"""Review policy adoption; open shared scope has a separate evidence-preserving opt-in."""
from hashlib import sha256
import json

from django.core.management.base import BaseCommand, CommandError
from django.db import connection, transaction
from django.db.models import F, Q
from django.utils import timezone

from grading.grades.models import TeamGrade


def adoption_row(grade, *, review_open_scope=False):
    schedule = grade.schedule
    blockers = []
    if not grade.semester.is_active or grade.project_version != grade.team.project_version:
        blockers.append('Historical period or project')
    if schedule.status != 'scheduled' or schedule.operation_state != 'normal':
        blockers.append('Hearing is not an active normal schedule')
    if not review_open_scope and (grade.attempt_count != 1 or grade.attempt_history.exists()):
        blockers.append('An earlier attempt exists')
    if (grade.verdict or grade.status == 'published' or grade.closed_as_failed
            or (not review_open_scope and (grade.verdict_remarks or grade.outcome_metadata
            or any(getattr(grade, field) is not None for field in
                   ('panel_score', 'adviser_score', 'peer_score', 'final_grade'))
            or grade.panelist_submissions.exists() or grade.breakdowns.exists()
            or grade.peer_evaluation_submissions.exists()))):
        blockers.append('Assessment evidence or a recorded result already exists')
    if not review_open_scope and schedule.evaluation_drafts.exists():
        blockers.append('A private evaluation draft already exists')
    from defense.stages.models import StageGradingConfig
    if StageGradingConfig.objects.filter(semester=grade.semester, defense_stage=grade.defense_stage,
                                        is_officially_complete=True).exists():
        blockers.append('Stage is officially complete')
    from repository.deliverables.models import ConceptRound
    hearing = ConceptRound.objects.filter(schedule=schedule).select_related('section_round').first()
    if hearing and (hearing.verdict or (not review_open_scope and hearing.number != 1)):
        blockers.append('Concept hearing has already been decided or repeated')
    section = hearing.section_round if hearing else None
    if not review_open_scope and section and (section.presentation_started_at or section.verdict):
        blockers.append('The shared section hearing has started')
    context = []
    if review_open_scope:
        from django.core.exceptions import ValidationError
        from grading.grades.defense_workflow import require_current
        from grading.grades.outcome_rules import automatic_outcomes
        from defense.scheduler.panelist_evaluation import evaluation_context, validate_evaluation_submissions
        if not automatic_outcomes(schedule):
            blockers.append('Open scope review requires an already automatic hearing')
        if not section or not section.selected_key or section.verdict not in ('approved', 'approved_with_revisions'):
            blockers.append('A confirmed shared-system selection is required')
        if grade.semester_id != grade.team.semester_id:
            blockers.append('The team has moved to another academic period')
        try:
            require_current(grade)
        except ValidationError:
            blockers.append('The project or term participation is closed')
        current = ConceptRound.objects.filter(team_id=grade.team_id,
            project_version=grade.project_version, defense_stage_id=grade.defense_stage_id).order_by('-number', '-pk').first()
        if not hearing or not current or current.pk != hearing.pk:
            blockers.append('This is not the current assessed attempt')
        if section:
            from repository.section_concepts import services
            if services.latest(section.project).pk != section.pk:
                blockers.append('This is not the current shared proposal round')
        drafts = list(schedule.evaluation_drafts.order_by('pk'))
        immutable_context = evaluation_context(schedule, grade, include_scope=False)
        for draft in drafts:
            try:
                if draft.context_signature != immutable_context:
                    raise ValidationError('Stale draft context')
                validate_evaluation_submissions(schedule, draft.submissions, partial=True)
            except ValidationError:
                blockers.append('A private draft no longer matches the captured assessment')
                break
        context = [immutable_context, hearing.pk if hearing else None,
            [section.pk, section.selected_key, section.verdict] if section else None,
            [[d.pk, d.context_signature, str(d.updated_at), d.submissions] for d in drafts]]
    return {'grade_id': grade.pk, 'team_name': grade.team.name, 'schedule_id': schedule.pk,
            'stage_label': grade.stage_label, 'semester_id': grade.semester_id,
            'captured_cutoff': schedule.assessment_policy.get('qualifying_score'),
            'selected_key': section.selected_key if section else '',
            'preserved_draft_count': len(drafts) if review_open_scope else 0,
            'eligible': not blockers, 'blockers': blockers,
            'review_context': [str(grade.updated_at), str(schedule.updated_at), schedule.revision,
                               schedule.assessment_policy, context]}


class Command(BaseCommand):
    help = 'Read-only by default. Explicit adoption requires named schedules, the current review token, and a reason.'

    def add_arguments(self, parser):
        parser.add_argument('--schedule-id', nargs='+', type=int, default=[])
        parser.add_argument('--apply', action='store_true')
        parser.add_argument('--review-token')
        parser.add_argument('--reason', default='')
        parser.add_argument('--shared-module-scope', action='store_true',
            help='Review selected-module-only scope for unstarted captured shared hearings.')
        parser.add_argument('--review-open-shared-scope', action='store_true',
            help='Explicitly review current undecided automatic hearings after shared selection; retain valid drafts and submissions.')

    def handle(self, *args, **options):
        apply = options['apply']
        ids = options['schedule_id']
        shared_scope = options['shared_module_scope']
        review_open_scope = options['review_open_shared_scope']
        if review_open_scope and not shared_scope:
            raise CommandError('Open shared review requires --shared-module-scope.')
        if apply and (not ids or not options['review_token'] or not options['reason'].strip()):
            raise CommandError('Name the schedules and provide the reviewed token and adoption reason.')
        if len(options['reason']) > 5000:
            raise CommandError('Use an adoption reason of up to 5000 characters.')
        already_atomic = connection.in_atomic_block
        with transaction.atomic():
            if not apply and not already_atomic and connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SET TRANSACTION READ ONLY')
            grades = TeamGrade.objects.filter(scope='capstone', schedule__assessment_policy__version=1)
            if shared_scope:
                grades = grades.filter(schedule__concept_round__section_round__isnull=False,
                    schedule__assessment_policy__per_concept=True).filter(
                    Q(schedule__assessment_policy__shared_module_scope_version=0) |
                    Q(schedule__assessment_policy__shared_module_scope_version__isnull=True))
            else:
                grades = grades.filter(
                    Q(schedule__assessment_policy__automatic_outcomes=False) |
                    Q(schedule__assessment_policy__automatic_outcomes__isnull=True))
            grades = grades.order_by('pk')
            if ids:
                grades = grades.filter(schedule_id__in=ids)
            if apply:
                from student_teams.models import StudentTeam
                from defense.scheduler.models import DefenseSchedule
                if review_open_scope:
                    from repository.section_concepts.models import SectionConceptProject, SectionConceptRound
                    project_ids = grades.values('schedule__concept_round__section_round__project_id')
                    list(SectionConceptProject.objects.select_for_update().filter(pk__in=project_ids).order_by('pk'))
                    round_ids = grades.values('schedule__concept_round__section_round_id')
                    list(SectionConceptRound.objects.select_for_update().filter(pk__in=round_ids).order_by('pk'))
                list(StudentTeam.objects.select_for_update().filter(pk__in=grades.values('team_id')).order_by('pk'))
                list(DefenseSchedule.objects.select_for_update().filter(pk__in=ids).order_by('pk'))
                grades = grades.select_for_update(of=('self',))
            grades = list(grades.select_related('team', 'semester', 'schedule'))
            rows = [adoption_row(grade, review_open_scope=review_open_scope) for grade in grades]
            token = sha256(json.dumps({'shared_module_scope': shared_scope,
                'review_open_scope': review_open_scope, 'hearings': rows},
                sort_keys=True, default=str).encode()).hexdigest()
            if apply:
                if sorted(set(ids)) != sorted(row['schedule_id'] for row in rows):
                    raise CommandError('Every named schedule must still match the requested captured Capstone policy.')
                if token != options['review_token'] or any(not row['eligible'] for row in rows):
                    raise CommandError('The hearing review changed or includes ineligible/historical evidence. No adoption applied.')
                from grading.grades.defense_workflow import audit
                from defense.scheduler.models import DefenseSchedule
                now = timezone.now()
                for grade in grades:
                    before = grade.schedule.assessment_policy
                    mode = 'shared_module_scope_version' if shared_scope else 'automatic_outcomes'
                    policy = {**before, mode: 1 if shared_scope else True,
                        'shared_module_scope_adoption' if shared_scope else 'automatic_outcome_adoption': {
                        'at': now.isoformat(), 'reason': options['reason'].strip(),
                        'prior_policy_hash': sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()}}
                    # Only the captured mode changes. Avoid schedule.save()'s
                    # unrelated readiness side effects; keep all existing inputs.
                    DefenseSchedule.objects.filter(pk=grade.schedule_id).update(
                        assessment_policy=policy, revision=F('revision') + 1, updated_at=now)
                    if review_open_scope:
                        from defense.scheduler.panelist_evaluation import evaluation_context
                        grade.schedule.refresh_from_db()
                        # Only matching, validated drafts reached this point. Change
                        # their context binding, never their scores or submit state.
                        grade.schedule.evaluation_drafts.update(context_signature=
                            evaluation_context(grade.schedule, grade, include_scope=False))
                    audit(grade, None, 'defense.shared_module_scope_adopted' if shared_scope else 'defense.automatic_policy_adopted', reason=options['reason'].strip(),
                          schedule_id=grade.schedule_id, prior_policy=before, adopted_policy=policy,
                          reviewed_open_scope=review_open_scope)
                if review_open_scope:
                    from grading.grades.automatic_outcomes import resolve_outcome
                    for grade in grades:
                        resolve_outcome(grade)
            for row in rows:
                row.pop('review_context')
        self.stdout.write(json.dumps({'read_only': not apply, 'count': len(rows),
            'policy': 'shared_module_scope' if shared_scope else 'automatic_outcomes',
            'reviewed_open_scope': review_open_scope,
            'review_token': token, 'hearings': rows, 'adopted_count': len(rows) if apply else 0}, indent=2))
