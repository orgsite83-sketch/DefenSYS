"""Read-only inventory by default; no historical decisions are synthesized."""
import json
from hashlib import sha256

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction
from django.db.models import F
from django.utils import timezone

from grading.grades.models import TeamGrade


def review_row(grade):
    from grading.grades.defense_workflow import require_current
    from defense.stages.revision_policy import validate_revision_areas
    from defense.stages.models import StageGradingConfig
    from defense.minutes.models import DefenseMinutes
    from grading.grades.dissemination_models import OutcomeRelease
    from repository.deliverables.models import ConceptRound
    from django.core.exceptions import ValidationError
    schedule = grade.schedule
    blockers = []
    areas = []
    try:
        areas = validate_revision_areas(grade.defense_stage.revision_areas)
        require_current(grade)
    except ValidationError as exc:
        blockers.extend(exc.messages)
    if not areas:
        blockers.append('Configure revision areas before adoption')
    if not grade.semester.is_active or grade.team.semester_id != grade.semester_id:
        blockers.append('The hearing is not in the active team participation')
    if schedule.status != 'scheduled' or schedule.operation_state != 'normal':
        blockers.append('The hearing is not open and normal')
    if schedule.assessment_policy.get('deliberation_version') == 1:
        blockers.append('The hearing already uses chair deliberation')
    if (grade.verdict or grade.closed_as_failed or grade.status == 'published'
            or hasattr(schedule, 'official_outcome') or OutcomeRelease.objects.filter(control__schedule=schedule).exists()):
        blockers.append('A protected decision, publication, release, or closure exists')
    if DefenseMinutes.objects.filter(schedule=schedule).exclude(status='draft').exists():
        blockers.append('The minutes signing process has started')
    if grade.corrections.filter(status='pending').exists():
        blockers.append('An assessment correction is awaiting review')
    from defense.scheduler.models import DefenseSchedule
    if DefenseSchedule.objects.filter(team=grade.team, project_version=grade.project_version,
            defense_stage=grade.defense_stage, pk__gt=schedule.pk).exists():
        blockers.append('A later defense schedule exists')
    if StageGradingConfig.objects.filter(semester=grade.semester, defense_stage=grade.defense_stage,
                                        is_officially_complete=True).exists():
        blockers.append('The stage is officially complete')
    hearing = ConceptRound.objects.filter(schedule=schedule).first()
    if hearing and (hearing.verdict or ConceptRound.objects.filter(team=grade.team,
            defense_stage=grade.defense_stage, project_version=grade.project_version, number__gt=hearing.number).exists()):
        blockers.append('A concept decision or later attempt exists')
    from defense.scheduler.panelist_evaluation import evaluation_context, validate_evaluation_submissions
    context = evaluation_context(schedule, grade, include_scope=False)
    for draft in schedule.evaluation_drafts.all():
        try:
            if draft.context_signature != context:
                raise ValidationError('Private draft context is stale')
            validate_evaluation_submissions(schedule, draft.submissions, partial=True)
        except ValidationError:
            blockers.append('A private evaluation draft no longer matches this captured hearing')
            break
    return {'grade_id': grade.pk, 'schedule_id': schedule.pk, 'team_name': grade.team.name,
        'stage_label': grade.stage_label, 'eligible': not blockers, 'blockers': blockers,
        'revision_areas': areas, 'review_context': [context, schedule.assessment_policy, schedule.revision,
            str(schedule.updated_at), str(grade.updated_at),
            list(schedule.evaluation_drafts.order_by('pk').values('pk', 'updated_at', 'context_signature', 'submissions'))]}


class Command(BaseCommand):
    help = 'Inventory unresolved Capstone hearings. Explicit reviewed adoption preserves captured grading inputs.'

    def add_arguments(self, parser):
        parser.add_argument('--schedule-id', nargs='+', type=int, default=[])
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--review-token')
        parser.add_argument('--actor-id', type=int)
        parser.add_argument('--reason', default='')

    def handle(self, *args, **options):
        apply = options['apply']
        ids = options['schedule_id']
        actor = None
        if apply:
            if not ids or not options['review_token'] or not 5 <= len(options['reason'].strip()) <= 2000:
                raise CommandError('Name schedules and provide the reviewed token and a reason of 5–2000 characters.')
            from authentication_access_control.scopes import is_admin_user
            actor = get_user_model().objects.filter(pk=options['actor_id'], is_active=True).first()
            if not actor or not is_admin_user(actor):
                raise CommandError('Provide the identity of an active authorized administrator.')
        was_atomic = connection.in_atomic_block
        with transaction.atomic():
            if not apply and not was_atomic and connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
            query = TeamGrade.objects.filter(scope='capstone', schedule__assessment_policy__version=1)
            if ids:
                query = query.filter(schedule_id__in=ids)
            if apply:
                from student_teams.models import StudentTeam
                from defense.scheduler.models import DefenseSchedule
                list(StudentTeam.objects.select_for_update().filter(pk__in=query.values('team_id')).order_by('pk'))
                list(DefenseSchedule.objects.select_for_update().filter(pk__in=ids).order_by('pk'))
                query = query.select_for_update(of=('self',))
            grades = list(query.select_related('schedule', 'team', 'semester', 'defense_stage').order_by('pk'))
            rows = [review_row(grade) for grade in grades]
            token = sha256(json.dumps(rows, sort_keys=True, default=str).encode()).hexdigest()
            if apply:
                if (sorted(set(ids)) != sorted(row['schedule_id'] for row in rows)
                        or token != options['review_token'] or any(not row['eligible'] for row in rows)):
                    raise CommandError('The review is stale or includes a protected hearing. Nothing was adopted.')
                from defense.scheduler.models import DefenseSchedule
                from defense.scheduler.panelist_evaluation import evaluation_context
                from grading.grades.defense_workflow import audit
                for grade, row in zip(grades, rows):
                    before = grade.schedule.assessment_policy
                    policy = {**before, 'deliberation_version': 1, 'automatic_outcomes': True,
                        'revision_areas': row['revision_areas'],
                        'deliberation_adoption': {'actor_id': actor.pk, 'reason': options['reason'].strip(),
                                                 'at': timezone.now().isoformat()}}
                    DefenseSchedule.objects.filter(pk=grade.schedule_id).update(assessment_policy=policy,
                        revision=F('revision') + 1, updated_at=timezone.now())
                    grade.schedule.refresh_from_db()
                    grade.schedule.evaluation_drafts.update(context_signature=evaluation_context(grade.schedule, grade, include_scope=False))
                    audit(grade, actor, 'defense.deliberation_policy_adopted', prior_policy=before,
                          adopted_policy=policy, reason=options['reason'].strip())
            for row in rows:
                row.pop('review_context')
        self.stdout.write(json.dumps({'read_only': not apply, 'review_token': token,
            'hearings': rows, 'adopted_count': len(rows) if apply else 0}, indent=2))
