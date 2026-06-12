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
                'vault_note': d.vault_note,
                'vault_file_template': d.vault_file_template,
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
            'vault_note': d.vault_note,
            'vault_file_template': d.vault_file_template,
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


def active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


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
        return team.current_defense_stage or team.ready_for_stage or default_stage_label()
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
        configs = list(PitEventGradingConfig.objects.filter(semester=team.semester).order_by('event_name'))
        if configs:
            completed_events = set(
                DefenseSchedule.objects.filter(
                    team=team,
                    scope=DefenseSchedule.SCOPE_PIT,
                    status=DefenseSchedule.STATUS_DONE,
                ).values_list('event_name', flat=True)
            )
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
        
        # PIT Instructors
        from user_management.models import PitInstructorAssignment
        from student_teams.team_levels import normalize_year_level
        assignments = PitInstructorAssignment.objects.filter(faculty=user, is_active=True)
        if assignments.exists():
            for assign in assignments:
                norm_year = normalize_year_level(assign.year_level)
                q |= Q(
                    semester=assign.semester,
                    section=assign.section,
                    level__icontains=norm_year
                ) & Q(level__icontains='PIT')

        if getattr(user, 'is_adviser', False) or getattr(user, 'is_pit_lead', False) or assignments.exists():
            return queryset.filter(q)
        return queryset.none()
    if getattr(user, 'role', None) == 'student':
        return queryset.filter(memberships__student=user).distinct()
    return queryset.none()


def filter_teams(request, queryset):
    search = request.query_params.get('search', '').strip()
    status_filter = request.query_params.get('status', '').strip()

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

    if status_filter == 'ready':
        queryset = queryset.exclude(ready_for_stage__isnull=True).exclude(ready_for_stage='')
    elif status_filter == 'missing':
        ready_ids = [
            team.id
            for team in queryset
            if required_complete(team, current_stage_for_team(team))
        ]
        queryset = queryset.exclude(pk__in=ready_ids)

    return queryset


def vault_unlocked(team, stage_label):
    if team.status == StudentTeam.STATUS_APPROVED:
        return True
    return DefenseSchedule.objects.filter(
        team=team,
        status=DefenseSchedule.STATUS_DONE,
    ).filter(Q(defense_stage__label=stage_label) | Q(event_name=stage_label)).exists()


def submissions_for(team, stage_label):
    return {
        submission.deliverable_id: submission
        for submission in team.deliverable_submissions.all()
        if submission.stage_label == stage_label
    }


def stage_deliverables_configured(team, stage_label):
    return bool(get_deliverable_definitions_for_team(team, stage_label))


def required_complete(team, stage_label):
    submitted = submissions_for(team, stage_label)
    return all(
        item['id'] in submitted and submitted[item['id']].status == DeliverableSubmission.STATUS_ACCEPTED
        for item in get_deliverable_definitions_for_team(team, stage_label)
        if item['type'] == DeliverableSubmission.TYPE_PRE and item['required']
    )


def stage_payload(team, stage_label):
    submitted = submissions_for(team, stage_label)
    definitions = get_deliverable_definitions_for_team(team, stage_label)
    unlocked = vault_unlocked(team, stage_label)
    rows = []

    from repository.audit.services import resolve_vault_file_template
    from academic_period_management.models import Semester
    semester_label = team.semester.label if team.semester_id else Semester.FIRST

    for item in definitions:
        submission = submitted.get(item['id'])
        is_vault = item['type'] == DeliverableSubmission.TYPE_VAULT
        
        suggested = ''
        if is_vault:
            suggested = resolve_vault_file_template(
                item.get('vault_file_template', ''),
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
            'vault_note': item.get('vault_note', ''),
            'suggested_file_name': suggested,
            'uploaded': submission is not None,
            'locked': is_vault and not unlocked,
            'submission': submission_payload(submission) if submission else None,
        })

    pre_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_PRE]
    vault_items = [item for item in rows if item['type'] == DeliverableSubmission.TYPE_VAULT]
    required_items = [item for item in pre_items if item['required']]
    vault_required_items = [item for item in vault_items if item['required']]

    configured = len(definitions) > 0
    vault_required_complete = (
        not vault_required_items
        or all(item['uploaded'] for item in vault_required_items)
    )
    return {
        'stage_label': stage_label,
        'deliverables_configured': configured,
        'endorsed': was_stage_endorsed(team, defense_stage_for_label(stage_label)) if team.is_capstone else (team.ready_for_stage == stage_label),
        'vault_unlocked': unlocked,
        'required_complete': configured and required_complete(team, stage_label),
        'pre_uploaded': sum(1 for item in pre_items if item['uploaded']),
        'pre_total': len(pre_items),
        'required_uploaded': sum(1 for item in required_items if item['uploaded']),
        'required_total': len(required_items),
        'vault_uploaded': sum(1 for item in vault_items if item['uploaded']),
        'vault_total': len(vault_items),
        'vault_required_uploaded': sum(1 for item in vault_required_items if item['uploaded']),
        'vault_required_total': len(vault_required_items),
        'vault_complete': unlocked and vault_required_complete,
        'deliverables': rows,
    }


def submission_payload(submission):
    if submission is None:
        return None
    return {
        'id': submission.id,
        'deliverable_id': submission.deliverable_id,
        'file_name': submission.file_name,
        'file_size': submission.file_size,
        'file_url': submission.file_url,
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
        configured_stage_labels = list(
            PitEventGradingConfig.objects.filter(semester=team.semester)
            .order_by('event_name')
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
    return {
        'id': team.id,
        'name': team.name,
        'project_title': team.project_title,
        'level': team.level,
        'year_level': team.year_level,
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
    }


def counts_payload(teams):
    team_list = list(teams)
    submitted_total = sum(team.deliverable_submissions.count() for team in team_list)
    ready_count = sum(1 for team in team_list if team.ready_for_stage)
    missing_count = sum(
        1
        for team in team_list
        if not required_complete(team, current_stage_for_team(team))
    )
    vault_total = DeliverableSubmission.objects.filter(
        team__in=team_list,
        deliverable_type=DeliverableSubmission.TYPE_VAULT,
    ).count() if team_list else 0
    return {
        'teams': len(team_list),
        'ready': ready_count,
        'missing_requirements': missing_count,
        'submitted_files': submitted_total,
        'vault_files': vault_total,
    }


@transaction.atomic
def upsert_submission(team, stage_label, deliverable_id, file_name, file_size, user, file=None):
    deliverable_id = (deliverable_id or '').strip()
    if not team.is_capstone and not team.is_pit:
        raise PermissionError('Only Capstone or PIT teams can submit deliverables.')
    definition = definition_for(team, stage_label, deliverable_id)
    if definition is None:
        raise ValueError('Deliverable does not exist for this stage.')
    if definition['type'] == DeliverableSubmission.TYPE_VAULT:
        if not vault_unlocked(team, stage_label):
            raise PermissionError('Vault submissions are locked until this defense is done.')
        
        # Check naming convention
        from repository.audit.services import resolve_vault_file_template
        from academic_period_management.models import Semester
        semester_label = team.semester.label if team.semester_id else Semester.FIRST
        suggested = resolve_vault_file_template(
            definition.get('vault_file_template', ''),
            team,
            stage_label,
            semester_label,
            deliverable_label=definition['label'],
        )
        if suggested and file_name.strip().lower() != suggested.strip().lower():
            raise ValidationError({'file_name': f"Filename must match the naming convention exactly. Expected: '{suggested}'"})


    defaults = {
        'label': definition['label'],
        'deliverable_type': definition['type'],
        'required': definition['required'],
        'file_name': file_name.strip(),
        'file_size': (file_size or '').strip(),
        'uploaded_by': user,
        'status': DeliverableSubmission.STATUS_PENDING,
        'feedback': '',
    }
    
    if file is not None:
        from django.core.files.base import ContentFile

        uploaded_name = getattr(file, 'name', None) or file_name
        defaults['file'] = ContentFile(file.read(), name=uploaded_name)

    submission, _ = DeliverableSubmission.objects.update_or_create(
        team=team,
        stage_label=stage_label,
        deliverable_id=deliverable_id,
        defaults=defaults,
    )
    return submission


@transaction.atomic
def remove_submission(team, stage_label, deliverable_id):
    deleted, _ = DeliverableSubmission.objects.filter(
        team=team,
        stage_label=stage_label,
        deliverable_id=deliverable_id,
    ).delete()
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
