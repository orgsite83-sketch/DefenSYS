"""Report captured hearings; explicitly adopt only reviewed, unstarted hearings."""
from hashlib import sha256
import json

from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction
from django.db.models import F, Q
from django.utils import timezone

from grading.grades.models import TeamGrade


def adoption_row(grade):
    schedule = grade.schedule
    blockers = []
    if not grade.semester.is_active or grade.project_version != grade.team.project_version:
        blockers.append('Historical period or project')
    if schedule.status != 'scheduled' or schedule.operation_state != 'normal':
        blockers.append('Hearing is not an active normal schedule')
    if grade.attempt_count != 1 or grade.attempt_history.exists():
        blockers.append('An earlier attempt exists')
    if (grade.verdict or grade.verdict_remarks or grade.outcome_metadata or grade.status == 'published'
            or any(getattr(grade, field) is not None for field in
                   ('panel_score', 'adviser_score', 'peer_score', 'final_grade'))
            or grade.panelist_submissions.exists() or grade.breakdowns.exists()
            or grade.peer_evaluation_submissions.exists()):
        blockers.append('Assessment evidence or a recorded result already exists')
    if schedule.evaluation_drafts.exists():
        blockers.append('A private evaluation draft already exists')
    from defense.stages.models import StageGradingConfig
    if StageGradingConfig.objects.filter(semester=grade.semester, defense_stage=grade.defense_stage,
                                        is_officially_complete=True).exists():
        blockers.append('Stage is officially complete')
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule=schedule).select_related('section_round').first()
    if hearing and (hearing.verdict or hearing.number != 1):
        blockers.append('Concept hearing has already been decided or repeated')
    section = hearing.section_round if hearing else None
    if section and (section.presentation_started_at or section.verdict):
        blockers.append('The shared section hearing has started')
    return {'grade_id': grade.pk, 'team_name': grade.team.name, 'schedule_id': schedule.pk,
            'stage_label': grade.stage_label, 'semester_id': grade.semester_id,
            'captured_cutoff': schedule.assessment_policy.get('qualifying_score'),
            'eligible': not blockers, 'blockers': blockers,
            'review_context': [str(grade.updated_at), str(schedule.updated_at), schedule.revision,
                               schedule.assessment_policy]}


class Command(BaseCommand):
    help = 'Read-only by default. Explicit adoption requires named schedules, the current review token, and a reason.'

    def add_arguments(self, parser):
        parser.add_argument('--schedule-id', nargs='+', type=int, default=[])
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--review-token')
        parser.add_argument('--reason', default='')

    def handle(self, *args, **options):
        apply = options['apply']
        ids = options['schedule_id']
        if apply and (not ids or not options['review_token'] or not options['reason'].strip()):
            raise CommandError('Name the schedules and provide the reviewed token and adoption reason.')
        if len(options['reason']) > 5000:
            raise CommandError('Use an adoption reason of up to 5000 characters.')
        already_atomic = connection.in_atomic_block
        with transaction.atomic():
            if not apply and not already_atomic and connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
            grades = TeamGrade.objects.filter(scope='capstone',
                schedule__assessment_policy__version=1).filter(
                    Q(schedule__assessment_policy__automatic_outcomes=False) |
                    Q(schedule__assessment_policy__automatic_outcomes__isnull=True)).order_by('pk')
            if ids:
                grades = grades.filter(schedule_id__in=ids)
            if apply:
                from student_teams.models import StudentTeam
                from defense.scheduler.models import DefenseSchedule
                list(StudentTeam.objects.select_for_update().filter(pk__in=grades.values('team_id')).order_by('pk'))
                list(DefenseSchedule.objects.select_for_update().filter(pk__in=ids).order_by('pk'))
                grades = grades.select_for_update(of=('self',))
            grades = list(grades.select_related('team', 'semester', 'schedule'))
            rows = [adoption_row(grade) for grade in grades]
            token = sha256(json.dumps(rows, sort_keys=True, default=str).encode()).hexdigest()
            if apply:
                if sorted(set(ids)) != sorted(row['schedule_id'] for row in rows):
                    raise CommandError('Every named schedule must still be a captured manual Capstone hearing.')
                if token != options['review_token'] or any(not row['eligible'] for row in rows):
                    raise CommandError('The hearing review changed or includes started/historical evidence. No adoption applied.')
                from grading.grades.defense_workflow import audit
                from defense.scheduler.models import DefenseSchedule
                now = timezone.now()
                for grade in grades:
                    before = grade.schedule.assessment_policy
                    policy = {**before, 'automatic_outcomes': True, 'automatic_outcome_adoption': {
                        'at': now.isoformat(), 'reason': options['reason'].strip(),
                        'prior_policy_hash': sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()}}
                    # Only the captured mode changes. Avoid schedule.save()'s
                    # unrelated readiness side effects; keep all existing inputs.
                    DefenseSchedule.objects.filter(pk=grade.schedule_id).update(
                        assessment_policy=policy, revision=F('revision') + 1, updated_at=now)
                    audit(grade, None, 'defense.automatic_policy_adopted', reason=options['reason'].strip(),
                          schedule_id=grade.schedule_id, prior_policy=before, adopted_policy=policy)
            for row in rows:
                row.pop('review_context')
        self.stdout.write(json.dumps({'read_only': not apply, 'count': len(rows),
            'review_token': token, 'hearings': rows, 'adopted_count': len(rows) if apply else 0}, indent=2))
