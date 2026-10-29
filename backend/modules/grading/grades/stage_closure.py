"""Shared read-only closure classification and audited nonpassing finalization."""
import hashlib
import json

from django.core.exceptions import ValidationError
from django.utils import timezone

from .models import TeamGrade
from .outcome_rules import automatic_outcomes, outcome_payload


def unassessed_teams(semester, config, assessed_team_ids):
    """Use existing participation and stage context; a missing grade is not a failure."""
    from django.db.models import Q, F
    from student_teams.models import StudentTeam, TeamTermParticipation
    from student_teams.capstone_lifecycle import requirements_for, latest_stage_assessment, stage_cleared
    captured_ids = TeamTermParticipation.objects.filter(semester=semester, closed_at__isnull=True,
        project_version=F('team__project_version'), requirements__contains=[{'id': config.defense_stage_id}]
    ).values('team_id')
    teams = StudentTeam.objects.filter(semester=semester, level__icontains='Capstone').exclude(
        pk__in=assessed_team_ids).filter(Q(current_defense_stage=config.defense_stage.label) |
        Q(ready_for_stage=config.defense_stage.label) | Q(pk__in=captured_ids)).order_by('pk')
    rows = []
    for team in teams:
        requirement = next((r for r in requirements_for(team) if r['id'] == config.defense_stage_id), None)
        previous = latest_stage_assessment(team, config.defense_stage_id)
        if requirement and previous and stage_cleared(team, requirement, previous):
            continue
        rows.append({'team_id': team.pk, 'team_name': team.name, 'grade_id': None,
            'missing_components': ['initial_assessment'], 'closure_failure_eligible': False,
            'panel_complete': False, 'peer_complete': False, 'adviser_complete': False,
            'post_defense_complete': False})
    return rows


def eligible_failure(grade):
    if not automatic_outcomes(grade.schedule) or grade.verdict != 'for_redefense' or grade.closed_as_failed:
        return False
    if grade.status in TeamGrade.LOCKED_STATUSES or grade.project_version != grade.team.project_version:
        return False
    if grade.schedule.status != 'done' or grade.schedule.operation_state != 'normal':
        return False
    rule = outcome_payload(grade)
    if not rule or not rule['panel_complete'] or rule['outcome'] != 'for_redefense':
        return False
    from defense.scheduler.models import DefenseSchedule
    return not DefenseSchedule.objects.filter(team_id=grade.team_id, semester_id=grade.semester_id,
        defense_stage_id=grade.defense_stage_id, project_version=grade.project_version,
        scope='capstone', status='scheduled').exists()


def completion_token(grades, cohort, config):
    """Include live attempt/roster/config identities, never a client-authored list."""
    from defense.scheduler.models import DefenseSchedule
    rows = list(grades.order_by('pk').values('id', 'updated_at', 'schedule_id', 'project_version',
        'team__project_version', 'status', 'verdict', 'outcome_metadata'))
    schedules = list(DefenseSchedule.objects.filter(team_id__in=grades.values('team_id'),
        semester_id=config.semester_id, scope='capstone', defense_stage_id=config.defense_stage_id
    ).order_by('pk').values('id', 'updated_at', 'revision', 'operation_state', 'status', 'project_version', 'assessment_policy'))
    from repository.deliverables.models import DeliverableSubmissionFile, ConceptRound
    files = list(DeliverableSubmissionFile.objects.filter(submission__team_id__in=grades.values('team_id'),
        submission__stage_label=config.defense_stage.label).order_by('pk').values(
            'id', 'revision', 'is_current', 'status', 'reviewed_at', 'reviewed_by_id'))
    rounds = list(ConceptRound.objects.filter(team_id__in=grades.values('team_id'), defense_stage=config.defense_stage
        ).order_by('pk').values('id', 'schedule_id', 'project_version', 'concepts', 'verdict', 'policy_snapshot'))
    from defense.minutes.models import DefenseMinutes
    minutes = list(DefenseMinutes.objects.filter(schedule__team_id__in=grades.values('team_id'),
        schedule__semester_id=config.semester_id, schedule__scope='capstone',
        schedule__defense_stage_id=config.defense_stage_id).order_by('pk').values(
            'id', 'schedule_id', 'updated_at', 'status', 'pdf_file',
            'documenter_signed_at', 'adviser_signed_at', 'chairman_signed_at'))
    signature = [rows, cohort, schedules, files, rounds, minutes, str(config.updated_at), config.is_officially_complete]
    return hashlib.sha256(json.dumps(signature, sort_keys=True, default=str).encode()).hexdigest()


def finalize_failure(grade, actor, reason):
    from .defense_workflow import audit
    from .services import _apply_team_result_from_grade
    rule = outcome_payload(grade)
    if not eligible_failure(grade):
        raise ValidationError('The assessment or re-defense schedule changed. Review stage completion again.')
    now = timezone.now()
    grade.outcome_metadata = {**grade.outcome_metadata, 'closure': {
        'failed': True, 'actor_id': actor.pk, 'at': now.isoformat(), 'reason': reason.strip(),
        'hearing_outcome': grade.verdict, 'schedule_id': grade.schedule_id,
        'grade_id': grade.pk, 'team_id': grade.team_id, 'attempt_number': grade.attempt_count,
        'project_version': grade.project_version,
        'qualifying_score': rule['qualifying_score'], 'assessments': rule['assessments'],
    }}
    grade.status = TeamGrade.STATUS_PUBLISHED
    grade.published_by = actor
    grade.published_at = now
    grade.save()
    _apply_team_result_from_grade(grade)
    audit(grade, actor, 'defense.stage_closed_failed', reason=reason.strip(),
        hearing_outcome=grade.verdict, final_disposition='failed')


def validate_failure_confirmation(candidates, *, grade_ids, reason, token, expected_token):
    if token != expected_token:
        raise ValidationError('Stage readiness changed. Review the affected teams again before completing the stage.')
    expected = sorted(row['grade_id'] for row in candidates)
    if not isinstance(grade_ids, list) or any(type(pk) is not int for pk in grade_ids) or sorted(grade_ids) != expected:
        raise ValidationError('Explicitly confirm every named team to be finalized as Failed.')
    if expected and (not isinstance(reason, str) or not reason.strip() or len(reason) > 5000):
        raise ValidationError('Record the stage closure reason or institutional reference.')
