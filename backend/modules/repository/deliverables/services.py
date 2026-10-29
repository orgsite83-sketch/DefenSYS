from student_teams.pit_rosters import endorsed as pit_endorsed, set_endorsed as set_pit_endorsed
from defensys_backend.file_cleanup import delete_repository_file_on_commit, replacement_file_name
from defensys_backend.read_projection import read_memoize
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from django.db.models import Prefetch, Q

from academic_period_management.models import Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam, TeamStageProgress
from student_teams.services import is_stage_ready, mark_stage_locked, mark_stage_ready, was_stage_endorsed
from .models import DeliverableSubmission
from .timing import scheduling_requirement
from .concepts import stage_for as document_context


@read_memoize(copy=True)
def _active_stage_labels():
    try:
        return list(DefenseStage.objects.filter(is_active=True)
                    .order_by('display_order', 'label').values_list('label', flat=True))
    except Exception:
        return []


class DynamicStageOptionsList(list):
    def _get_stages(self):
        return _active_stage_labels()

    def __iter__(self):
        return iter(self._get_stages())

    def __len__(self):
        return len(self._get_stages())

    def __getitem__(self, index):
        return self._get_stages()[index]

    def __add__(self, other):
        return self._get_stages() + list(other)

    def __radd__(self, other):
        return list(other) + self._get_stages()

    def __repr__(self):
        return repr(self._get_stages())

    def __contains__(self, item):
        return item in self._get_stages()

STAGE_OPTIONS = DynamicStageOptionsList()


def default_stage_label():
    stages = list(STAGE_OPTIONS)
    return stages[0] if stages else ''


@read_memoize(copy=True)
def get_deliverable_definitions(stage_label):
    """Load deliverable definitions configured in Defense Stages (database only)."""
    try:
        stage = DefenseStage.objects.prefetch_related('deliverables').get(label=stage_label)
        deliverables = stage.deliverables.all()
        definitions = [
            {
                'id': (d.deliverable_id or '').strip(),
                'label': d.label,
                'required': d.required,
                'requirement_timing': d.requirement_timing,
                'deadline_hours_before': d.deadline_hours_before,
                'type': d.deliverable_type,
                'archive_note': d.archive_note,
                'archive_file_template': d.archive_file_template,
                'is_restricted': d.is_restricted,
                'is_defense_material': getattr(d, 'is_defense_material', False),
                'verdict_condition': getattr(d, 'verdict_condition', 'all_pass'),
                'file_format': getattr(d, 'file_format', 'any') or 'any',
                'file_policy': getattr(d, 'file_policy', {}) or {},
            }
            for d in deliverables
            if (d.deliverable_id or '').strip()
        ]
        from defense.minutes.requirements import minutes_definition
        generated = minutes_definition(stage)
        if generated:
            definitions.append(generated)
        from defense.deliverable_policy import faculty_review_definition
        return [faculty_review_definition(item) for item in definitions]
    except DefenseStage.DoesNotExist:
        return []


@read_memoize(copy=True)
def get_deliverable_definitions_for_team(team, stage_label):
    """Load deliverable definitions configured for a Capstone stage or PIT event."""
    if not team or not stage_label:
        return []
    from copy import deepcopy
    captured = getattr(team, '_capstone_requirement', None)
    if not captured and team.is_capstone:
        from student_teams.capstone_lifecycle import requirement_for_label
        captured = requirement_for_label(team, stage_label)
    definitions = (deepcopy(captured['definitions']) if captured and 'definitions' in captured else
        get_deliverable_definitions_for_scope('capstone' if team.is_capstone else 'pit', team.semester_id, stage_label, year_level=team.year_level))
    if any((d.get('file_policy') or {}).get('mode') == 'concepts' for d in definitions):
        from student_teams.concept_policy import resolve_policy
        stage = document_context(team, stage_label)
        if not stage or not stage.concept_config.get('enabled'):
            return [d for d in definitions if (d.get('file_policy') or {}).get('mode') != 'concepts']
        policy = resolve_policy(team, stage)
        for definition in definitions:
            if (definition.get('file_policy') or {}).get('mode') == 'concepts':
                definition['concept_policy'] = policy
    from defense.deliverable_policy import apply_hearing_policy
    from .timing import stage_schedule
    from .concepts import latest_round
    context = document_context(team, stage_label)
    hearing = latest_round(team, context) if context else None
    grade = latest_stage_grade(team, stage_label, scope='capstone' if team.is_capstone else 'pit')
    # A new concept set or a pending re-defense must not borrow the previous
    # hearing's completed exemptions.
    if hearing:
        schedule = hearing.schedule if hearing.schedule_id else None
    elif grade and grade.verdict == 'for_redefense':
        schedule = None
    else:
        schedule = stage_schedule(team, stage_label)
    return apply_hearing_policy(definitions, schedule, grade=grade)


@read_memoize(copy=True)
def get_deliverable_definitions_for_scope(scope, semester_id, stage_label, *, year_level=None):
    """Use the record's term/scope when reading historical defenses."""
    if scope == 'capstone':
        return get_deliverable_definitions(stage_label)
    
    # It's a PIT team! stage_label here is the event name.
    from defense.scheduler.models import PitEventGradingConfig
    config = PitEventGradingConfig.objects.filter(
        semester_id=semester_id,
        **({"year_level": year_level} if year_level is not None else {}),
        event_name__iexact=stage_label.strip()
    ).prefetch_related('deliverables').first()
    if not config:
        return []
    return [
        {
            'id': (d.deliverable_id or '').strip(),
            'label': d.label,
            'required': d.required,
            'requirement_timing': 'scheduling',
            'deadline_hours_before': 24,
            'type': d.deliverable_type,
            'archive_note': d.archive_note,
            'archive_file_template': d.archive_file_template,
            'is_restricted': d.is_restricted,
            'is_defense_material': getattr(d, 'is_defense_material', False),
            'verdict_condition': 'all_pass',
            'file_format': getattr(d, 'file_format', 'any') or 'any',
            'file_policy': getattr(d, 'file_policy', {}) or {},
        }
        for d in config.deliverables.all().order_by('display_order', 'deliverable_id')
        if (d.deliverable_id or '').strip()
    ]


def deliverable_definitions_for_stage(stage_label):
    """Runtime source of truth: admin-configured StageDeliverable rows only."""
    return get_deliverable_definitions(stage_label)


def display_name(user):
    if user is None:
        return None
    full_name = f'{user.first_name} {user.last_name}'.strip()
    return full_name or user.username


from academic_period_management.services import active_semester


@read_memoize
def defense_stage_for_label(stage_label):
    return DefenseStage.objects.filter(label=stage_label).first()


def definition_for(team, stage_label, deliverable_id):
    deliverable_id = (deliverable_id or '').strip()
    if not deliverable_id:
        return None
    for item in get_deliverable_definitions_for_team(team, stage_label):
        if item['id'] == deliverable_id:
            return item
    return None


@read_memoize
def current_stage_for_team(team):
    if not team:
        return default_stage_label()
    if team.is_capstone:
        from defense.scheduler.models import DefenseSchedule
        from student_teams.capstone_context import phase_requirements
        from student_teams.capstone_lifecycle import stage_cleared
        required = phase_requirements(team)
        if not required:
            return None
        labels = dict(DefenseStage.objects.filter(pk__in=[r['id'] for r in required]).values_list('pk', 'label'))

        # 1. If currently scheduled, the scheduled stage is active
        sched = (
            DefenseSchedule.objects.filter(
                team=team,
                semester=team.semester,
        project_version=team.project_version,
                scope=DefenseSchedule.SCOPE_CAPSTONE,
                status=DefenseSchedule.STATUS_SCHEDULED,
            )
            .select_related('defense_stage')
            .order_by('scheduled_date', 'start_time')
            .first()
        )
        if sched and sched.defense_stage:
            return sched.defense_stage.label

        for requirement in required:
            if not stage_cleared(team, requirement):
                return labels.get(requirement['id'], requirement['label'])
        return labels.get(required[-1]['id'], required[-1]['label'])
    else:
        # For PIT: find the scheduled schedule or the first event config
        from defense.scheduler.models import DefenseSchedule
        from defense.scheduler.event_scope import pit_events_for_team
        allowed_events = pit_events_for_team(team).values('event_name')
        sched = (
            DefenseSchedule.objects.filter(
                team=team,
                semester=team.semester,
                event_name__in=allowed_events,
        project_version=team.project_version,
                scope=DefenseSchedule.SCOPE_PIT,
                status=DefenseSchedule.STATUS_SCHEDULED,
            )
            .order_by('scheduled_date', 'start_time')
            .first()
        )
        if sched and sched.event_name:
            return sched.event_name
        
        # Or, if they have configured events for this semester,
        # find the first event for which they don't have a STATUS_DONE schedule.
        from defense.scheduler.models import PitEventGradingConfig
        from defense.scheduler.event_scope import pit_events_for_team
        configs_qs = pit_events_for_team(team)
        configs = list(configs_qs.order_by('event_name'))
        if configs:
            from .models import DeliverableSubmission
            completed_events = set()
            for config in configs:
                if config.is_officially_complete:
                    completed_events.add(config.event_name)
                    continue

                has_done_sched = DefenseSchedule.objects.filter(
                    team=team,
        project_version=team.project_version,
                    scope=DefenseSchedule.SCOPE_PIT,
                    event_name__iexact=config.event_name,
                    status=DefenseSchedule.STATUS_DONE,
                ).exists()

                if has_done_sched:
                    req_deliv_ids = set(
                        config.deliverables.filter(required=True).values_list('deliverable_id', flat=True)
                    )
                    if req_deliv_ids:
                        submitted_deliv_ids = set(
                            DeliverableSubmission.objects.filter(
                                team=team,
                                stage_label__iexact=config.event_name,
                                deliverable_id__in=req_deliv_ids,
                            ).values_list('deliverable_id', flat=True)
                        )
                        if req_deliv_ids.issubset(submitted_deliv_ids):
                            completed_events.add(config.event_name)
                    else:
                        completed_events.add(config.event_name)

            for config in configs:
                if config.event_name not in completed_events:
                    return config.event_name
            return configs[-1].event_name

        # Fall back to any scheduled schedule, or first event config
        sched_any = (
            DefenseSchedule.objects.filter(
                team=team,
                semester=team.semester,
                event_name__in=allowed_events,
        project_version=team.project_version,
                scope=DefenseSchedule.SCOPE_PIT,
            )
            .order_by('-scheduled_date', '-start_time')
            .first()
        )
        if sched_any and sched_any.event_name:
            return sched_any.event_name
            
        return 'No PIT event configured'


def team_queryset_for_user(user, *, include_pit_lead=True):
    queryset = (
        StudentTeam.objects.select_related(
            'semester',
            'semester__school_year',
            'leader',
            'adviser',
        )
        .prefetch_related(
            'roster_details',
            'memberships',
            'memberships__student',
            Prefetch('deliverable_submissions', queryset=DeliverableSubmission.objects.select_related(
                'uploaded_by', 'reviewed_by',
            ).defer('extracted_text', 'topics', 'summary', 'classification').prefetch_related('files')),
        )
    )

    if getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False):
        return queryset
    if getattr(user, 'role', None) == 'faculty':
        q = Q()
        if getattr(user, 'is_adviser', False):
            q |= Q(adviser=user)
        if include_pit_lead and getattr(user, 'is_pit_lead', False):
            pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
            if pit_year:
                q |= Q(year_level=pit_year, level__icontains='PIT')
        
        # Section Instructors
        from user_management.models import SectionInstructorAssignment
        from student_teams.team_levels import normalize_year_level
        assignments = SectionInstructorAssignment.objects.filter(faculty=user, is_active=True)
        if assignments.exists():
            for assign in assignments:
                norm_year = normalize_year_level(assign.year_level)
                q |= Q(
                    semester=assign.semester,
                    section=assign.section,
                    year_level=norm_year,
                    level__icontains='PIT',
                )

        return queryset.filter(q) if q else queryset.none()
    if getattr(user, 'role', None) == 'student':
        return queryset.filter(memberships__student=user).distinct()
    return queryset.none()


def filter_teams(request, queryset):
    event_name = request.query_params.get('stage_label') or request.query_params.get('event_name')
    if event_name:
        from student_teams.pit_rosters import filter_teams as roster_teams
        queryset = queryset.exclude(level__icontains='PIT') | roster_teams(queryset.filter(level__icontains='PIT'), event_name)
    search = request.query_params.get('search', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    year_level = request.query_params.get('year_level', '').strip()
    section = request.query_params.get('section', '').strip()
    team_id = request.query_params.get('team_id', '').strip()

    if team_id:
        queryset = queryset.filter(pk=team_id)

    if year_level:
        queryset = queryset.filter(year_level=year_level)

    if section:
        queryset = queryset.filter(section=section)

    if search:
        queryset = queryset.filter(
            Q(name__icontains=search)
            | Q(project_title__icontains=search)
            | Q(leader__first_name__icontains=search)
            | Q(leader__last_name__icontains=search)
            | Q(adviser__first_name__icontains=search)
            | Q(adviser__last_name__icontains=search)
            | Q(adviser__username__icontains=search)
        ).distinct()

    if event_name and status_filter in ('ready', 'endorsed', 'awaiting_endorsement', 'pending_endorsement'):
        want_ready = status_filter in ('ready', 'endorsed')
        queryset = queryset.filter(pk__in=[t.pk for t in queryset if (
            pit_endorsed(t, event_name) if t.is_pit else bool(t.ready_for_stage)) == want_ready])
    elif status_filter in ('ready', 'endorsed'):
        queryset = queryset.exclude(ready_for_stage__isnull=True).exclude(ready_for_stage='')
    elif status_filter in ('awaiting_endorsement', 'pending_endorsement'):
        queryset = queryset.filter(Q(ready_for_stage__isnull=True) | Q(ready_for_stage=''))
    elif status_filter == 'scheduled':
        from student_teams.models import TeamStageProgress
        scheduled_ids = TeamStageProgress.objects.filter(status=TeamStageProgress.STATUS_SCHEDULED).values_list('team_id', flat=True)
        queryset = queryset.filter(pk__in=scheduled_ids)
    elif status_filter == 'pending_post_defense':
        from student_teams.models import TeamStageProgress
        grading_ids = TeamStageProgress.objects.filter(status__in=[TeamStageProgress.STATUS_GRADING, TeamStageProgress.STATUS_PASSED]).values_list('team_id', flat=True)
        queryset = queryset.filter(pk__in=grading_ids)
    elif status_filter == 'passed':
        from student_teams.models import TeamStageProgress
        passed_ids = TeamStageProgress.objects.filter(status=TeamStageProgress.STATUS_PASSED).values_list('team_id', flat=True)
        queryset = queryset.filter(pk__in=passed_ids)
    elif status_filter == 'missing':
        missing_ids = [
            team.id
            for team in queryset
            if team_stage_status(team, current_stage_for_team(team)) in ('missing', 'needs_revision')
        ]
        queryset = queryset.filter(pk__in=missing_ids)
    elif status_filter == 'pending_review':
        pending_ids = [
            team.id
            for team in queryset
            if team_stage_status(team, current_stage_for_team(team)) == 'pending_review'
        ]
        queryset = queryset.filter(pk__in=pending_ids)

    return queryset


@read_memoize
def post_defense_ready(team, stage_label):
    """Show archive requirements after assessment, before archive-dependent closure.

    Upload overrides and legacy schedule/progress flags are not assessment
    evidence. Concept hearings also need their current selection/decision.
    """
    from grading.grades.models import TeamGrade
    from grading.grades.services import team_grading_readiness
    from .concept_completion import post_defense_state

    scope = TeamGrade.SCOPE_CAPSTONE if team.is_capstone else TeamGrade.SCOPE_PIT
    grade = latest_stage_grade(team, stage_label, scope=scope)
    if not grade or grade.project_version != team.project_version or not grade.schedule_id:
        return False
    if team.is_capstone:
        from student_teams.capstone_lifecycle import evidence_team, requirement_for_label
        team = evidence_team(team, grade, requirement_for_label(team, stage_label))
        grade.team = team
    schedule = grade.schedule
    if (schedule.project_version != team.project_version
            or schedule.semester_id != team.semester_id
            or schedule.scope != scope
            or schedule.status not in (DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE)):
        return False
    if not team_grading_readiness(grade, grade.semester, scope)['panel_complete']:
        return False
    if grade.uses_defense_verdict and grade.verdict not in TeamGrade.PASSING_VERDICTS:
        return False
    concept_access = post_defense_state(team, document_context(team, stage_label))
    return concept_access is None or concept_access['unlocked']


@read_memoize
def archive_unlocked(team, stage_label, deliverable_type='post'):
    from .stage_access import manually_locked
    if manually_locked(team, stage_label, deliverable_type):
        return False
    if deliverable_type == 'pre':
        if is_stage_unlocked_by_admin(team, stage_label, deliverable_type='pre'):
            return True
        from .redefense import preparing
        if preparing(team, document_context(team, stage_label)):
            return True
        stage_obj = defense_stage_for_label(stage_label) if team.is_capstone else None
        endorsed = was_stage_endorsed(team, stage_obj) if stage_obj else pit_endorsed(team, stage_label)
        return not (endorsed or is_stage_defense_done(team, stage_label))

    if is_stage_unlocked_by_admin(team, stage_label, deliverable_type='post') or is_stage_unlocked_by_admin(team, stage_label, deliverable_type='all') or is_stage_unlocked_by_admin(team, stage_label):
        return True

    from .concepts import stage_for
    from .concept_completion import post_defense_state
    concept_access = post_defense_state(team, stage_for(team, stage_label))
    if concept_access is not None:
        return concept_access['unlocked']

    from grading.grades.models import TeamGrade
    stage_grade = latest_stage_grade(team, stage_label)
    from grading.grades.outcome_rules import policy_for
    if stage_grade and stage_grade.uses_defense_verdict and policy_for(stage_grade.schedule).get('version') == 1:
        return post_defense_ready(team, stage_label)
    if stage_grade and stage_grade.uses_defense_verdict:
        if stage_grade.closed_as_failed:
            return 'failed'
        if getattr(stage_grade, 'verdict', '') == TeamGrade.VERDICT_FOR_REDEFENSE:
            return False
        if getattr(stage_grade, 'result', '') == 'failed':
            return False

    # Oral/panel defense is completed once panel scores are recorded
    if stage_grade and stage_grade.panel_score is not None:
        return True

    if is_stage_defense_done(team, stage_label):
        return True
    return DefenseSchedule.objects.filter(
        team=team,
        project_version=team.project_version,
        status=DefenseSchedule.STATUS_DONE,
    ).filter(Q(defense_stage__label=stage_label) | Q(event_name=stage_label)).exists()


@read_memoize
def latest_stage_grade(team, stage_label, *, scope=None):
    from grading.grades.models import TeamGrade
    if team.is_capstone and scope != TeamGrade.SCOPE_PIT:
        from student_teams.capstone_lifecycle import latest_stage_assessment, requirement_for_label
        requirement = getattr(team, '_capstone_requirement', None) or requirement_for_label(team, stage_label)
        if requirement and not getattr(team, '_assessment_semester_id', None):
            return latest_stage_assessment(team, requirement['id'])
    label_filter = (Q(pit_event_config__event_name=stage_label) | Q(stage_label=stage_label)
                    if scope == TeamGrade.SCOPE_PIT else
                    Q(defense_stage__label=stage_label) | Q(stage_label=stage_label))
    grades = TeamGrade.objects.filter(label_filter, team=team, semester=team.semester)
    if scope is not None:
        grades = grades.filter(scope=scope)
    return grades.select_related('pit_event_config', 'defense_stage').order_by('-updated_at', '-id').first()


@read_memoize
def submissions_for(team, stage_label):
    labels = {stage_label}
    if team.is_capstone:
        from student_teams.capstone_lifecycle import requirement_for_label
        requirement = getattr(team, '_capstone_requirement', None) or requirement_for_label(team, stage_label)
        if requirement:
            labels.add(requirement['label'])
    return {
        submission.deliverable_id: submission
        for submission in sorted(team.deliverable_submissions.all(), key=lambda s: (s.uploaded_at, s.pk))
        if submission.stage_label in labels
    }


@read_memoize
def is_presentation_stage(team, stage_label):
    # Every Capstone stage uses files, including legacy presentation-only stages
    # and captured cohort requirements. PIT event policy remains independent.
    if not team or getattr(team, 'is_capstone', True):
        return False
    if not stage_label:
        return False
    from defense.scheduler.pit_config import get_pit_event_config
    sem = getattr(team, 'semester', None)
    if sem:
        config = get_pit_event_config(sem, stage_label.strip(), year_level=team.year_level)
        if config and not config.deliverables.exists():
            return True
    return False


def stage_deliverables_configured(team, stage_label):
    if is_presentation_stage(team, stage_label):
        return True
    if get_deliverable_definitions_for_team(team, stage_label):
        return True
    from repository.section_concepts.shared_deliverables import resolve
    context = document_context(team, stage_label)
    profile = resolve(team, context)
    if profile:
        return bool(profile['definitions'])
    # A PM-only checklist is configured even when a particular independent
    # team has no applicable files. It must not acquire a synthetic team task.
    from defense.shared_deliverables import shared_definitions
    return bool(context and shared_definitions(context))


@read_memoize
def required_complete(team, stage_label):
    if is_presentation_stage(team, stage_label):
        return True
    configured = stage_deliverables_configured(team, stage_label)
    if not configured:
        return False
    submitted = submissions_for(team, stage_label)
    definitions = get_deliverable_definitions_for_team(team, stage_label)
    required_items = [
        item for item in definitions
        if scheduling_requirement(item)
    ]
    if not required_items:
        return True
    from .documents import completeness
    stage = document_context(team, stage_label)
    return all(
        completeness(submitted.get(item['id']), item, accepted=True, stage=stage)
        and item['id'] in submitted
        and submitted[item['id']].status == DeliverableSubmission.STATUS_ACCEPTED
        for item in required_items
    )


@read_memoize
def post_deliverables_complete(team, stage_label, *, include_shared=True):
    from repository.section_concepts.shared_deliverables import resolve, required_complete as shared_complete
    from .concepts import stage_for
    profile = resolve(team, stage_for(team, stage_label))
    if include_shared and profile and not shared_complete(profile, 'post'):
        return False
    if is_presentation_stage(team, stage_label):
        return True
    definitions = get_deliverable_definitions_for_team(team, stage_label)
    if not definitions:
        return True
    post_required = [
        item for item in definitions
        if item['type'] == DeliverableSubmission.TYPE_POST and item['required']
    ]
    if not post_required:
        return True
    from .concepts import stage_for, enabled, latest_round
    stage = stage_for(team, stage_label)
    if enabled(stage):
        from .concept_completion import final_paper_complete, shared_final_complete
        if not final_paper_complete(team, stage):
            return False
        hearing = latest_round(team, stage)
        if include_shared and hearing and hearing.section_round_id and not shared_final_complete(hearing.section_round):
            return False

    submitted = submissions_for(team, stage_label)
    from .documents import completeness
    for item in post_required:
        if item.get('historical_waiver'):
            continue
        sub = submitted.get(item['id'])
        if (not sub or sub.status != DeliverableSubmission.STATUS_ACCEPTED
                or not completeness(sub, item, accepted=True, stage=stage)):
            return False
    return True


@read_memoize(copy=True)
def post_deliverables_state(team, stage_label):
    """Keep the authoritative gate while identifying who owns outstanding work."""
    from repository.section_concepts.shared_deliverables import resolve, completion_summary
    from .concepts import stage_for
    profile = resolve(team, stage_for(team, stage_label))
    shared = completion_summary(profile) if profile else None
    return {'complete': post_deliverables_complete(team, stage_label),
        'team_complete': post_deliverables_complete(team, stage_label, include_shared=False),
        'shared_complete': shared['complete'] if shared else True,
        'shared': shared if shared and shared['requirements'] else None}


def team_stage_status(team, stage_label):
    configured = stage_deliverables_configured(team, stage_label)
    if not configured:
        return 'not_configured'
    is_endorsed = was_stage_endorsed(team, defense_stage_for_label(stage_label)) if team.is_capstone else pit_endorsed(team, stage_label)
    if is_endorsed:
        return 'endorsed'
    if required_complete(team, stage_label):
        return 'complete'
    
    # Check submissions
    submitted = submissions_for(team, stage_label)
    definitions = get_deliverable_definitions_for_team(team, stage_label)
    required_items = [item for item in definitions if scheduling_requirement(item)]
    if not required_items:
        return 'complete'
        
    any_rejected = any(
        submitted[item['id']].status == DeliverableSubmission.STATUS_REJECTED
        for item in required_items
        if item['id'] in submitted
    )
    if any_rejected:
        return 'needs_revision'
    from .documents import completeness
    stage = document_context(team, stage_label)
    if not all(completeness(submitted.get(item['id']), item, stage=stage) for item in required_items):
        return 'missing'
        
    return 'pending_review'


def compute_stage_status_detail(team, stage_label, configured, archive_required_complete):
    if not configured:
        return 'not_configured'

    from student_teams.models import TeamStageProgress
    from student_teams.services import get_stage_progress
    from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
    from defense.stages.models import StageGradingConfig
    from django.utils import timezone

    is_capstone = getattr(team, 'is_capstone', False)
    stage_obj = defense_stage_for_label(stage_label) if is_capstone else None
    progress = get_stage_progress(team, stage_obj) if stage_obj else None
    progress_status = progress.status if progress else ('ready' if (pit_endorsed(team, stage_label) if team.is_pit else team.ready_for_stage == stage_label) else 'locked')

    today = timezone.localdate()
    assessment = latest_stage_grade(team, stage_label) if is_capstone else None
    active_schedules = DefenseSchedule.objects.filter(
        scope=DefenseSchedule.SCOPE_CAPSTONE if is_capstone else DefenseSchedule.SCOPE_PIT,
        team=team,
        project_version=team.project_version,
        semester_id=assessment.semester_id if assessment else team.semester_id,
        status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE]
    )
    if stage_obj:
        active_schedules = active_schedules.filter(defense_stage=stage_obj)
    else:
        active_schedules = active_schedules.filter(event_name=stage_label)

    is_defense_today = active_schedules.filter(scheduled_date=today).exists()
    has_active_schedule = active_schedules.filter(status=DefenseSchedule.STATUS_SCHEDULED).exists()
    has_done_schedule = active_schedules.filter(status=DefenseSchedule.STATUS_DONE).exists()

    if is_capstone:
        from .redefense import preparing
        current_grade = latest_stage_grade(team, stage_label)
        if preparing(team, stage_obj) or (current_grade and current_grade.verdict == 'for_redefense'
                and progress_status == TeamStageProgress.STATUS_READY and not has_active_schedule):
            status = team_stage_status(team, stage_label)
            return {'missing': 'awaiting_files', 'needs_revision': 'changes_requested',
                    'pending_review': 'needs_review', 'complete': 'awaiting_endorsement',
                    'endorsed': 'ready_to_schedule_redefense'}.get(status, status)
        latest = active_schedules.order_by('-created_at', '-pk').first()
        if latest:
            from defense.scheduler.progress import schedule_progress
            return schedule_progress(latest, reconcile_status=False)['display_status']

    is_officially_complete = False
    if is_capstone and stage_obj:
        sem = getattr(team, 'semester', None)
        is_officially_complete = StageGradingConfig.objects.filter(
            defense_stage=stage_obj,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()
    elif not is_capstone:
        sem = getattr(team, 'semester', None)
        is_officially_complete = PitEventGradingConfig.objects.filter(
            event_name=stage_label, year_level=team.year_level,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()

    from grading.grades.models import TeamGrade
    stage_grade = latest_stage_grade(team, stage_label)
    has_panel_scored = bool(stage_grade and stage_grade.panel_score is not None)

    if stage_grade and stage_grade.uses_defense_verdict:
        if stage_grade.closed_as_failed:
            return 'failed'
        if stage_grade.verdict in ('failed', 'project_rejected'):
            return stage_grade.verdict
        if stage_grade.verdict == 'for_redefense':
            return 'for_redefense'
        if stage_grade.verdict == 'approved_with_revisions' and not stage_grade.revisions_cleared_at:
            return 'revisions_pending'
        is_officially_complete = is_officially_complete and stage_grade.status == TeamGrade.STATUS_PUBLISHED

    if (
        is_officially_complete
        or progress_status in [TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_GRADING]
        or has_done_schedule
        or has_panel_scored
    ):
        if archive_required_complete or is_officially_complete:
            return 'passed'
        else:
            return 'pending_post_defense'
    elif progress_status == TeamStageProgress.STATUS_SCHEDULED or has_active_schedule:
        if is_defense_today:
            return 'defense_ongoing'
        else:
            return 'defense_scheduled'
    elif progress_status == TeamStageProgress.STATUS_READY or (not is_capstone and pit_endorsed(team, stage_label)):
        return 'endorsed'
    else:
        return 'awaiting_endorsement'


@read_memoize
def is_stage_defense_done(team, stage_label):
    from student_teams.models import TeamStageProgress
    from student_teams.services import get_stage_progress
    from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
    from defense.stages.models import StageGradingConfig

    is_capstone = getattr(team, 'is_capstone', False)
    if not is_capstone:
        from defense.scheduler.event_scope import pit_events_for_team
        if not pit_events_for_team(team).filter(event_name__iexact=stage_label).exists():
            return False
    stage_obj = defense_stage_for_label(stage_label) if is_capstone else None
    progress = get_stage_progress(team, stage_obj) if stage_obj else None
    progress_status = progress.status if progress else ''

    active_schedules = DefenseSchedule.objects.filter(
        scope=DefenseSchedule.SCOPE_CAPSTONE if is_capstone else DefenseSchedule.SCOPE_PIT,
        team=team,
        project_version=team.project_version,
        status=DefenseSchedule.STATUS_DONE,
    )
    if stage_obj:
        active_schedules = active_schedules.filter(defense_stage=stage_obj)
    else:
        active_schedules = active_schedules.filter(event_name=stage_label)

    has_done_schedule = active_schedules.exists()

    is_officially_complete = False
    if is_capstone and stage_obj:
        sem = getattr(team, 'semester', None)
        is_officially_complete = StageGradingConfig.objects.filter(
            defense_stage=stage_obj,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()
    elif not is_capstone:
        sem = getattr(team, 'semester', None)
        is_officially_complete = PitEventGradingConfig.objects.filter(
            event_name=stage_label, year_level=team.year_level,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()

    from grading.grades.models import TeamGrade
    stage_grade = latest_stage_grade(team, stage_label)
    if stage_grade:
        if is_capstone:
            is_officially_complete = is_officially_complete and stage_grade.status == TeamGrade.STATUS_PUBLISHED
        if stage_grade.uses_defense_verdict and getattr(stage_grade, 'verdict', '') == TeamGrade.VERDICT_FOR_REDEFENSE:
            return False
        if is_capstone and getattr(stage_grade, 'result', '') == 'failed':
            return False

    has_panel_scored = bool(stage_grade and stage_grade.panel_score is not None)

    from .concepts import latest_round, stage_for
    c_stage = stage_for(team, stage_label)
    if c_stage:
        c_round = latest_round(team, c_stage)
        if c_round and c_round.verdict in ('approved', 'approved_with_revisions'):
            return True

    return (
        progress_status in [TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_GRADING]
        or has_done_schedule
        or has_panel_scored
        or is_officially_complete
    )


def is_stage_unlocked_by_admin(team, stage_label, deliverable_type=None):
    from .stage_access import manually_locked
    if deliverable_type and manually_locked(team, stage_label, deliverable_type):
        return False
    unlocked_stages = getattr(team, 'unlocked_stages', []) or []
    if stage_label in unlocked_stages:
        return True
    if f"{stage_label}:all" in unlocked_stages:
        return True
    if deliverable_type and f"{stage_label}:{deliverable_type}" in unlocked_stages:
        return True
    return False


def ensure_submission_editable(team, stage_label, deliverable_type, submission=None, *, allow_replacement=False, deliverable_id=None, lock=None):
    """Keep upload and removal rules aligned with the review state."""
    from student_teams.participation import require_open
    require_open(team)
    from .stage_access import manually_locked, deliverable_override
    specific = deliverable_override(team, stage_label, submission.deliverable_id if submission else deliverable_id)
    if specific is False or (specific is None and manually_locked(team, stage_label, deliverable_type)):
        raise PermissionError('File uploads for this deliverable are locked by an Admin or PIT Lead.')
    definition = definition_for(team, stage_label, submission.deliverable_id if submission else deliverable_id)
    from grading.grades.models import TeamGrade
    stage_grade = latest_stage_grade(team, stage_label)
    from .redefense import preparing
    context = document_context(team, stage_label)
    is_redefense = preparing(team, context) if context else False
    endorsed = (was_stage_endorsed(team, context) if team.is_capstone else pit_endorsed(team, stage_label)) and not is_redefense
    if team.is_pit:
        from .concepts import latest_round, stage_for
        current = latest_round(team, stage_for(team, stage_label))
        is_redefense = bool(current and current.number > 1 and not current.schedule_id and not current.endorsed_at)

    if submission and deliverable_type == DeliverableSubmission.TYPE_PRE:
        if allow_replacement and submission.file_replacement_unlocked and submission.status == DeliverableSubmission.STATUS_ACCEPTED:
            return
        if submission.status == DeliverableSubmission.STATUS_REJECTED and (not endorsed or submission.revision_review_unlocked):
            # An explicit revision request reopens only this submission, including past stages.
            return
        if definition and definition.get('file_policy') and submission.revision_review_unlocked:
            from .documents import current_files
            if any(f.status == 'rejected' for f in current_files(submission)):
                return

    if submission and submission.status == DeliverableSubmission.STATUS_ACCEPTED:
        from .documents import current_files
        grouped_corrections = bool(definition and definition.get('file_policy') and any(f.status == 'rejected' for f in current_files(submission)))
        grouped_draft = bool(definition and (definition.get('file_policy') or {}).get('mode') in ('named', 'multiple', 'concepts')
            and not (is_redefense and not definition.get('is_defense_material')
                     and (definition.get('file_policy') or {}).get('mode') != 'concepts')
            and not is_stage_defense_done(team, stage_label)
            and not (was_stage_endorsed(team, defense_stage_for_label(stage_label)) if team.is_capstone else pit_endorsed(team, stage_label)))
        if not grouped_corrections and not grouped_draft:
            raise PermissionError(
                'Accepted deliverables are locked. Reopen the submission for revision before changing its file.'
            )

    if specific is True:
        return

    if deliverable_type == DeliverableSubmission.TYPE_POST:
        if not archive_unlocked(team, stage_label):
            raise PermissionError('Post-Defense submissions are locked until this defense is done.')
        return

    stage = defense_stage_for_label(stage_label) if team.is_capstone else None
    endorsed = (was_stage_endorsed(team, stage) if stage else pit_endorsed(team, stage_label)) and not is_redefense
    if not is_redefense and (endorsed or is_stage_defense_done(team, stage_label)) and not is_stage_unlocked_by_admin(
        team, stage_label, deliverable_type='pre'
    ):
        raise PermissionError('Pre-defense submissions are locked after endorsement or defense completion.')


def toggle_stage_deliverables_unlock(team, stage_label, user, unlock_type='all', target_state=None, *, reason='', request=None, deliverable_id=None):
    from .stage_access import set_access
    return set_access(
        user, scope='team', team=team, stage_label=stage_label,
        unlock_type=unlock_type, target_state=target_state, reason=reason, request=request,
        deliverable_id=deliverable_id,
    )


def toggle_global_stage_deliverables_unlock(stage_label, user, scope='capstone', year_level=None, unlock_type='all', target_state=None, *, reason='', request=None, deliverable_id=None):
    from .stage_access import set_access
    return set_access(
        user, scope='global', program_scope=scope, year_level=year_level,
        stage_label=stage_label, unlock_type=unlock_type, target_state=target_state,
        reason=reason, request=request, deliverable_id=deliverable_id,
    )


def can_submit_files(user, team):
    """File submission ownership is independent from faculty review authority."""
    if not user:
        return False
    if getattr(user, 'is_superuser', False) or getattr(user, 'role', '') == 'admin':
        return True
    return getattr(user, 'role', '') == 'student' and team.memberships.filter(student=user).exists()


def stage_payload(team, stage_label, evaluator=None):
    submitted = submissions_for(team, stage_label)
    definitions = get_deliverable_definitions_for_team(team, stage_label)
    unlocked = archive_unlocked(team, stage_label)
    from .documents import slots_for as document_slots_for, completeness as document_completeness
    rows = []

    from repository.project_archive.services import resolve_archive_file_template, _deliverable_slug
    from academic_period_management.models import Semester
    from student_teams.services import get_stage_progress
    from defense.stages.models import StageGradingConfig
    from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
    from django.utils import timezone

    semester_label = team.semester.label if team.semester_id else Semester.FIRST

    is_capstone = getattr(team, 'is_capstone', False)
    stage_obj = defense_stage_for_label(stage_label) if is_capstone else None
    progress = get_stage_progress(team, stage_obj) if stage_obj else None
    progress_status = progress.status if progress else ('ready' if (pit_endorsed(team, stage_label) if team.is_pit else team.ready_for_stage == stage_label) else 'locked')
    is_endorsed = was_stage_endorsed(team, stage_obj) if is_capstone else pit_endorsed(team, stage_label)
    from .redefense import preparing
    if preparing(team, document_context(team, stage_label)):
        is_endorsed = False

    today = timezone.localdate()
    assessment = latest_stage_grade(team, stage_label) if is_capstone else None
    active_schedules = DefenseSchedule.objects.filter(
        scope=DefenseSchedule.SCOPE_CAPSTONE if is_capstone else DefenseSchedule.SCOPE_PIT,
        team=team,
        project_version=team.project_version,
        semester_id=assessment.semester_id if assessment else team.semester_id,
        status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE]
    )
    if stage_obj:
        active_schedules = active_schedules.filter(defense_stage=stage_obj)
    else:
        active_schedules = active_schedules.filter(event_name=stage_label)

    is_defense_today = active_schedules.filter(scheduled_date=today).exists()
    has_active_schedule = active_schedules.filter(status=DefenseSchedule.STATUS_SCHEDULED).exists()
    has_done_schedule = active_schedules.filter(status=DefenseSchedule.STATUS_DONE).exists()

    is_stage_officially_complete = False
    if is_capstone and stage_obj:
        sem = getattr(team, 'semester', None)
        is_stage_officially_complete = StageGradingConfig.objects.filter(
            defense_stage=stage_obj,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()
    elif not is_capstone:
        sem = getattr(team, 'semester', None)
        is_stage_officially_complete = PitEventGradingConfig.objects.filter(
            event_name=stage_label, year_level=team.year_level,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()

    is_defense_done = is_stage_defense_done(team, stage_label)
    admin_unlocked_pre = is_stage_unlocked_by_admin(team, stage_label, deliverable_type='pre') or is_stage_unlocked_by_admin(team, stage_label)
    admin_unlocked_post = is_stage_unlocked_by_admin(team, stage_label, deliverable_type='post') or is_stage_unlocked_by_admin(team, stage_label)
    can_faculty_review_pre = ((not is_endorsed and not is_defense_done) or admin_unlocked_pre)
    can_faculty_review_post = is_defense_done
    from .concepts import latest_round, enabled as concepts_enabled
    concept_context = document_context(team, stage_label)
    open_concepts = latest_round(team, concept_context)
    from .concept_completion import post_defense_state
    concept_access = post_defense_state(team, concept_context)
    if concept_access is not None:
        can_faculty_review_post = concept_access['unlocked']
    if open_concepts and not open_concepts.schedule_id and not is_endorsed:
        can_faculty_review_pre = True

    can_cancel_endorsement = bool(
        is_endorsed
        and not has_active_schedule
        and not has_done_schedule
        and not is_stage_officially_complete
        and not is_defense_done
    )

    # Resolve stage-scoped grade first so deliverable waiver conditions can evaluate it
    from grading.grades.models import TeamGrade
    stage_grade = latest_stage_grade(team, stage_label,
        scope=TeamGrade.SCOPE_CAPSTONE if is_capstone else TeamGrade.SCOPE_PIT)
    from grading.grades.outcome_rules import policy_for
    if is_capstone and policy_for(getattr(stage_grade, 'schedule', None)).get('version') == 1:
        can_faculty_review_post = post_defense_ready(team, stage_label)
    if stage_grade and stage_grade.verdict == TeamGrade.VERDICT_FOR_REDEFENSE and not is_endorsed:
        can_faculty_review_pre = True

    grade_data = None
    if (is_capstone and stage_grade and stage_grade.status != TeamGrade.STATUS_PUBLISHED
            and stage_grade.verdict == TeamGrade.VERDICT_FOR_REDEFENSE
            and not stage_grade.closed_as_failed):
        is_stage_officially_complete = False
    if stage_grade:
        from grading.grades.defense_workflow import workflow_payload
        grade_data = {
            'id': stage_grade.id,
            'schedule_id': stage_grade.schedule_id,
            'stage_label': stage_grade.stage_label,
            'panel_score': float(stage_grade.panel_score) if stage_grade.panel_score is not None else None,
            'peer_score': float(stage_grade.peer_score) if stage_grade.peer_score is not None else None,
            'adviser_score': float(stage_grade.adviser_score) if stage_grade.adviser_score is not None else None,
            'final_grade': float(stage_grade.final_grade) if stage_grade.final_grade is not None else None,
            'status': stage_grade.status,
            'result': stage_grade.result,
            'verdict': stage_grade.verdict or '',
            'verdict_remarks': stage_grade.verdict_remarks or '',
            'revision_deadline': stage_grade.revision_deadline.isoformat() if stage_grade.revision_deadline else None,
            'revisions_cleared_at': stage_grade.revisions_cleared_at.isoformat() if stage_grade.revisions_cleared_at else None,
            'clearance_remarks': stage_grade.clearance_remarks or '',
            'redefense_verification_required': stage_grade.redefense_verification_required,
            'redefense_verified_at': stage_grade.redefense_verified_at.isoformat() if stage_grade.redefense_verified_at else None,
            'compliance_review_date': stage_grade.compliance_review_date.isoformat() if stage_grade.compliance_review_date else None,
            'attempt_count': stage_grade.attempt_count or 1,
            'is_officially_complete': is_stage_officially_complete,
            'workflow': workflow_payload(stage_grade) if is_capstone else {},
        }

    actor_can_submit = evaluator is None or can_submit_files(evaluator, team)
    used_vault_names = set()
    for item in definitions:
        if item.get('source') == 'defense_minutes':
            continue
        submission = submitted.get(item['id'])
        is_vault = item['type'] == DeliverableSubmission.TYPE_POST
        verdict_cond = item.get('verdict_condition', 'all_pass')
        is_defense_material = item.get('is_defense_material', False)

        is_waived = bool(item.get('historical_waiver'))

        if is_vault:
            can_review_item = can_faculty_review_post and (
                submission is None or submission.status != DeliverableSubmission.STATUS_ACCEPTED
            )
            if submission and item.get('file_policy') and can_faculty_review_post:
                from .documents import current_files
                can_review_item = any(f.status != 'accepted' for f in current_files(submission))
        else:
            can_review_item = can_faculty_review_pre or bool(submission and submission.revision_review_unlocked)
        
        suggested = ''
        if is_vault:
            suggested = resolve_archive_file_template(
                item.get('archive_file_template', ''),
                team,
                stage_label,
                semester_label,
                deliverable_label=item['label'],
                file_format=item.get('file_format', 'any'),
                file_extension=submission.file_name.rpartition('.')[2] if submission else '',
            )
            if suggested in used_vault_names:
                import os
                base, ext = os.path.splitext(suggested)
                slug = _deliverable_slug(item['label']) or item['id']
                suggested = f"{base}_{slug}{ext or '.pdf'}"
                if suggested in used_vault_names:
                    suggested = f"{base}_{item['id']}{ext or '.pdf'}"
            used_vault_names.add(suggested)

        try:
            ensure_submission_editable(team, stage_label, item['type'], submission,
                                       allow_replacement=True, deliverable_id=item['id'], lock=False)
            upload_window_open = True
        except PermissionError:
            upload_window_open = False

        can_upload = upload_window_open and actor_can_submit

        slots = document_slots_for(item, stage=concept_context)
        if (item.get('file_policy') or {}).get('mode') == 'concepts' and not is_vault:
            from repository.title_workflow import team_guard
            for slot in slots:
                try:
                    team_guard(team, concept_context, slot['key'].split(':')[0])
                    slot['upload_blocker'] = ''
                except ValidationError as exc:
                    slot['upload_blocker'] = ' '.join(exc.messages)

        rows.append({
            'id': item['id'],
            'label': item['label'],
            'required': item['required'],
            'type': item['type'],
            'archive_note': item.get('archive_note', ''),
            'file_format': item.get('file_format', 'any'),
            'file_policy': item.get('file_policy', {}),
            'document_slots': slots,
            'suggested_file_name': suggested,
            'uploaded': document_completeness(submission, item, stage=concept_context),
            'locked': not can_upload,
            'can_upload': can_upload,
            'is_defense_material': is_defense_material,
            'verdict_condition': verdict_cond,
            'is_waived': is_waived,
            'can_faculty_review': can_review_item,
            'submission': submission_payload(submission) if submission else None,
            'requirement_timing': 'scheduling', 'due_at': None,
        })

    from defense.minutes.requirements import stage_minutes_requirement
    generated_minutes = stage_minutes_requirement(team, stage_obj)
    system_items = [generated_minutes] if generated_minutes else []
    rows.extend(system_items)
    pre_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_PRE]
    archive_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_POST]
    required_items = [item for item in pre_items if scheduling_requirement(item)]
    archive_required_items = [item for item in archive_items if item['required'] and not item.get('is_waived')]

    is_pres = is_presentation_stage(team, stage_label)
    configured = len(definitions) > 0 or is_pres
    endorsement_required = is_capstone or bool(required_items)
    archive_required_complete = (
        not archive_required_items
        or all(
            item['submission'] is not None
            and item['submission']['status'] == DeliverableSubmission.STATUS_ACCEPTED
            for item in archive_required_items
        )
    )
    archive_required_complete = archive_required_complete and post_deliverables_complete(team, stage_label)
    stage_status_detail = compute_stage_status_detail(team, stage_label, configured, archive_required_complete)
    if configured and not endorsement_required and stage_status_detail == 'awaiting_endorsement':
        stage_status_detail = 'scheduling_eligible'

    # Resolve stage-scoped schedule
    stage_sched = active_schedules.order_by('-scheduled_date', '-start_time', '-id').first()
    from defense.scheduler.progress import schedule_progress
    assessment_progress = schedule_progress(stage_sched, reconcile_status=False) if stage_sched else None
    schedule_data = None
    if stage_sched:
        panelists_list = []
        if hasattr(stage_sched, 'panelists'):
            for p in stage_sched.panelists.all():
                panelists_list.append({
                    'id': p.id,
                    'name': display_name(p),
                    'username': p.username,
                })
        doc_data = None
        if getattr(stage_sched, 'documenter', None):
            doc_data = {
                'id': stage_sched.documenter.id,
                'name': display_name(stage_sched.documenter),
                'username': stage_sched.documenter.username,
            }
        from academic_period_management.calendar import schedule_time_payload
        schedule_data = {
            **schedule_time_payload(stage_sched),
            'id': stage_sched.id,
            'stage': stage_sched.stage_label,
            'date': stage_sched.scheduled_date.isoformat() if stage_sched.scheduled_date else None,
            'scheduled_date': stage_sched.scheduled_date.isoformat() if stage_sched.scheduled_date else None,
            'startTime': str(stage_sched.start_time) if stage_sched.start_time else None,
            'start_time': str(stage_sched.start_time) if stage_sched.start_time else None,
            'slotDuration': stage_sched.slot_duration,
            'room': stage_sched.room,
            'status': stage_sched.status,
            'teamId': stage_sched.team_id,
            'team_name': team.name,
            'stage_label': stage_sched.stage_label,
            'scope': stage_sched.scope,
            'revision': stage_sched.revision,
            'panelists': panelists_list,
            'documenter': doc_data,
        }

    # Resolve stage-scoped peer evaluation data
    from grading.grades.peer_eval import (
        is_team_peer_eval_complete,
        peer_criteria_payload,
        peer_submissions_for_evaluator,
    )
    stage_peer_criteria = peer_criteria_payload(team, stage_label=stage_label)
    stage_peer_submissions = (
        peer_submissions_for_evaluator(team, evaluator, stage_label=stage_label)
        if evaluator
        else []
    )
    stage_peer_complete = bool(stage_grade and is_team_peer_eval_complete(stage_grade))
    from grading.grades.services import peer_grading_allowed_for_grade
    stage_peer_allowed = bool(
        stage_grade
        and stage_grade.status not in TeamGrade.LOCKED_STATUSES
        and peer_grading_allowed_for_grade(stage_grade)
    )
    from grading.grades.availability import peer_grading_unavailable_reason
    stage_peer_reason = peer_grading_unavailable_reason(stage_grade)

    from .concepts import payload as concept_payload
    concept_workflow = concept_payload(team, concept_context, actor=evaluator)
    from repository.section_concepts.shared_deliverables import summary as shared_summary
    shared_checklist = shared_summary(team, concept_context) if concept_context else None
    from .redefense import preparing
    repeat_preparation = bool(is_capstone and stage_grade and stage_grade.verdict == 'for_redefense'
                              and (preparing(team, concept_context) or (
                                  progress_status == TeamStageProgress.STATUS_READY and not has_active_schedule)))
    from .endorsement import endorsement_review
    from .redefense import hearing_history
    review = endorsement_review(team, stage_label, definitions=definitions, submitted=submitted)
    return {
        'stage_label': stage_label,
        'concept_workflow': concept_workflow,
        'shared_deliverables_summary': shared_checklist,
        'hearing_history': (hearing_history(team, concept_context)
                            if not concept_workflow and concept_context else []),
        'assessment_progress': assessment_progress,
        'repeat_preparation': repeat_preparation,
        'endorsement_review': review,
        'peer_eval_unavailable_reason': stage_peer_reason,
        'deliverables_configured': configured,
        'is_presentation_only': is_pres,
        'endorsement_required': endorsement_required,
        'endorsed': is_endorsed,
        'is_officially_complete': is_stage_officially_complete,
        'has_active_schedule': has_active_schedule,
        'has_done_schedule': has_done_schedule,
        'can_cancel_endorsement': can_cancel_endorsement,
        'archive_unlocked': unlocked or any(item.get('can_upload') for item in archive_items),
        'post_defense_ready': post_defense_ready(team, stage_label),
        'vault_unlocked': unlocked or any(item.get('can_upload') for item in archive_items),
        'pre_unlocked': archive_unlocked(team, stage_label, deliverable_type='pre'),
        'post_unlocked': archive_unlocked(team, stage_label, deliverable_type='post'),
        'post_unavailable_reason': concept_access['reason'] if concept_access else '',
        'required_complete': configured and required_complete(team, stage_label),
        'status': team_stage_status(team, stage_label),
        'stage_progress_status': progress_status,
        'stage_status_detail': stage_status_detail,
        'is_defense_done': is_defense_done,
        'admin_unlocked': admin_unlocked_pre,
        'can_faculty_review': can_faculty_review_pre,
        'can_faculty_review_pre': can_faculty_review_pre,
        'can_faculty_review_post': can_faculty_review_post,
        'pre_uploaded': sum(1 for item in pre_items if item['uploaded']),
        'pre_total': len(pre_items),
        'required_uploaded': sum(1 for item in required_items if item['uploaded']),
        'required_total': len(required_items),
        'archive_uploaded': sum(1 for item in archive_items if item['uploaded']),
        'archive_total': len(archive_items),
        'archive_required_uploaded': sum(1 for item in archive_required_items if item['uploaded']),
        'archive_required_accepted': sum(
            1 for item in archive_required_items
            if item['submission'] is not None
            and item['submission']['status'] == DeliverableSubmission.STATUS_ACCEPTED
        ),
        'archive_required_total': len(archive_required_items),
        'archive_complete': archive_required_complete,
        'post_defense_completion': post_deliverables_state(team, stage_label),
        'pre': pre_items,
        'post': archive_items,
        'system': system_items,
        'minutes_required': bool(generated_minutes and generated_minutes.get('required')),
        'documentation_complete': not generated_minutes or not generated_minutes.get('required') or generated_minutes['completed'],
        'deliverables_total': len(rows),
        'deliverables_completed': sum(1 for item in rows if item.get('completed') or (
            item.get('submission') and item['submission']['status'] == DeliverableSubmission.STATUS_ACCEPTED
        )),
        'deliverables': rows,
        'schedule': schedule_data,
        'grade': grade_data,
        'peer_criteria': stage_peer_criteria,
        'my_peer_submissions': stage_peer_submissions,
        'peer_eval_complete': stage_peer_complete,
        'peer_eval_allowed': stage_peer_allowed,
    }


@read_memoize(copy=True)
def submission_payload(submission):
    if submission is None:
        return None
        
    from .documents import current_files, file_payload
    files_data = [file_payload(f) for f in current_files(submission)]
    history_data = [file_payload(f) for f in submission.files.all() if not f.is_current]

    return {
        'id': submission.id,
        'deliverable_id': submission.deliverable_id,
        'files': files_data,
        'file_history': history_data,
        'file_name': files_data[0]['file_name'] if files_data else (getattr(submission, 'file_name', '') or ''),
        'file_size': files_data[0]['file_size'] if files_data else (getattr(submission, 'file_size', '') or ''),
        'file_url': files_data[0]['file_url'] if files_data else (submission.file.url if getattr(submission, 'file', None) and submission.file else None),
        'uploaded_by_name': display_name(submission.uploaded_by),
        'uploaded_at': submission.uploaded_at,
        'is_late': getattr(submission, 'is_late', False),
        'status': submission.status,
        'feedback': submission.feedback,
        'file_replacement_unlocked': submission.file_replacement_unlocked,
        'file_replacement_reason': submission.file_replacement_reason,
        'revision_review_unlocked': submission.revision_review_unlocked,
        'reviewed_by_name': display_name(submission.reviewed_by),
        'reviewed_at': submission.reviewed_at,
    }


def resolve_team_instructor_or_adviser_name(team):
    if team.adviser:
        return display_name(team.adviser)
    if not team.is_capstone and team.semester_id and team.section and team.year_level:
        from student_teams.team_levels import normalize_year_level
        from user_management.models import SectionInstructorAssignment
        assignment = SectionInstructorAssignment.objects.filter(
            semester_id=team.semester_id,
            section=team.section,
            year_level=normalize_year_level(team.year_level),
            is_active=True,
        ).select_related('faculty').first()
        if assignment:
            return display_name(assignment.faculty)
    return None


def team_payload(team, selected_stage=None, evaluator=None):
    if team.is_capstone:
        from student_teams.capstone_context import phase_requirements
        required = phase_requirements(team)
        labels = dict(DefenseStage.objects.filter(pk__in=[r['id'] for r in required]).values_list('pk', 'label'))
        configured_stage_labels = [labels.get(r['id'], r['label']) for r in required]
    else:
        from defense.scheduler.models import PitEventGradingConfig
        from defense.scheduler.event_scope import pit_events_for_team
        configs_qs = pit_events_for_team(team)
        configured_stage_labels = list(
            configs_qs.order_by('event_name')
            .values_list('event_name', flat=True)
        )
    selected = selected_stage or current_stage_for_team(team)
    stages = [stage_payload(team, stage, evaluator=evaluator) for stage in configured_stage_labels]
    if configured_stage_labels and selected not in configured_stage_labels:
        selected = configured_stage_labels[0]
    selected_payload = next(
        (item for item in stages if item['stage_label'] == selected),
        None,
    )
    if selected_payload is None:
        selected_payload = stage_payload(team, selected or '', evaluator=evaluator)

    # Fetch team members list
    members = [
        {
            'id': membership.student.id,
            'username': membership.student.username,
            'name': display_name(membership.student),
            'role': 'leader' if team.leader == membership.student else 'member'
        }
        for membership in team.memberships.all()
    ]

    # Fetch grading details if TeamGrade exists for the selected stage
    from grading.grades.models import TeamGrade, StudentStageGrade

    grade_payload = None
    if selected:
        grade_obj = latest_stage_grade(team, selected,
            scope=TeamGrade.SCOPE_CAPSTONE if team.is_capstone else TeamGrade.SCOPE_PIT)

        if grade_obj:
            student_grades = StudentStageGrade.objects.filter(team_grade=grade_obj).select_related('student')
            peer_per_student = [
                {
                    'student_id': sg.student.id,
                    'username': sg.student.username,
                    'student_name': display_name(sg.student),
                    'average_score': float(sg.peer_score) if sg.peer_score is not None else None,
                    'max_score': 100.0,
                    'normalized_score': float(sg.peer_score) if sg.peer_score is not None else None,
                }
                for sg in student_grades
            ]

            from grading.grades.defense_workflow import workflow_payload
            grade_payload = {
                'id': grade_obj.id,
                'schedule_id': grade_obj.schedule_id,
                'scheduled_date': grade_obj.schedule.scheduled_date.isoformat() if grade_obj.schedule and grade_obj.schedule.scheduled_date else None,
                'stage_label': grade_obj.stage_label,
                'panel_score': float(grade_obj.panel_score) if grade_obj.panel_score is not None else None,
                'peer_score': float(grade_obj.peer_score) if grade_obj.peer_score is not None else None,
                'adviser_score': float(grade_obj.adviser_score) if grade_obj.adviser_score is not None else None,
                'final_grade': float(grade_obj.final_grade) if grade_obj.final_grade is not None else None,
                'status': grade_obj.status,
                'result': grade_obj.result,
                'verdict': grade_obj.verdict or '',
                'verdict_remarks': grade_obj.verdict_remarks or '',
                'revision_deadline': grade_obj.revision_deadline.isoformat() if grade_obj.revision_deadline else None,
                'revisions_cleared_at': grade_obj.revisions_cleared_at.isoformat() if grade_obj.revisions_cleared_at else None,
                'clearance_remarks': grade_obj.clearance_remarks or '',
                'redefense_verification_required': grade_obj.redefense_verification_required,
                'redefense_verified_at': grade_obj.redefense_verified_at.isoformat() if grade_obj.redefense_verified_at else None,
                'compliance_review_date': grade_obj.compliance_review_date.isoformat() if grade_obj.compliance_review_date else None,
                'attempt_count': grade_obj.attempt_count or 1,
                'is_officially_complete': bool(selected_payload.get('is_officially_complete', False)),
                'workflow': workflow_payload(grade_obj) if team.is_capstone else {},
                'peer_per_student': peer_per_student,
            }

    effective_adviser_name = resolve_team_instructor_or_adviser_name(team)
    roster_display = {'name': team.name, 'project_title': team.project_title}
    if team.is_pit:
        from student_teams.roster_workspace import display_for
        from defense.scheduler.models import PitEventGradingConfig
        event = PitEventGradingConfig.objects.filter(semester_id=team.semester_id,
            year_level=team.year_level, event_name__iexact=selected).first()
        roster_display = display_for(team, event)
    return {
        'id': team.id,
        **roster_display,
        'setup_pending': team.setup_pending,
        'project_pending': team.project_pending,
        'project_version': team.project_version,
        'semester_id': team.semester_id,
        'level': team.level,
        'year_level': team.year_level,
        'section': team.section,
        'status': team.status,
        'ready_for_stage': team.ready_for_stage,
        'current_defense_stage': team.current_defense_stage,
        'current_stage': current_stage_for_team(team),
        'selected_stage': selected_payload,
        'stages': stages,
        'adviser_name': effective_adviser_name,
        'instructor_name': effective_adviser_name,
        'leader_name': display_name(team.leader),
        'member_count': team.memberships.count(),
        'submitted_count': team.deliverable_submissions.count(),
        'counts': team_counts_payload(team, selected_payload),
        'members': members,
        'grade': grade_payload,
    }


def team_counts_payload(team, stage):
    """The team's contribution to list counts, using the serialized stage facts."""
    status = stage['status']
    ready = status in ('endorsed', 'complete')
    missing = status in ('missing', 'needs_revision')
    pending = status == 'pending_review'
    if not (ready or missing or pending) and team.ready_for_stage and not team.is_pit:
        ready = True
    submissions = list(team.deliverable_submissions.all())
    return {
        'teams': 1,
        'ready': int(ready),
        'missing_requirements': int(missing),
        'pending_review': int(pending),
        'submitted_files': len(submissions),
        'archive_files': sum(
            submission.deliverable_type == DeliverableSubmission.TYPE_POST
            and submission.status == DeliverableSubmission.STATUS_ACCEPTED
            for submission in submissions
        ),
        'deliverables_configured': stage['deliverables_configured'],
    }


def counts_payload(teams, selected_stage=None, *, serialized_teams=None):
    if serialized_teams is not None:
        contributions = [team['counts'] for team in serialized_teams]
        return {
            **{key: sum(row[key] for row in contributions) for key in (
                'teams', 'ready', 'missing_requirements', 'pending_review',
                'submitted_files', 'archive_files',
            )},
            'deliverables_configured': any(row['deliverables_configured'] for row in contributions),
        }
    team_list = list(teams)
    submitted_total = sum(team.deliverable_submissions.count() for team in team_list)
    
    ready_count = 0
    missing_count = 0
    pending_count = 0
    deliverables_configured = False

    for team in team_list:
        stage = selected_stage or current_stage_for_team(team)
        if stage_deliverables_configured(team, stage):
            deliverables_configured = True
        status = team_stage_status(team, stage)
        if status in ('endorsed', 'complete'):
            ready_count += 1
        elif status in ('missing', 'needs_revision'):
            missing_count += 1
        elif status == 'pending_review':
            pending_count += 1
        elif team.ready_for_stage and not team.is_pit:
            ready_count += 1

    archive_total = DeliverableSubmission.objects.filter(
        team__in=team_list,
        deliverable_type=DeliverableSubmission.TYPE_POST,
        status=DeliverableSubmission.STATUS_ACCEPTED,
    ).count() if team_list else 0

    return {
        'teams': len(team_list),
        'ready': ready_count,
        'missing_requirements': missing_count,
        'pending_review': pending_count,
        'submitted_files': submitted_total,
        'archive_files': archive_total,
        'deliverables_configured': deliverables_configured,
    }


@transaction.atomic
def upsert_submission(team, stage_label, deliverable_id, file_name, file_size, user, file=None, file_id=None, slot_key=''):
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    deliverable_id = (deliverable_id or '').strip()
    if not team.is_capstone and not team.is_pit:
        raise PermissionError('Only Capstone or PIT teams can submit deliverables.')
    definition = definition_for(team, stage_label, deliverable_id)
    if definition is None:
        raise ValueError('Deliverable does not exist for this stage.')
    if definition.get('source') == 'defense_minutes':
        raise PermissionError('Signed minutes are generated by the documenter signing workflow and cannot be uploaded.')
    if file is not None:
        from .timing import validate_material_file
        validate_material_file(definition, file_name, file)
    existing = DeliverableSubmission.objects.select_for_update().filter(
        team=team, stage_label=stage_label, deliverable_id=deliverable_id,
    ).first()
    ensure_submission_editable(team, stage_label, definition['type'], existing, allow_replacement=True, deliverable_id=deliverable_id)
    is_approved_replacement = bool(
        existing and existing.deliverable_type == DeliverableSubmission.TYPE_PRE
        and existing.status == DeliverableSubmission.STATUS_ACCEPTED
        and existing.file_replacement_unlocked
    )
    if is_approved_replacement and file is None:
        raise ValueError('Choose a replacement file before submitting.')
    previous_file_name = existing.file_name if existing else ''
    replacement_reason = existing.file_replacement_reason if is_approved_replacement else ''
    if definition['type'] == DeliverableSubmission.TYPE_POST:
        
        # Resolve suggested archive name for metadata reference
        from repository.project_archive.services import resolve_archive_file_template
        from academic_period_management.models import Semester
        semester_label = team.semester.label if team.semester_id else Semester.FIRST
        suggested = resolve_archive_file_template(
            definition.get('archive_file_template', ''),
            team,
            stage_label,
            semester_label,
            deliverable_label=definition['label'],
        )

    # Ensure DeliverableSubmission container exists
    submission, created = DeliverableSubmission.objects.select_for_update().get_or_create(
        team=team,
        stage_label=stage_label,
        deliverable_id=deliverable_id,
        defaults={
            'label': definition['label'],
            'deliverable_type': definition['type'],
            'required': definition['required'],
            'uploaded_by': user,
            'status': DeliverableSubmission.STATUS_PENDING,
            'feedback': '',
        }
    )

    if not created:
        if not is_approved_replacement:
            submission.status = DeliverableSubmission.STATUS_PENDING
            submission.feedback = ''
        submission.file_replacement_unlocked = False
        submission.file_replacement_reason = ''
        submission.uploaded_by = user
        submission.save(update_fields=[
            'status', 'feedback', 'file_replacement_unlocked', 'file_replacement_reason',
            'uploaded_by', 'uploaded_at',
        ])

    from .documents import store_revision, sync_submission
    stage = document_context(team, stage_label)
    from .concepts import enabled, get_round
    if enabled(stage):
        get_round(team, stage)
    store_revision(submission, definition, file=file, file_name=file_name, file_size=file_size,
        slot_key=slot_key, file_id=file_id, preserve_approval=is_approved_replacement, stage=stage)
    sync_submission(submission, definition, stage)
    from .concepts import invalidate_clearance
    invalidate_clearance(team, stage_label, deliverable_id)

    # Sync latest file to the parent submission for backward compatibility
    latest_file = submission.latest_file
    if latest_file:
        submission.file_name = latest_file.file_name
        submission.file_size = latest_file.file_size
        submission.file = latest_file.file
        submission.extracted_text = latest_file.extracted_text
        submission.topics = latest_file.topics
        submission.summary = latest_file.summary
        submission.category = latest_file.category
        submission.category_confidence = latest_file.category_confidence
        fields_to_update = [
            'file_name', 'file_size', 'file', 'extracted_text',
            'topics', 'summary', 'category', 'category_confidence', 'uploaded_at',
        ]
        submission.save(update_fields=fields_to_update)

    if is_approved_replacement:
        from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        from repository.archive.models import ArchiveEntry
        from repository.project_archive.models import ProjectArchiveLog
        from repository.project_archive.trail import log_action
        track = 'pit' if team.is_pit else 'capstone'
        context = {**audit_scope_metadata(scope=track, team=team), 'stage_label': stage_label}
        log_action(
            ArchiveEntry.TYPE_PIT if team.is_pit else ArchiveEntry.TYPE_CAPSTONE,
            submission.pk, submission.file_name, ProjectArchiveLog.ACTION_OVERRIDE, user,
            previous_status='Approved', new_status='Approved',
            message=f'Student replaced the approved file ({previous_file_name}); approval retained. Reason: {replacement_reason}',
        )
        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.student_file_replace', target=submission, actor=user,
            old_values={**context, 'file_name': previous_file_name, 'status': 'accepted', 'file_replacement_unlocked': True},
            new_values={**context, 'file_name': submission.file_name, 'status': submission.status, 'file_replacement_unlocked': False},
            reason=replacement_reason, strict=True,
        )
    return submission


@transaction.atomic
def remove_submission(team, stage_label, deliverable_id, file_id=None):
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    definition = definition_for(team, stage_label, deliverable_id)
    if definition and definition.get('source') == 'defense_minutes':
        raise PermissionError('Signed minutes can only be changed through the minutes amendment workflow.')
    try:
        submission = DeliverableSubmission.objects.select_for_update().get(
            team=team,
            stage_label=stage_label,
            deliverable_id=deliverable_id,
        )
    except DeliverableSubmission.DoesNotExist:
        return 0

    ensure_submission_editable(
        team, stage_label, submission.deliverable_type, submission,
    )

    from .redefense import hearing_history
    preserve_hearing_files = bool(definition and submission.files.filter(is_current=False).exists()
        and hearing_history(team, document_context(team, stage_label)))
    if definition and (definition.get('file_policy') or preserve_hearing_files):
        from .documents import sync_submission
        targets = submission.files.filter(is_current=True)
        if file_id:
            targets = targets.filter(pk=file_id)
        deleted = targets.update(is_current=False)
        submission._prefetched_objects_cache = {}
        sync_submission(submission, definition, document_context(team, stage_label))
        from .concepts import invalidate_clearance
        invalidate_clearance(team, stage_label, deliverable_id)
        if hasattr(team, '_prefetched_objects_cache'):
            team._prefetched_objects_cache.pop('deliverable_submissions', None)
        return deleted

    deleted = 0
    if file_id:
        file_to_delete = submission.files.filter(id=file_id).first()
        if file_to_delete:
            delete_repository_file_on_commit(file_to_delete.file)
            file_to_delete.delete()
            deleted = 1
            
        # Delete submission container if no files remain
        if not submission.files.exists():
            submission.delete()
        else:
            # Sync backward compatibility fields with the remaining latest file
            latest_file = submission.latest_file
            submission.file_name = latest_file.file_name
            submission.file_size = latest_file.file_size
            submission.file = latest_file.file
            submission.extracted_text = latest_file.extracted_text
            submission.topics = latest_file.topics
            submission.summary = latest_file.summary
            submission.category = latest_file.category
            submission.category_confidence = latest_file.category_confidence
            submission.save()
    else:
        for f in submission.files.all():
            delete_repository_file_on_commit(f.file)
        delete_repository_file_on_commit(submission.file)
        submission.delete()
        deleted = 1

    if hasattr(team, '_prefetched_objects_cache'):
        team._prefetched_objects_cache.pop('deliverable_submissions', None)
    if (pit_endorsed(team, stage_label) if team.is_pit else team.ready_for_stage == stage_label) and not required_complete(team, stage_label):
        if team.is_capstone:
            stage = defense_stage_for_label(stage_label)
            if stage is not None:
                mark_stage_locked(team, stage)
            else:
                set_pit_endorsed(team, stage_label, False)
                if team.ready_for_stage == stage_label:
                    team.ready_for_stage = None
                    team.save(update_fields=['ready_for_stage', 'updated_at'])
        else:
            set_pit_endorsed(team, stage_label, False)
            if team.ready_for_stage == stage_label:
                team.ready_for_stage = None
                team.save(update_fields=['ready_for_stage', 'updated_at'])
    return deleted


@transaction.atomic
def endorse_team(team, stage_label, user=None):
    if not stage_deliverables_configured(team, stage_label):
        raise ValueError(
            'No deliverables configured for this stage. Add them in Defense Stages or PIT configs before endorsement.'
        )
    if not required_complete(team, stage_label):
        raise ValueError('All required scheduling deliverables must be cleared before endorsement.')
    if team.is_capstone:
        stage = defense_stage_for_label(stage_label)
        if stage is None:
            raise ValueError('Defense stage does not exist.')
        try:
            from .concepts import endorse as endorse_concepts
            endorse_concepts(team, stage, user)
            mark_stage_ready(team, stage, user=user)
        except ValidationError as exc:
            raise ValueError(' '.join(exc.messages)) from exc
    else:
        from .concepts import endorse as endorse_concepts
        endorse_concepts(team, document_context(team, stage_label), user)
        set_pit_endorsed(team, stage_label, True, user)
        team.ready_for_stage = stage_label
        team.save(update_fields=['ready_for_stage', 'updated_at'])
    # A new endorsement closes earlier correction windows, including optional
    # submissions. A subsequent explicit reopening may permit another correction.
    DeliverableSubmission.objects.filter(team=team, stage_label=stage_label,
        deliverable_type=DeliverableSubmission.TYPE_PRE).update(revision_review_unlocked=False)
    return team


@transaction.atomic
def unendorse_team(team, stage_label):
    from defense.scheduler.models import DefenseSchedule
    if team.is_capstone:
        stage = defense_stage_for_label(stage_label)
        if stage is None:
            raise ValueError('Defense stage does not exist.')

        has_schedule = DefenseSchedule.objects.filter(
            team=team,
        project_version=team.project_version,
            defense_stage=stage,
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE],
        ).exists()
        if has_schedule:
            raise ValueError('Cannot cancel endorsement: defense is already scheduled or completed.')

        mark_stage_locked(team, stage)
    else:
        has_schedule = DefenseSchedule.objects.filter(
            team=team,
        project_version=team.project_version,
            event_name__iexact=stage_label,
            scope=DefenseSchedule.SCOPE_PIT,
            status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE],
        ).exists()
        if has_schedule:
            raise ValueError('Cannot cancel endorsement: defense is already scheduled or completed.')

        set_pit_endorsed(team, stage_label, False)
        if team.ready_for_stage == stage_label:
            team.ready_for_stage = None
            team.save(update_fields=['ready_for_stage', 'updated_at'])
        from .concepts import invalidate_clearance
        invalidate_clearance(team, stage_label)
    return team


def check_review_assignment(actor, team):
    from .views import check_deliverable_write_permission
    return actor.role != 'student' and check_deliverable_write_permission(actor, team)


@transaction.atomic
def review_submission(team, stage_label, deliverable_id, status_val, feedback_val, reviewer_user, clear_defense_revisions=False, file_id=None, revision_scope='paper', title_review_token=None):
    team = StudentTeam.objects.select_for_update().get(pk=team.pk)
    from student_teams.participation import require_open
    require_open(team)
    definition = definition_for(team, stage_label, deliverable_id)
    if definition and definition.get('source') == 'defense_minutes':
        raise PermissionError('Use the defense minutes signing workflow to approve this record.')
    from django.utils import timezone

    try:
        submission = DeliverableSubmission.objects.select_for_update().get(
            team=team,
            stage_label=stage_label,
            deliverable_id=deliverable_id
        )
    except DeliverableSubmission.DoesNotExist:
        raise ValueError('Deliverable submission not found.')

    is_admin = getattr(reviewer_user, 'role', None) == 'admin' or getattr(reviewer_user, 'is_superuser', False)
    if not is_admin and getattr(reviewer_user, 'role', None) != 'faculty':
        raise PermissionError('Only assigned faculty or an Admin can review deliverables.')
    is_defense_done = is_stage_defense_done(team, stage_label)
    from .concepts import latest_round, stage_for
    concept_round = latest_round(team, stage_for(team, stage_label))
    if concept_round and not concept_round.schedule_id:
        is_defense_done = False
    elif concept_round and concept_round.verdict in ('approved', 'approved_with_revisions'):
        is_defense_done = True
    is_post = submission.deliverable_type == DeliverableSubmission.TYPE_POST
    from .concept_completion import post_defense_state
    concept_access = post_defense_state(team, stage_for(team, stage_label))
    if is_post and concept_access is not None and not concept_access['unlocked']:
        raise PermissionError(concept_access['reason'])
    admin_unlocked = is_stage_unlocked_by_admin(team, stage_label, deliverable_type=submission.deliverable_type)
    from grading.grades.outcome_rules import policy_for
    grade = latest_stage_grade(team, stage_label) if is_post and team.is_capstone else None
    if (grade and policy_for(grade.schedule).get('version') == 1 and not admin_unlocked
            and not post_defense_ready(team, stage_label)):
        raise PermissionError('Post-defense review opens after the panel records approval for this hearing.')

    current_target = submission.files.filter(pk=file_id, is_current=True).first() if file_id else None
    reviewing_pending_attachment = bool(definition and definition.get('file_policy') and current_target and current_target.status != 'accepted')
    if is_post and submission.status == DeliverableSubmission.STATUS_ACCEPTED and not reviewing_pending_attachment:
        raise PermissionError('This file is already in the archive. An Admin must reopen it for revision.')
    if is_post and status_val == DeliverableSubmission.STATUS_ACCEPTED and not is_defense_done:
        raise PermissionError('Post-defense files can be approved only after this defense is complete.')

    if not is_post:
        stage = document_context(team, stage_label)
        endorsed = was_stage_endorsed(team, stage) if stage else pit_endorsed(team, stage_label)
        prior_grade = latest_stage_grade(team, stage_label)
        from .redefense import preparing
        if prior_grade and prior_grade.verdict == 'for_redefense' and preparing(team, stage):
            # Historical endorsement is not a lock on corrections for the next
            # attempt. Its required files still need acceptance before scheduling.
            endorsed = False
        if concept_round and not concept_round.schedule_id and not concept_round.endorsed_at:
            endorsed = False
        if endorsed and not (admin_unlocked or submission.revision_review_unlocked):
            raise PermissionError('Cancel endorsement or ask an Admin to unlock pre-defense review first.')

    if not is_post and is_defense_done and not is_admin and not (admin_unlocked or submission.revision_review_unlocked):
        raise PermissionError('Pre-defense deliverables for completed defenses are view-only for faculty. Resubmission requests must be unlocked by an Admin.')

    if status_val not in (DeliverableSubmission.STATUS_ACCEPTED, DeliverableSubmission.STATUS_REJECTED):
        raise ValueError('Invalid review status action.')
    if is_post and status_val == DeliverableSubmission.STATUS_REJECTED and not (feedback_val or '').strip():
        raise ValueError('Explain what the team must correct before requesting a post-defense revision.')

    from .documents import review_files
    stage = document_context(team, stage_label)
    from defense.document_policy import is_approved_concept
    if concept_access is not None and is_approved_concept(definition or {}) and status_val == 'accepted':
        selected = next((c['key'] for c in concept_round.concepts if c.get('decision') in ('approved', 'approved_with_revisions')), '') if concept_round else ''
        targets = submission.files.filter(is_current=True)
        if file_id:
            targets = targets.filter(pk=file_id)
        if not targets.exists() or any(f.concept_round_id != getattr(concept_round, 'pk', None)
                or f.selected_concept_key != selected for f in targets):
            raise ValueError('Review the final paper uploaded for the current selected concept and hearing.')
    if not check_review_assignment(reviewer_user, team):
        raise PermissionError('Only assigned faculty can review this team.')
    from repository import title_workflow
    concept_file = (definition or {}).get('file_policy', {}).get('mode') == 'concepts' and not is_post
    if revision_scope == 'title_and_paper' and (not concept_file or not title_workflow.enabled(concept_round) or not file_id):
        raise ValueError('Choose a current concept file with a matching title for a combined revision.')
    if concept_file and title_workflow.enabled(concept_round) and file_id:
        from .concepts import module_review_token
        if title_review_token != module_review_token(team, stage):
            raise ValueError('The title changed. Refresh before reviewing this file.')
    if status_val == 'rejected' and concept_file and title_workflow.enabled(concept_round):
        if not current_target:
            raise ValueError('Choose the exact file to return for revision.')
        title_workflow.revise_file(concept_round, current_target.slot_key.split(':')[0], reviewer_user, feedback_val or '', current_target, revision_scope, 'team')
    review_files(submission, definition or {}, status_val, feedback_val or '', reviewer_user, file_id=file_id, stage=stage)
    submission.status = status_val
    submission.feedback = (feedback_val or '').strip()
    submission.reviewed_by = reviewer_user
    submission.reviewed_at = timezone.now()
    submission.revision_review_unlocked = not is_post and status_val == DeliverableSubmission.STATUS_REJECTED
    submission.file_replacement_unlocked = False
    submission.file_replacement_reason = ''
    submission.save(update_fields=[
        'status', 'feedback', 'reviewed_by', 'reviewed_at',
        'revision_review_unlocked', 'file_replacement_unlocked', 'file_replacement_reason',
    ])

    if definition and definition.get('file_policy'):
        from .documents import sync_submission
        sync_submission(submission, definition, stage)
    if status_val == DeliverableSubmission.STATUS_REJECTED:
        from .concepts import invalidate_clearance
        invalidate_clearance(team, stage_label, deliverable_id)

    if is_post and status_val == DeliverableSubmission.STATUS_ACCEPTED:
        if clear_defense_revisions and concept_access is not None:
            from .concept_completion import final_paper_complete
            if not is_approved_concept(definition or {}) or not final_paper_complete(team, stage, required=True):
                raise ValueError('Clear concept revisions with the accepted final paper for the selected concept.')
        from grading.grades.models import TeamGrade
        stage_grade = latest_stage_grade(team, stage_label)
        if stage_grade and stage_grade.verdict == 'approved_with_revisions' and not stage_grade.revisions_cleared_at:
            if clear_defense_revisions:
                from grading.grades.defense_workflow import apply_workflow_action
                reason = (feedback_val or '').strip() or f"Post-defense deliverable '{submission.label or deliverable_id}' approved."
                apply_workflow_action(stage_grade, actor=reviewer_user, action='clear_revisions', reason=reason)
        elif stage_grade and stage_grade.verdict in ('approved', 'approved_with_revisions'):
            from grading.grades.services import maybe_auto_finalize_passed_grade
            maybe_auto_finalize_passed_grade(stage_grade, user=reviewer_user)
        if (is_approved_concept(definition or {}) and team.is_pit and concept_round
                and concept_round.verdict == 'approved_with_revisions' and not concept_round.revisions_cleared_at):
            from .concept_completion import final_paper_complete
            if not final_paper_complete(team, stage, required=True):
                return submission
            concept_round.revisions_cleared_at = timezone.now()
            concept_round.revisions_cleared_by = reviewer_user
            concept_round.save(update_fields=['revisions_cleared_at', 'revisions_cleared_by'])
            from authentication_access_control.audit import log_high_impact_action
            from authentication_access_control.models import SystemAuditLog
            log_high_impact_action(
                category=SystemAuditLog.CATEGORY_REPOSITORY,
                action='repository.pit_concept_revisions_cleared',
                target=concept_round, actor=reviewer_user,
                reason=(feedback_val or '').strip() or f"Post-defense deliverable '{submission.label or deliverable_id}' approved.",
                new_values={'team_id': team.pk, 'round': concept_round.number}, strict=True
            )

    # Re-evaluate team readiness if we are rejecting a required pre-defense deliverable
    if status_val == DeliverableSubmission.STATUS_REJECTED and not is_defense_done:
        if (pit_endorsed(team, stage_label) if team.is_pit else team.ready_for_stage == stage_label) and not required_complete(team, stage_label):
            if team.is_capstone:
                stage = defense_stage_for_label(stage_label)
                if stage is not None:
                    mark_stage_locked(team, stage)
                else:
                    team.ready_for_stage = None
                    team.save(update_fields=['ready_for_stage', 'updated_at'])
            else:
                set_pit_endorsed(team, stage_label, False)
                if team.ready_for_stage == stage_label:
                    team.ready_for_stage = None
                    team.save(update_fields=['ready_for_stage', 'updated_at'])

    if is_post and team.is_capstone:
        # Publishing the academic record can precede file clearance. Reflect
        # the last file review (or an explicit reopening) in stage progression.
        from grading.grades.models import TeamGrade
        from grading.grades.services import _apply_team_result_from_grade
        from grading.grades.defense_workflow import legacy_finalized_pass
        grade = latest_stage_grade(team, stage_label)
        if grade and (grade.verdict in TeamGrade.PASSING_VERDICTS or legacy_finalized_pass(grade)):
            _apply_team_result_from_grade(grade)

    return submission
