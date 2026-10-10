"""Remove only peer-only records created for unendorsed, unscheduled teams."""
import json
from pathlib import Path

from django.core import serializers
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.models import DefenseSchedule
from student_teams.models import StudentTeam
from student_teams.services import was_stage_endorsed
from .models import TeamGrade


def cleanup_candidates(semester_id, stage_label):
    return TeamGrade.objects.filter(semester_id=semester_id, scope='capstone',
        stage_label=stage_label, schedule__isnull=True).select_related('team', 'semester', 'defense_stage').order_by('pk')


def validate_cleanup_grade(grade):
    """Never discard a legitimate attempt or any non-peer assessment evidence."""
    if (grade.scope != 'capstone' or grade.schedule_id or not grade.semester.is_active
            or grade.team.semester_id != grade.semester_id
            or grade.project_version != grade.team.project_version):
        raise ValidationError(f'Grade {grade.pk} is not an unscheduled current Capstone context.')
    if grade.team.ready_for_stage == grade.stage_label or (
            grade.defense_stage_id and was_stage_endorsed(grade.team, grade.defense_stage)):
        raise ValidationError(f'Grade {grade.pk} belongs to an endorsed team.')
    schedules = DefenseSchedule.objects.filter(team_id=grade.team_id, semester_id=grade.semester_id,
        project_version=grade.project_version, scope='capstone')
    schedules = schedules.filter(defense_stage_id=grade.defense_stage_id) if grade.defense_stage_id else schedules.filter(defense_stage__label=grade.stage_label)
    if schedules.exists():
        raise ValidationError(f'Grade {grade.pk} has a defense schedule for this stage.')
    if (grade.panel_score is not None or grade.adviser_score is not None or grade.final_grade is not None
            or grade.status != TeamGrade.STATUS_PENDING or grade.verdict or grade.verdict_remarks
            or grade.verdict_at or grade.published_at or grade.attempt_count != 1
            or grade.peer_score_is_override):
        raise ValidationError(f'Grade {grade.pk} contains protected grading evidence.')
    for row in grade.student_grades.all():
        if row.panel_score is not None or row.adviser_score is not None or row.final_grade is not None:
            raise ValidationError(f'Grade {grade.pk} has non-peer student scores.')
    if grade.breakdowns.exclude(evaluation_type='peer').exists():
        raise ValidationError(f'Grade {grade.pk} has non-peer criterion scores.')
    for relation in TeamGrade._meta.related_objects:
        name = relation.get_accessor_name()
        if name not in {'student_grades', 'peer_evaluation_submissions', 'breakdowns'} and getattr(grade, name).exists():
            raise ValidationError(f'Grade {grade.pk} has protected {name} records.')


def preview_cleanup(semester_id, stage_label):
    result = []
    for grade in cleanup_candidates(semester_id, stage_label):
        validate_cleanup_grade(grade)
        result.append({'grade_id': grade.pk, 'team_id': grade.team_id, 'team_name': grade.team.name,
            'peer_submissions': grade.peer_evaluation_submissions.count(),
            'student_summaries': grade.student_grades.count()})
    return result


@transaction.atomic
def remove_unscheduled_peer_grades(*, semester_id, stage_label, grade_ids, backup_path, reason):
    expected = set(grade_ids)
    if not expected or len(expected) != len(grade_ids) or not reason.strip():
        raise ValidationError('Specify distinct reviewed grade IDs and a cleanup reason.')
    candidate_ids = set(cleanup_candidates(semester_id, stage_label).values_list('pk', flat=True))
    if candidate_ids != expected:
        raise ValidationError('The cleanup candidates changed. Review a new preview before applying.')
    team_ids = list(TeamGrade.objects.filter(pk__in=expected).values_list('team_id', flat=True))
    list(StudentTeam.objects.select_for_update().filter(pk__in=team_ids).order_by('pk'))
    grades = list(cleanup_candidates(semester_id, stage_label).select_for_update(of=('self',)))
    if {grade.pk for grade in grades} != expected:
        raise ValidationError('The cleanup candidates changed while acquiring locks.')
    objects, removed_submissions, removed_summaries = [], 0, 0
    for grade in grades:
        validate_cleanup_grade(grade)
        submissions = list(grade.peer_evaluation_submissions.all())
        summaries = list(grade.student_grades.all())
        objects.extend([grade, *submissions, *summaries, *grade.breakdowns.all()])
        removed_submissions += len(submissions)
        removed_summaries += len(summaries)
    backup = {'created_at': timezone.now().isoformat(), 'semester_id': semester_id,
        'stage_label': stage_label, 'reason': reason, 'grade_ids': sorted(expected),
        'objects': json.loads(serializers.serialize('json', objects))}
    path = Path(backup_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation ensures a previous recovery copy can never be overwritten.
    with path.open('x', encoding='utf-8') as handle:
        json.dump(backup, handle, indent=2)
    for grade in grades:
        log_high_impact_action(category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='grade.remove_premature_peer_evaluations', target=grade, reason=reason,
            old_values={'team_id': grade.team_id, 'stage_label': stage_label,
                'semester_id': semester_id, 'peer_score': str(grade.peer_score),
                'peer_submissions': grade.peer_evaluation_submissions.count()},
            new_values={'removed_peer_only_grade': True, 'backup_path': str(path)}, strict=True)
        grade.delete()
    return {'removed_grades': len(grades), 'removed_peer_submissions': removed_submissions,
        'removed_student_summaries': removed_summaries, 'backup_path': str(path)}
