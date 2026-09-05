from django.core.exceptions import ValidationError
from django.db import transaction

from django.db.models import Q

from academic_period_management.models import Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam
from student_teams.services import is_stage_ready, mark_stage_locked, mark_stage_ready, was_stage_endorsed
from .models import DeliverableSubmission


class DynamicStageOptionsList(list):
    def _get_stages(self):
        try:
            return list(
                DefenseStage.objects.filter(is_active=True)
                .order_by('display_order', 'label')
                .values_list('label', flat=True)
            )
        except Exception:
            return []

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


def get_deliverable_definitions(stage_label):
    """Load deliverable definitions configured in Defense Stages (database only)."""
    try:
        stage = DefenseStage.objects.prefetch_related('deliverables').get(label=stage_label)
        deliverables = stage.deliverables.all()
        return [
            {
                'id': (d.deliverable_id or '').strip(),
                'label': d.label,
                'required': d.required,
                'type': d.deliverable_type,
                'archive_note': d.archive_note,
                'archive_file_template': d.archive_file_template,
                'is_restricted': d.is_restricted,
            }
            for d in deliverables
            if (d.deliverable_id or '').strip()
        ]
    except DefenseStage.DoesNotExist:
        return []


def get_deliverable_definitions_for_team(team, stage_label):
    """Load deliverable definitions configured for a Capstone stage or PIT event."""
    if not team or not stage_label:
        return []
    if team.is_capstone:
        return get_deliverable_definitions(stage_label)
    
    # It's a PIT team! stage_label here is the event name.
    from defense.scheduler.models import PitEventGradingConfig
    config = PitEventGradingConfig.objects.filter(
        semester=team.semester,
        event_name__iexact=stage_label.strip()
    ).prefetch_related('deliverables').first()
    if not config:
        return []
    return [
        {
            'id': (d.deliverable_id or '').strip(),
            'label': d.label,
            'required': d.required,
            'type': d.deliverable_type,
            'archive_note': d.archive_note,
            'archive_file_template': d.archive_file_template,
            'is_restricted': d.is_restricted,
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


def current_stage_for_team(team):
    if not team:
        return default_stage_label()
    if team.is_capstone:
        from defense.scheduler.models import DefenseSchedule
        from defense.stages.models import DefenseStage, StageGradingConfig
        from student_teams.models import TeamStageProgress
        from grading.grades.models import TeamGrade
        from grading.constants import PASS_GRADE_THRESHOLD

        # 1. If currently scheduled, the scheduled stage is active
        sched = (
            DefenseSchedule.objects.filter(
                team=team,
                scope=DefenseSchedule.SCOPE_CAPSTONE,
                status=DefenseSchedule.STATUS_SCHEDULED,
            )
            .order_by('scheduled_date', 'start_time')
            .first()
        )
        if sched and sched.defense_stage:
            return sched.defense_stage.label

        # 2. Get all configured active stages in sequential order
        stages = list(
            DefenseStage.objects.filter(is_active=True).order_by('display_order', 'id')
        )
        if not stages:
            return team.current_defense_stage or team.ready_for_stage or default_stage_label()

        # 3. Check completion for each stage in order
        completed_stage_ids = set()
        for stg in stages:
            # Check if stage is marked officially complete for this semester
            if team.semester_id and StageGradingConfig.objects.filter(
                semester=team.semester,
                defense_stage=stg,
                is_officially_complete=True,
            ).exists():
                completed_stage_ids.add(stg.id)
                continue

            # Check if team has passed/archived progress for this stage
            if TeamStageProgress.objects.filter(
                team=team,
                defense_stage=stg,
                status__in=[TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_ARCHIVED],
            ).exists():
                completed_stage_ids.add(stg.id)
                continue

            # Check if team has a passing published grade for this stage
            if TeamGrade.objects.filter(
                team=team,
                defense_stage=stg,
                status=TeamGrade.STATUS_PUBLISHED,
                final_grade__gte=PASS_GRADE_THRESHOLD,
            ).exists():
                completed_stage_ids.add(stg.id)
                continue

        # 4. Find the first uncompleted stage in order
        for stg in stages:
            if stg.id not in completed_stage_ids:
                return stg.label

        # 5. If all configured stages are completed, return the last completed stage
        return stages[-1].label
    else:
        # For PIT: find the scheduled schedule or the first event config
        from defense.scheduler.models import DefenseSchedule
        sched = (
            DefenseSchedule.objects.filter(
                team=team,
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
        from repository.project_archive.services import PIT_YEAR_EVENT_HINTS
        configs_qs = PitEventGradingConfig.objects.filter(semester=team.semester)
        if team.year_level:
            exclude_filter = Q()
            for y, hints in PIT_YEAR_EVENT_HINTS.items():
                if y != team.year_level:
                    for hint in hints:
                        exclude_filter |= Q(event_name__icontains=hint)
            if exclude_filter:
                configs_qs = configs_qs.exclude(exclude_filter)
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
                scope=DefenseSchedule.SCOPE_PIT,
            )
            .order_by('-scheduled_date', '-start_time')
            .first()
        )
        if sched_any and sched_any.event_name:
            return sched_any.event_name
            
        return 'No PIT event configured'


def team_queryset_for_user(user):
    queryset = (
        StudentTeam.objects.select_related(
            'semester',
            'semester__school_year',
            'leader',
            'adviser',
        )
        .prefetch_related(
            'memberships',
            'memberships__student',
            'deliverable_submissions',
        )
    )

    if getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False):
        return queryset
    if getattr(user, 'role', None) == 'faculty':
        q = Q()
        if getattr(user, 'is_adviser', False):
            q |= Q(adviser=user)
        if getattr(user, 'is_pit_lead', False):
            pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
            if pit_year:
                q |= Q(level__icontains=pit_year) & Q(level__icontains='PIT')
            else:
                q |= Q(level__icontains='PIT')
        
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
                    level__icontains=norm_year
                )

        if getattr(user, 'is_adviser', False) or getattr(user, 'is_pit_lead', False) or assignments.exists():
            return queryset.filter(q)
        return queryset.none()
    if getattr(user, 'role', None) == 'student':
        return queryset.filter(memberships__student=user).distinct()
    return queryset.none()


def filter_teams(request, queryset):
    search = request.query_params.get('search', '').strip()
    status_filter = request.query_params.get('status', '').strip()
    year_level = request.query_params.get('year_level', '').strip()

    if year_level:
        queryset = queryset.filter(year_level=year_level)

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

    if status_filter in ('ready', 'endorsed'):
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


def archive_unlocked(team, stage_label, deliverable_type='post'):
    if deliverable_type == 'pre':
        if is_stage_unlocked_by_admin(team, stage_label, deliverable_type='pre'):
            return True
        if team.is_capstone:
            stage_obj = defense_stage_for_label(stage_label)
            if stage_obj and was_stage_endorsed(team, stage_obj):
                return True
        else:
            if team.ready_for_stage == stage_label:
                return True
        return is_stage_unlocked_by_admin(team, stage_label, deliverable_type='all') or is_stage_unlocked_by_admin(team, stage_label)

    if is_stage_unlocked_by_admin(team, stage_label, deliverable_type='post') or is_stage_unlocked_by_admin(team, stage_label, deliverable_type='all') or is_stage_unlocked_by_admin(team, stage_label):
        return True
    if is_stage_defense_done(team, stage_label):
        return True
    return DefenseSchedule.objects.filter(
        team=team,
        status=DefenseSchedule.STATUS_DONE,
    ).filter(Q(defense_stage__label=stage_label) | Q(event_name=stage_label)).exists()



def submissions_for(team, stage_label):
    return {
        submission.deliverable_id: submission
        for submission in DeliverableSubmission.objects.filter(team=team, stage_label=stage_label)
    }


def is_presentation_stage(team, stage_label):
    if not stage_label:
        return False
    if not team or getattr(team, 'is_capstone', True):
        stage = defense_stage_for_label(stage_label)
        if stage and getattr(stage, 'is_presentation_only', False):
            return True
    else:
        from defense.scheduler.models import PitEventGradingConfig
        sem = getattr(team, 'semester', None)
        if sem:
            config = PitEventGradingConfig.objects.filter(
                semester=sem,
                event_name__iexact=stage_label.strip(),
            ).prefetch_related('deliverables').first()
            if config and not config.deliverables.exists():
                return True
    return False


def stage_deliverables_configured(team, stage_label):
    if is_presentation_stage(team, stage_label):
        return True
    return bool(get_deliverable_definitions_for_team(team, stage_label))


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
        if item['type'] == DeliverableSubmission.TYPE_PRE and item['required']
    ]
    if not required_items:
        return True
    return all(
        item['id'] in submitted
        and (
            submitted[item['id']].status != DeliverableSubmission.STATUS_REJECTED
            if not getattr(team, 'is_capstone', False) else
            submitted[item['id']].status == DeliverableSubmission.STATUS_ACCEPTED
        )
        for item in required_items
    )


def team_stage_status(team, stage_label):
    configured = stage_deliverables_configured(team, stage_label)
    if not configured:
        return 'not_configured'
    is_endorsed = was_stage_endorsed(team, defense_stage_for_label(stage_label)) if team.is_capstone else (team.ready_for_stage == stage_label)
    if is_endorsed:
        return 'endorsed'
    if required_complete(team, stage_label):
        return 'complete'
    
    # Check submissions
    submitted = submissions_for(team, stage_label)
    definitions = get_deliverable_definitions_for_team(team, stage_label)
    required_items = [item for item in definitions if item['type'] == DeliverableSubmission.TYPE_PRE and item['required']]
    if not required_items:
        return 'complete'
        
    all_uploaded = all(item['id'] in submitted for item in required_items)
    if not all_uploaded:
        return 'missing'
        
    any_rejected = any(
        submitted[item['id']].status == DeliverableSubmission.STATUS_REJECTED
        for item in required_items
        if item['id'] in submitted
    )
    if any_rejected:
        return 'needs_revision'
        
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
    progress_status = progress.status if progress else ('ready' if team.ready_for_stage == stage_label else 'locked')

    today = timezone.localdate()
    active_schedules = DefenseSchedule.objects.filter(
        scope=DefenseSchedule.SCOPE_CAPSTONE if is_capstone else DefenseSchedule.SCOPE_PIT,
        team=team,
        status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE]
    )
    if stage_obj:
        active_schedules = active_schedules.filter(defense_stage=stage_obj)
    else:
        active_schedules = active_schedules.filter(event_name=stage_label)

    is_defense_today = active_schedules.filter(scheduled_date=today).exists()
    has_active_schedule = active_schedules.filter(status=DefenseSchedule.STATUS_SCHEDULED).exists()
    has_done_schedule = active_schedules.filter(status=DefenseSchedule.STATUS_DONE).exists()

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
            event_name=stage_label,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()

    if is_officially_complete or progress_status in [TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_GRADING] or has_done_schedule:
        if archive_required_complete or is_officially_complete:
            return 'passed'
        else:
            return 'pending_post_defense'
    elif progress_status == TeamStageProgress.STATUS_SCHEDULED or has_active_schedule:
        if is_defense_today:
            return 'defense_ongoing'
        else:
            return 'defense_scheduled'
    elif progress_status == TeamStageProgress.STATUS_READY or (not is_capstone and team.ready_for_stage == stage_label):
        return 'endorsed'
    else:
        return 'awaiting_endorsement'


def is_stage_defense_done(team, stage_label):
    from student_teams.models import TeamStageProgress
    from student_teams.services import get_stage_progress
    from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
    from defense.stages.models import StageGradingConfig

    is_capstone = getattr(team, 'is_capstone', False)
    stage_obj = defense_stage_for_label(stage_label) if is_capstone else None
    progress = get_stage_progress(team, stage_obj) if stage_obj else None
    progress_status = progress.status if progress else ''

    active_schedules = DefenseSchedule.objects.filter(
        scope=DefenseSchedule.SCOPE_CAPSTONE if is_capstone else DefenseSchedule.SCOPE_PIT,
        team=team,
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
            event_name=stage_label,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()

    return progress_status in [TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_GRADING] or has_done_schedule or is_officially_complete


def is_stage_unlocked_by_admin(team, stage_label, deliverable_type=None):
    unlocked_stages = getattr(team, 'unlocked_stages', []) or []
    if stage_label in unlocked_stages:
        return True
    if f"{stage_label}:all" in unlocked_stages:
        return True
    if deliverable_type and f"{stage_label}:{deliverable_type}" in unlocked_stages:
        return True
    return False


@transaction.atomic
def toggle_stage_deliverables_unlock(team, stage_label, user, unlock_type='all', target_state=None):
    is_admin = getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False)
    is_pit_lead = getattr(user, 'is_pit_lead', False) and getattr(team, 'is_pit', False)
    
    if not (is_admin or is_pit_lead):
        raise PermissionError('Only Admin, Capstone Coordinator, or PIT Lead can unlock deliverables for defense stages.')

    if is_pit_lead and not is_admin:
        from student_teams.team_levels import normalize_year_level
        pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
        if pit_year and normalize_year_level(team.year_level) != normalize_year_level(pit_year):
            raise PermissionError('PIT Leads can only unlock deliverables for teams in their assigned year level.')

    unlocked_stages = set(getattr(team, 'unlocked_stages', []) or [])
    
    all_key = f"{stage_label}:all"
    pre_key = f"{stage_label}:pre"
    post_key = f"{stage_label}:post"
    legacy_key = stage_label

    if unlock_type == 'pre':
        currently_unlocked = (legacy_key in unlocked_stages or all_key in unlocked_stages or pre_key in unlocked_stages)
    elif unlock_type == 'post':
        currently_unlocked = (legacy_key in unlocked_stages or all_key in unlocked_stages or post_key in unlocked_stages)
    else:
        currently_unlocked = (legacy_key in unlocked_stages or all_key in unlocked_stages or (pre_key in unlocked_stages and post_key in unlocked_stages))

    new_state = (not currently_unlocked) if target_state is None else bool(target_state)

    if new_state:
        if unlock_type == 'all':
            unlocked_stages.add(all_key)
            unlocked_stages.add(pre_key)
            unlocked_stages.add(post_key)
            unlocked_stages.add(legacy_key)
        elif unlock_type == 'pre':
            unlocked_stages.add(pre_key)
        elif unlock_type == 'post':
            unlocked_stages.add(post_key)
    else:
        if unlock_type == 'all':
            unlocked_stages.discard(all_key)
            unlocked_stages.discard(pre_key)
            unlocked_stages.discard(post_key)
            unlocked_stages.discard(legacy_key)
        elif unlock_type == 'pre':
            unlocked_stages.discard(pre_key)
            unlocked_stages.discard(all_key)
            unlocked_stages.discard(legacy_key)
        elif unlock_type == 'post':
            unlocked_stages.discard(post_key)
            unlocked_stages.discard(all_key)
            unlocked_stages.discard(legacy_key)

    team.unlocked_stages = list(unlocked_stages)
    team.save(update_fields=['unlocked_stages', 'updated_at'])
    return new_state


@transaction.atomic
def toggle_global_stage_deliverables_unlock(stage_label, user, scope='capstone', year_level=None, unlock_type='all', target_state=None):
    is_admin = getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False)
    is_pit_lead = getattr(user, 'is_pit_lead', False)
    
    if not (is_admin or (is_pit_lead and scope == 'pit')):
        raise PermissionError('Permission denied to perform global stage unlock.')

    if scope == 'capstone' and not is_admin:
        raise PermissionError('Only Admin or Capstone Coordinator can manage global Capstone stage unlocks.')

    from student_teams.models import StudentTeam
    from student_teams.team_levels import normalize_year_level

    teams_qs = StudentTeam.objects.all()
    if scope == 'capstone':
        teams = [t for t in teams_qs if t.is_capstone]
    else:
        if is_pit_lead and not is_admin:
            user_pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
            if not user_pit_year:
                raise PermissionError('PIT Leads must have an assigned year level to manage stage access.')
            year_level = user_pit_year

            # Validate that stage_label is actually a PIT event for this year level
            from repository.project_archive.services import pit_event_matches_year_level
            from defense.scheduler.models import PitEventGradingConfig
            from academic_period_management.models import Semester
            active_sem = Semester.objects.filter(is_active=True).first()
            valid_event_names = list(
                PitEventGradingConfig.objects.filter(semester=active_sem)
                .values_list('event_name', flat=True)
            ) if active_sem else []
            stage_is_valid_pit_event = (
                stage_label in valid_event_names
                and pit_event_matches_year_level(stage_label, user_pit_year)
            )
            if not stage_is_valid_pit_event:
                raise PermissionError(
                    f'Stage "{stage_label}" is not a configured PIT event for {user_pit_year}.'
                )

        teams = [t for t in teams_qs if t.is_pit]
        if year_level:
            teams = [t for t in teams if normalize_year_level(t.year_level) == normalize_year_level(year_level)]

    for t in teams:
        toggle_stage_deliverables_unlock(t, stage_label, user, unlock_type=unlock_type, target_state=target_state)

    return True



def stage_payload(team, stage_label):
    submitted = submissions_for(team, stage_label)
    definitions = get_deliverable_definitions_for_team(team, stage_label)
    unlocked = archive_unlocked(team, stage_label)
    rows = []

    from repository.project_archive.services import resolve_archive_file_template
    from academic_period_management.models import Semester
    from student_teams.services import get_stage_progress
    from defense.stages.models import StageGradingConfig
    from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
    from django.utils import timezone

    semester_label = team.semester.label if team.semester_id else Semester.FIRST

    is_capstone = getattr(team, 'is_capstone', False)
    stage_obj = defense_stage_for_label(stage_label) if is_capstone else None
    progress = get_stage_progress(team, stage_obj) if stage_obj else None
    progress_status = progress.status if progress else ('ready' if team.ready_for_stage == stage_label else 'locked')
    is_endorsed = was_stage_endorsed(team, stage_obj) if is_capstone else (team.ready_for_stage == stage_label)

    today = timezone.localdate()
    active_schedules = DefenseSchedule.objects.filter(
        scope=DefenseSchedule.SCOPE_CAPSTONE if is_capstone else DefenseSchedule.SCOPE_PIT,
        team=team,
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
            event_name=stage_label,
            is_officially_complete=True,
        ).filter(
            Q(semester=sem) if sem else Q()
        ).exists()

    is_defense_done = is_stage_defense_done(team, stage_label)
    admin_unlocked_pre = is_stage_unlocked_by_admin(team, stage_label, deliverable_type='pre') or is_stage_unlocked_by_admin(team, stage_label)
    admin_unlocked_post = is_stage_unlocked_by_admin(team, stage_label, deliverable_type='post') or is_stage_unlocked_by_admin(team, stage_label)
    can_faculty_review_pre = ((not is_endorsed and not is_defense_done) or admin_unlocked_pre)
    can_faculty_review_post = True

    can_cancel_endorsement = bool(
        is_endorsed
        and not has_active_schedule
        and not has_done_schedule
        and not is_stage_officially_complete
        and not is_defense_done
    )

    for item in definitions:
        submission = submitted.get(item['id'])
        is_vault = item['type'] == DeliverableSubmission.TYPE_POST
        can_review_item = can_faculty_review_post if is_vault else can_faculty_review_pre
        
        suggested = ''
        if is_vault:
            suggested = resolve_archive_file_template(
                item.get('archive_file_template', ''),
                team,
                stage_label,
                semester_label,
                deliverable_label=item['label'],
            )

        rows.append({
            'id': item['id'],
            'label': item['label'],
            'required': item['required'],
            'type': item['type'],
            'archive_note': item.get('archive_note', ''),
            'suggested_file_name': suggested,
            'uploaded': submission is not None,
            'locked': is_vault and not unlocked,
            'can_faculty_review': can_review_item,
            'submission': submission_payload(submission) if submission else None,
        })

    pre_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_PRE]
    archive_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_POST]
    required_items = [item for item in pre_items if item['required']]
    archive_required_items = [item for item in archive_items if item['required']]

    is_pres = is_presentation_stage(team, stage_label)
    configured = len(definitions) > 0 or is_pres
    archive_required_complete = (
        not archive_required_items
        or all(item['uploaded'] for item in archive_required_items)
    )
    
    stage_status_detail = compute_stage_status_detail(team, stage_label, configured, archive_required_complete)

    return {
        'stage_label': stage_label,
        'deliverables_configured': configured,
        'is_presentation_only': is_pres,
        'endorsed': is_endorsed,
        'is_officially_complete': is_stage_officially_complete,
        'has_active_schedule': has_active_schedule,
        'has_done_schedule': has_done_schedule,
        'can_cancel_endorsement': can_cancel_endorsement,
        'archive_unlocked': unlocked,
        'vault_unlocked': unlocked,
        'pre_unlocked': archive_unlocked(team, stage_label, deliverable_type='pre'),
        'post_unlocked': archive_unlocked(team, stage_label, deliverable_type='post'),
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
        'archive_required_total': len(archive_required_items),
        'archive_complete': unlocked and archive_required_complete,
        'pre': pre_items,
        'post': archive_items,
        'deliverables': rows,
    }


def submission_payload(submission):
    if submission is None:
        return None
        
    files_list = list(submission.files.all().order_by('-uploaded_at'))
    if len(files_list) > 1:
        latest = files_list[0]
        for extra in files_list[1:]:
            try:
                if extra.file:
                    extra.file.delete(save=False)
            except Exception:
                pass
            extra.delete()
        files_list = [latest]

    files_data = []
    for f in files_list:
        files_data.append({
            'id': f.id,
            'file_name': f.file_name,
            'file_size': f.file_size,
            'file_url': f.file.url if f.file else None,
            'uploaded_at': f.uploaded_at,
        })
        
    return {
        'id': submission.id,
        'deliverable_id': submission.deliverable_id,
        'files': files_data,
        'file_name': files_data[0]['file_name'] if files_data else '',
        'file_size': files_data[0]['file_size'] if files_data else '',
        'file_url': files_data[0]['file_url'] if files_data else None,
        'uploaded_by_name': display_name(submission.uploaded_by),
        'uploaded_at': submission.uploaded_at,
        'status': submission.status,
        'feedback': submission.feedback,
        'reviewed_by_name': display_name(submission.reviewed_by),
        'reviewed_at': submission.reviewed_at,
    }


def team_payload(team, selected_stage=None):
    if team.is_capstone:
        configured_stage_labels = list(STAGE_OPTIONS)
    else:
        from defense.scheduler.models import PitEventGradingConfig
        from repository.project_archive.services import PIT_YEAR_EVENT_HINTS
        configs_qs = PitEventGradingConfig.objects.filter(semester=team.semester)
        if team.year_level:
            exclude_filter = Q()
            for y, hints in PIT_YEAR_EVENT_HINTS.items():
                if y != team.year_level:
                    for hint in hints:
                        exclude_filter |= Q(event_name__icontains=hint)
            if exclude_filter:
                configs_qs = configs_qs.exclude(exclude_filter)
        configured_stage_labels = list(
            configs_qs.order_by('event_name')
            .values_list('event_name', flat=True)
        )
    selected = selected_stage or current_stage_for_team(team)
    stages = [stage_payload(team, stage) for stage in configured_stage_labels]
    if configured_stage_labels and selected not in configured_stage_labels:
        selected = configured_stage_labels[0]
    selected_payload = next(
        (item for item in stages if item['stage_label'] == selected),
        stage_payload(team, selected) if selected else stage_payload(team, ''),
    )

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
        if team.is_capstone:
            grade_obj = TeamGrade.objects.filter(
                Q(defense_stage__label=selected) | Q(stage_label=selected),
                team=team,
                semester=team.semester,
                scope=TeamGrade.SCOPE_CAPSTONE,
            ).order_by('-updated_at', '-id').first()
        else:
            grade_obj = TeamGrade.objects.filter(
                Q(pit_event_config__event_name=selected) | Q(stage_label=selected),
                team=team,
                semester=team.semester,
                scope=TeamGrade.SCOPE_PIT,
            ).order_by('-updated_at', '-id').first()

        if grade_obj:
            student_grades = StudentStageGrade.objects.filter(team_grade=grade_obj)
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
                'is_officially_complete': bool(selected_payload.get('is_officially_complete', False)),
                'peer_per_student': peer_per_student,
            }

    return {
        'id': team.id,
        'name': team.name,
        'project_title': team.project_title,
        'level': team.level,
        'year_level': team.year_level,
        'section': team.section,
        'status': team.status,
        'ready_for_stage': team.ready_for_stage,
        'current_defense_stage': team.current_defense_stage,
        'current_stage': current_stage_for_team(team),
        'selected_stage': selected_payload,
        'stages': stages,
        'adviser_name': display_name(team.adviser),
        'leader_name': display_name(team.leader),
        'member_count': team.memberships.count(),
        'submitted_count': team.deliverable_submissions.count(),
        'members': members,
        'grade': grade_payload,
    }


def counts_payload(teams, selected_stage=None):
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
        elif team.ready_for_stage:
            ready_count += 1

    archive_total = DeliverableSubmission.objects.filter(
        team__in=team_list,
        deliverable_type=DeliverableSubmission.TYPE_POST,
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
def upsert_submission(team, stage_label, deliverable_id, file_name, file_size, user, file=None, file_id=None):
    deliverable_id = (deliverable_id or '').strip()
    if not team.is_capstone and not team.is_pit:
        raise PermissionError('Only Capstone or PIT teams can submit deliverables.')
    definition = definition_for(team, stage_label, deliverable_id)
    if definition is None:
        raise ValueError('Deliverable does not exist for this stage.')
    if definition['type'] == DeliverableSubmission.TYPE_POST:
        if not archive_unlocked(team, stage_label):
            raise PermissionError('Post-Defense submissions are locked until this defense is done.')
        
        # Check naming convention
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
        if suggested:
            import os
            suggested_base, _ = os.path.splitext(suggested.lower())
            uploaded_name = file_name.strip().lower()
            if not uploaded_name.startswith(suggested_base):
                raise ValidationError({'file_name': f"Filename must start with the naming convention prefix. Expected prefix: '{suggested_base}'"})

    # Ensure DeliverableSubmission container exists
    submission, created = DeliverableSubmission.objects.get_or_create(
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

    # Check if this upload is a simple file replacement (Choice B: Approved status preserved)
    was_replacement_unlocked = (
        'Unlocked for file replacement' in (submission.feedback or '')
        and submission.status == DeliverableSubmission.STATUS_ACCEPTED
    )

    if not created:
        if was_replacement_unlocked:
            submission.status = DeliverableSubmission.STATUS_ACCEPTED
            submission.feedback = ''
        else:
            submission.status = DeliverableSubmission.STATUS_PENDING
            submission.feedback = ''
        submission.uploaded_by = user
        submission.save(update_fields=['status', 'feedback', 'uploaded_by', 'uploaded_at'])

    # Create/update file in DeliverableSubmissionFile
    from django.core.files.base import ContentFile
    from repository.deliverables.models import DeliverableSubmissionFile

    file_obj = None
    if file_id:
        file_obj = submission.files.filter(id=file_id).first()
        
    if not file_obj and file:
        file_obj = submission.files.filter(file_name=file_name.strip()).first()

    if not file_obj and submission.files.exists():
        # Overwrite existing primary file for single-file deliverables rather than creating duplicate file rows!
        file_obj = submission.files.order_by('uploaded_at').first()
        # Clean up any secondary duplicate files if they exist from past uploads
        for extra in submission.files.exclude(id=file_obj.id):
            try:
                if extra.file:
                    extra.file.delete(save=False)
            except Exception:
                pass
            extra.delete()

    target_file_name = file_name.strip()
    if file_obj and file_obj.file and file is not None:
        import os
        target_file_name = os.path.basename(file_obj.file.name)
        try:
            file_obj.file.delete(save=False)
        except Exception:
            pass

    if file_obj:
        file_obj.file_name = file_name.strip()
        file_obj.file_size = (file_size or '').strip()
        if file is not None:
            file_obj.file = ContentFile(file.read(), name=target_file_name)
            file_obj.extracted_text = ''
            file_obj.topics = []
            file_obj.summary = ''
            file_obj.category = ''
            file_obj.category_confidence = None
        file_obj.save()
    else:
        file_obj = DeliverableSubmissionFile(
            submission=submission,
            file_name=file_name.strip(),
            file_size=(file_size or '').strip(),
        )
        if file is not None:
            file_obj.file = ContentFile(file.read(), name=target_file_name)
        file_obj.save()

    # Sync latest file to the parent submission for backward compatibility
    latest_file = submission.files.order_by('-uploaded_at').first()
    if latest_file:
        submission.file_name = latest_file.file_name
        submission.file_size = latest_file.file_size
        submission.file = latest_file.file
        submission.extracted_text = latest_file.extracted_text
        submission.topics = latest_file.topics
        submission.summary = latest_file.summary
        submission.category = latest_file.category
        submission.category_confidence = latest_file.category_confidence
        submission.save(update_fields=[
            'file_name', 'file_size', 'file', 'extracted_text',
            'topics', 'summary', 'category', 'category_confidence', 'uploaded_at'
        ])

    return submission


@transaction.atomic
def remove_submission(team, stage_label, deliverable_id, file_id=None):
    try:
        submission = DeliverableSubmission.objects.get(
            team=team,
            stage_label=stage_label,
            deliverable_id=deliverable_id,
        )
    except DeliverableSubmission.DoesNotExist:
        return 0

    deleted = 0
    if file_id:
        file_to_delete = submission.files.filter(id=file_id).first()
        if file_to_delete:
            if file_to_delete.file:
                try:
                    file_to_delete.file.delete(save=False)
                except Exception:
                    pass
            file_to_delete.delete()
            deleted = 1
            
        # Delete submission container if no files remain
        if not submission.files.exists():
            submission.delete()
        else:
            # Sync backward compatibility fields with the remaining latest file
            latest_file = submission.files.order_by('-uploaded_at').first()
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
            if f.file:
                try:
                    f.file.delete(save=False)
                except Exception:
                    pass
        submission.delete()
        deleted = 1

    if hasattr(team, '_prefetched_objects_cache'):
        team._prefetched_objects_cache.pop('deliverable_submissions', None)
    if team.ready_for_stage == stage_label and not required_complete(team, stage_label):
        if team.is_capstone:
            stage = defense_stage_for_label(stage_label)
            if stage is not None:
                mark_stage_locked(team, stage)
            else:
                team.ready_for_stage = None
                team.save(update_fields=['ready_for_stage', 'updated_at'])
        else:
            team.ready_for_stage = None
            team.save(update_fields=['ready_for_stage', 'updated_at'])
    return deleted


@transaction.atomic
def endorse_team(team, stage_label):
    if not stage_deliverables_configured(team, stage_label):
        raise ValueError(
            'No deliverables configured for this stage. Add them in Defense Stages or PIT configs before endorsement.'
        )
    if not required_complete(team, stage_label):
        raise ValueError('All required pre-defense deliverables must be uploaded before endorsement.')
    if team.is_capstone:
        stage = defense_stage_for_label(stage_label)
        if stage is None:
            raise ValueError('Defense stage does not exist.')
        mark_stage_ready(team, stage)
    else:
        team.ready_for_stage = stage_label
        team.save(update_fields=['ready_for_stage', 'updated_at'])
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
            event_name__iexact=stage_label,
            scope=DefenseSchedule.SCOPE_PIT,
            status__in=[DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE],
        ).exists()
        if has_schedule:
            raise ValueError('Cannot cancel endorsement: defense is already scheduled or completed.')

        if team.ready_for_stage == stage_label:
            team.ready_for_stage = None
            team.save(update_fields=['ready_for_stage', 'updated_at'])
    return team


@transaction.atomic
def review_submission(team, stage_label, deliverable_id, status_val, feedback_val, reviewer_user):
    from django.utils import timezone

    try:
        submission = DeliverableSubmission.objects.get(
            team=team,
            stage_label=stage_label,
            deliverable_id=deliverable_id
        )
    except DeliverableSubmission.DoesNotExist:
        raise ValueError('Deliverable submission not found.')

    is_admin = getattr(reviewer_user, 'role', None) == 'admin' or getattr(reviewer_user, 'is_superuser', False)
    is_defense_done = is_stage_defense_done(team, stage_label)
    is_post = submission.deliverable_type == DeliverableSubmission.TYPE_POST
    admin_unlocked = is_stage_unlocked_by_admin(team, stage_label, deliverable_type=submission.deliverable_type)

    if not is_post and is_defense_done and not is_admin and not admin_unlocked:
        raise PermissionError('Pre-defense deliverables for completed defenses are view-only for faculty. Resubmission requests must be unlocked by an Admin.')

    if status_val not in (DeliverableSubmission.STATUS_ACCEPTED, DeliverableSubmission.STATUS_REJECTED):
        raise ValueError('Invalid review status action.')

    submission.status = status_val
    submission.feedback = (feedback_val or '').strip()
    submission.reviewed_by = reviewer_user
    submission.reviewed_at = timezone.now()
    submission.save()

    # Re-evaluate team readiness if we are rejecting a required pre-defense deliverable
    if status_val == DeliverableSubmission.STATUS_REJECTED:
        if team.ready_for_stage == stage_label and not required_complete(team, stage_label):
            if team.is_capstone:
                stage = defense_stage_for_label(stage_label)
                if stage is not None:
                    mark_stage_locked(team, stage)
                else:
                    team.ready_for_stage = None
                    team.save(update_fields=['ready_for_stage', 'updated_at'])
            else:
                team.ready_for_stage = None
                team.save(update_fields=['ready_for_stage', 'updated_at'])

    return submission
