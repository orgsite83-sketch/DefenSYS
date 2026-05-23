import csv
import io
import re
from datetime import datetime
from decimal import Decimal

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.db.models import Q

from academic_period_management.models import Semester, SchoolYear
from defense.scheduler.models import PitEventGradingConfig
from defense.stages.models import StageGradingConfig
from grading.grades.models import TeamGrade
from repository.deliverables.models import DeliverableSubmission
from repository.entry_payloads import apply_list_entry_options
from repository.vault.ml_search import filter_and_rank_entries
from repository.vault.models import PIT_SEMESTER_LABELS, PIT_YEAR_PREFIX_LABELS, VaultEntry
from student_teams.models import StudentTeam
from student_teams.term_scope import get_active_semester
from .constants import (
    DEFAULT_AUDIT_PAGE_LIMIT,
    MAX_AUDIT_PAGE_LIMIT,
    STATUS_OPTIONS,
    SUBMISSION_KIND_OPTIONS,
    TYPE_OPTIONS,
)
from .grouping import (
    augment_deliverable_missing_rows,
    deliverable_summary_payload,
    grouped_by_stage_for_team,
    options_payload,
    resolve_team_view_error,
    team_counts_payload,
    track_from_entry_type,
)
from .payloads import (
    capstone_entry_payload,
    capstone_vault_entry_payload,
    pit_entry_payload,
)
from .models import RepositoryAuditLog
from .trail import audit_trail, log_action

User = get_user_model()


PIT_PREFIX_BY_YEAR = {
    '1st Year': '1stYear',
    '2nd Year': '2ndYear',
    '3rd Year': '3rdYear',
}

PIT_FILENAME_RE = re.compile(
    r'^(?P<prefix>1stYear|2ndYear|3rdYear)\.(?P<course>[A-Za-z0-9]+)\.'
    r'(?P<project>[A-Za-z0-9_-]+)\.(?P<semester>1stSemester|2ndSemester|Summer)\.pdf$',
    re.IGNORECASE,
)

CAPSTONE_DEFAULT_COURSE = 'CAP301'
CAPSTONE_YEAR_PREFIX = '3rdYear'
CAPSTONE_YEAR_LEVEL = '3rd Year'

CAPSTONE_FILENAME_RE = re.compile(
    r'^(?P<prefix>3rdYear)\.(?P<course>[A-Za-z0-9]+)\.'
    r'(?P<project>[A-Za-z0-9_-]+)\.(?P<semester>1stSemester|2ndSemester|Summer)\.pdf$',
    re.IGNORECASE,
)

PIT_YEAR_EVENT_HINTS = {
    '1st Year': ('1st', 'first'),
    '2nd Year': ('2nd', 'second'),
    '3rd Year': ('3rd', 'third'),
}

def is_admin(user):
    return getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False)


def _has_assigned_repo_assistant(year_level):
    if not year_level:
        return False
    return User.objects.filter(
        is_repo_assistant=True,
        repo_assistant_year=year_level,
        is_active=True,
    ).exists()


def pit_event_matches_year_level(event_name, year_level):
    if not year_level:
        return True
    name = (event_name or '').lower()
    hints = PIT_YEAR_EVENT_HINTS.get(year_level, ())
    if not hints:
        return True
    return any(hint in name for hint in hints)


def completed_pit_events(semester=None, year_level=None):
    semester = semester or get_active_semester()
    queryset = PitEventGradingConfig.objects.filter(is_officially_complete=True)
    if semester:
        queryset = queryset.filter(semester=semester)
    if year_level:
        event_filter = Q()
        for hint in PIT_YEAR_EVENT_HINTS.get(year_level, ()):
            event_filter |= Q(event_name__icontains=hint)
        if event_filter:
            queryset = queryset.filter(event_filter)
        else:
            queryset = queryset.none()
    return queryset


def all_completed_pit_event_names(semester=None):
    semester = semester or get_active_semester()
    if not semester:
        return []
    return list(
        PitEventGradingConfig.objects.filter(
            semester=semester,
            is_officially_complete=True,
        ).values_list('event_name', flat=True)
    )


def pit_archive_queue_statuses():
    return [TeamGrade.STATUS_READY_FOR_ARCHIVE, TeamGrade.STATUS_PUBLISHED]


def pit_upload_window_open(year_level, semester=None):
    if not year_level:
        return False
    queue = pit_vault_upload_queue(year_level, semester=semester)
    if queue:
        return True
    semester = semester or get_active_semester()
    event_names = all_completed_pit_event_names(semester=semester)
    if not event_names:
        return False
    return TeamGrade.objects.filter(
        scope=TeamGrade.SCOPE_PIT,
        status=TeamGrade.STATUS_READY_FOR_ARCHIVE,
        stage_label__in=event_names,
        team__year_level=year_level,
        final_grade__gte=Decimal('75.00'),
    ).exists()


def _project_slug(value):
    cleaned = re.sub(r'[^A-Za-z0-9_-]', '', (value or '').replace(' ', ''))
    return cleaned or 'ProjectTitle'


def _default_course_for_year(year_level):
    return {
        '1st Year': 'PIT101',
        '2nd Year': 'PIT201',
        '3rd Year': 'PIT301',
    }.get(year_level, 'PIT301')


def suggested_pit_file_name(team, year_level, semester_label='1st Semester'):
    prefix = PIT_PREFIX_BY_YEAR.get(year_level, '3rdYear')
    course = _default_course_for_year(year_level)
    project = _project_slug(team.project_title if team else 'ProjectTitle')
    semester_key = '1stSemester'
    for key, label in PIT_SEMESTER_LABELS.items():
        if label == semester_label:
            semester_key = key
            break
    return f'{prefix}.{course}.{project}.{semester_key}.pdf'


def pit_vault_upload_queue(year_level, semester=None):
    if not year_level:
        return []

    semester = semester or get_active_semester()
    event_names = all_completed_pit_event_names(semester=semester)
    if not event_names:
        return []

    uploaded_team_ids = set(
        VaultEntry.objects.filter(
            entry_type=VaultEntry.TYPE_PIT,
            year_level=year_level,
            team_id__isnull=False,
        ).values_list('team_id', flat=True)
    )

    grades = (
        TeamGrade.objects.filter(
            scope=TeamGrade.SCOPE_PIT,
            status__in=pit_archive_queue_statuses(),
            stage_label__in=event_names,
            team__year_level=year_level,
            team__status=StudentTeam.STATUS_APPROVED,
            final_grade__gte=Decimal('75.00'),
        )
        .select_related('team', 'team__semester')
        .order_by('stage_label', 'team__name')
    )

    queue = []
    seen_team_event = set()
    for grade in grades:
        team = grade.team
        if team.id in uploaded_team_ids:
            continue
        if grade.status != TeamGrade.STATUS_READY_FOR_ARCHIVE:
            continue
        key = (team.id, grade.stage_label)
        if key in seen_team_event:
            continue
        seen_team_event.add(key)
        if team.semester:
            semester_label = team.semester.label
        else:
            semester_label = Semester.FIRST
        queue.append({
            'team_id': team.id,
            'team_name': team.name,
            'project_title': team.project_title or team.name,
            'event_name': grade.stage_label,
            'suggested_file_name': suggested_pit_file_name(team, year_level, semester_label),
            'vault_status': 'uploaded' if team.id in uploaded_team_ids else 'pending',
        })
    return queue


def pit_upload_diagnostics(year_level, semester=None):
    semester = semester or get_active_semester()
    if not year_level or not semester:
        return {}

    all_completed = all_completed_pit_event_names(semester=semester)
    pit_grades = TeamGrade.objects.filter(
        semester=semester,
        scope=TeamGrade.SCOPE_PIT,
        team__year_level=year_level,
    )
    completed_for_year = sorted(
        {
            label
            for label in pit_grades.filter(
                stage_label__in=all_completed,
                status__in=pit_archive_queue_statuses(),
            ).values_list('stage_label', flat=True)
            if label
        }
    )
    stage_labels = sorted(
        {
            label
            for label in pit_grades.values_list('stage_label', flat=True)
            if label
        }
    )
    ready_for_archive = pit_grades.filter(
        status=TeamGrade.STATUS_READY_FOR_ARCHIVE,
    ).count()
    unpublished_passed = pit_grades.filter(
        final_grade__gte=Decimal('75.00'),
    ).exclude(
        status__in=[TeamGrade.STATUS_READY_FOR_ARCHIVE, TeamGrade.STATUS_PUBLISHED],
    ).count()

    return {
        'completed_events_for_year': completed_for_year,
        'completed_events_other_years': [
            name for name in all_completed if name not in completed_for_year
        ],
        'pit_stage_labels': stage_labels,
        'ready_for_archive_count': ready_for_archive,
        'unpublished_passed_count': unpublished_passed,
    }


def upload_window_payload(year_level, semester=None):
    open_window = pit_upload_window_open(year_level, semester=semester)
    completed = all_completed_pit_event_names(semester=semester)
    queue = pit_vault_upload_queue(year_level, semester=semester) if open_window else []
    diagnostics = {}
    if year_level and (not open_window or not queue):
        diagnostics = pit_upload_diagnostics(year_level, semester=semester)
    return {
        'open': open_window,
        'completed_events': completed,
        'queue': queue,
        'has_assigned_assistant': _has_assigned_repo_assistant(year_level),
        'diagnostics': diagnostics,
    }


def all_completed_capstone_stage_labels(semester=None):
    semester = semester or get_active_semester()
    if not semester:
        return []
    return list(
        StageGradingConfig.objects.filter(
            semester=semester,
            is_officially_complete=True,
        ).values_list('defense_stage__label', flat=True)
    )


def capstone_archive_queue_statuses():
    return pit_archive_queue_statuses()


def suggested_capstone_file_name(team, stage_label, semester_label='1st Semester'):
    project = _project_slug(team.project_title if team else 'ProjectTitle')
    semester_key = '1stSemester'
    for key, label in PIT_SEMESTER_LABELS.items():
        if label == semester_label:
            semester_key = key
            break
    return f'{CAPSTONE_YEAR_PREFIX}.{CAPSTONE_DEFAULT_COURSE}.{project}.{semester_key}.pdf'


def capstone_vault_upload_queue(semester=None):
    semester = semester or get_active_semester()
    stage_labels = all_completed_capstone_stage_labels(semester=semester)
    if not stage_labels:
        return []

    uploaded_keys = set(
        VaultEntry.objects.filter(
            entry_type=VaultEntry.TYPE_CAPSTONE,
            team_id__isnull=False,
        ).values_list('team_id', 'stage_label')
    )

    grades = (
        TeamGrade.objects.filter(
            scope=TeamGrade.SCOPE_CAPSTONE,
            status=TeamGrade.STATUS_READY_FOR_ARCHIVE,
            stage_label__in=stage_labels,
            team__status=StudentTeam.STATUS_APPROVED,
            final_grade__gte=Decimal('75.00'),
        )
        .select_related('team', 'team__semester')
        .order_by('stage_label', 'team__name')
    )
    if semester:
        grades = grades.filter(semester=semester)

    queue = []
    seen = set()
    for grade in grades:
        team = grade.team
        key = (team.id, grade.stage_label)
        if key in uploaded_keys or key in seen:
            continue
        seen.add(key)
        semester_label = team.semester.label if team.semester_id else Semester.FIRST
        queue.append({
            'team_id': team.id,
            'team_name': team.name,
            'project_title': team.project_title or team.name,
            'stage_label': grade.stage_label,
            'suggested_file_name': suggested_capstone_file_name(
                team,
                grade.stage_label,
                semester_label,
            ),
            'vault_status': 'pending',
        })
    return queue


def capstone_upload_diagnostics(semester=None):
    semester = semester or get_active_semester()
    if not semester:
        return {}

    completed_stages = all_completed_capstone_stage_labels(semester=semester)
    capstone_grades = TeamGrade.objects.filter(
        semester=semester,
        scope=TeamGrade.SCOPE_CAPSTONE,
    )
    ready_for_archive = capstone_grades.filter(
        status=TeamGrade.STATUS_READY_FOR_ARCHIVE,
    ).count()
    unpublished_passed = capstone_grades.filter(
        final_grade__gte=Decimal('75.00'),
    ).exclude(
        status__in=capstone_archive_queue_statuses(),
    ).count()

    return {
        'completed_stages': completed_stages,
        'capstone_stage_labels': sorted(
            {
                label
                for label in capstone_grades.values_list('stage_label', flat=True)
                if label
            }
        ),
        'ready_for_archive_count': ready_for_archive,
        'unpublished_passed_count': unpublished_passed,
    }


def capstone_upload_window_open(semester=None):
    semester = semester or get_active_semester()
    queue = capstone_vault_upload_queue(semester=semester)
    if queue:
        return True
    if not all_completed_capstone_stage_labels(semester=semester):
        return False
    return TeamGrade.objects.filter(
        scope=TeamGrade.SCOPE_CAPSTONE,
        status=TeamGrade.STATUS_READY_FOR_ARCHIVE,
        semester=semester,
        final_grade__gte=Decimal('75.00'),
    ).exists()


def capstone_upload_window_payload(semester=None):
    semester = semester or get_active_semester()
    open_window = capstone_upload_window_open(semester=semester)
    completed = all_completed_capstone_stage_labels(semester=semester)
    queue = capstone_vault_upload_queue(semester=semester) if open_window else []
    diagnostics = {}
    if not open_window or not queue:
        diagnostics = capstone_upload_diagnostics(semester=semester)
    return {
        'open': open_window,
        'completed_stages': completed,
        'queue': queue,
        'diagnostics': diagnostics,
    }


def validate_capstone_file_name(file_name):
    match = CAPSTONE_FILENAME_RE.fullmatch((file_name or '').strip())
    if not match:
        raise ValidationError(
            'Use format: 3rdYear.CAP301.ProjectTitle.1stSemester.pdf'
        )
    prefix = match.group('prefix')
    semester = match.group('semester')
    return {
        'prefix': prefix,
        'year_level': PIT_YEAR_PREFIX_LABELS.get(prefix, CAPSTONE_YEAR_LEVEL),
        'course_code': match.group('course').upper(),
        'project_slug': match.group('project'),
        'semester_label': PIT_SEMESTER_LABELS[semester],
    }


def repository_scope(user):
    if is_admin(user):
        capstone_open = capstone_upload_window_open()
        return {
            'scope': 'admin',
            'label': 'Admin repository audit',
            'pit_year_level': '',
            'can_upload_pit': False,
            'can_upload_capstone': capstone_open,
            'can_override': True,
            'can_export': True,
            'has_assigned_assistant': False,
        }
    if getattr(user, 'role', None) == 'faculty' and getattr(user, 'is_pit_lead', False):
        pit_year = user.pit_lead_year or ''
        assistant_assigned = _has_assigned_repo_assistant(pit_year)
        window_open = pit_upload_window_open(pit_year)
        can_upload = bool(pit_year) and window_open and not assistant_assigned
        return {
            'scope': 'pit_lead',
            'label': 'PIT lead repository audit',
            'pit_year_level': pit_year,
            'can_upload_pit': can_upload,
            'can_upload_capstone': False,
            'can_override': False,
            'can_export': True,
            'has_assigned_assistant': assistant_assigned,
        }
    if getattr(user, 'role', None) == 'faculty' and getattr(user, 'is_repo_assistant', False):
        pit_year = getattr(user, 'repo_assistant_year', '') or ''
        window_open = pit_upload_window_open(pit_year)
        return {
            'scope': 'repo_assistant',
            'label': 'Repository assistant PIT uploads',
            'pit_year_level': pit_year,
            'can_upload_pit': bool(pit_year) and window_open,
            'can_upload_capstone': False,
            'can_override': False,
            'can_export': True,
            'has_assigned_assistant': False,
        }
    raise PermissionDenied('Repository audit is available to admins, PIT leads, and repository assistants.')


def active_academic_year_label():
    semester = Semester.objects.select_related('school_year').filter(is_active=True).first()
    if semester:
        return semester.school_year.label
    now = datetime.now()
    return f'{now.year}-{now.year + 1}'


def normalize(value):
    return re.sub(r'[^a-z0-9]', '', (value or '').lower())


def validate_pit_file_name(file_name):
    match = PIT_FILENAME_RE.fullmatch((file_name or '').strip())
    if not match:
        raise ValidationError(
            'Use format: 3rdYear.PIT301.ProjectTitle.1stSemester.pdf'
        )
    prefix = match.group('prefix')
    semester = match.group('semester')
    return {
        'prefix': prefix,
        'year_level': PIT_YEAR_PREFIX_LABELS[prefix],
        'course_code': match.group('course').upper(),
        'project_slug': match.group('project'),
        'semester_label': PIT_SEMESTER_LABELS[semester],
    }


def pit_queryset_for_scope(scope):
    queryset = VaultEntry.objects.select_related('team', 'uploaded_by').filter(
        entry_type=VaultEntry.TYPE_PIT,
    )
    if scope['scope'] in ('pit_lead', 'repo_assistant') and scope.get('pit_year_level'):
        queryset = queryset.filter(year_level=scope['pit_year_level'])
    return queryset


def capstone_vault_queryset_for_scope(scope):
    if scope['scope'] != 'admin':
        return VaultEntry.objects.none()
    return (
        VaultEntry.objects.select_related('team', 'uploaded_by')
        .filter(entry_type=VaultEntry.TYPE_CAPSTONE)
        .filter(Q(team__isnull=True) | Q(team__level__icontains='Capstone'))
    )


def capstone_deliverable_queryset_for_scope(scope):
    if scope['scope'] != 'admin':
        return DeliverableSubmission.objects.none()
    return (
        DeliverableSubmission.objects.select_related(
            'team',
            'team__semester',
            'team__semester__school_year',
            'uploaded_by',
        )
        .filter(team__level__icontains='Capstone')
        .order_by('-uploaded_at', 'file_name')
    )


def _query_flag(value):
    return str(value or '').strip().lower() in ('1', 'true', 'yes')


def scoped_entries(user, request=None, *, include_ml=False, include_audit_trail=False):
    scope = repository_scope(user)
    payload_kwargs = {
        'request': request,
        'include_ml': include_ml,
        'include_audit_trail': include_audit_trail,
    }
    entries = [
        pit_entry_payload(entry, **payload_kwargs)
        for entry in pit_queryset_for_scope(scope)
    ]
    entries.extend(
        capstone_vault_entry_payload(entry, **payload_kwargs)
        for entry in capstone_vault_queryset_for_scope(scope)
    )
    entries.extend(
        capstone_entry_payload(submission, **payload_kwargs)
        for submission in capstone_deliverable_queryset_for_scope(scope)
    )
    return sorted(entries, key=lambda item: item.get('uploaded_at'), reverse=True), scope


def filter_entries(entries, query_params):
    filtered, _suggestions = filter_and_rank_entries(entries, query_params)
    return filtered


def counts_payload(entries, filtered_entries):
    return {
        'total': len(filtered_entries),
        'filtered': len(filtered_entries),
        'pit': sum(1 for entry in filtered_entries if entry.get('submission_kind') == 'pit'),
        'capstone': sum(
            1
            for entry in filtered_entries
            if entry.get('type') == VaultEntry.TYPE_CAPSTONE
            and entry.get('submission_kind') != 'pit'
        ),
        'approved': sum(
            1
            for entry in filtered_entries
            if entry['status'] in [VaultEntry.STATUS_APPROVED, 'Vault Submission']
        ),
        'needs_revision': sum(
            1 for entry in filtered_entries if entry['status'] == VaultEntry.STATUS_NEEDS_REVISION
        ),
        'pre_defense': sum(1 for entry in filtered_entries if entry.get('submission_kind') == 'pre'),
        'vault_submissions': sum(
            1 for entry in filtered_entries if entry.get('submission_kind') == 'vault'
        ),
        'archive_pdf': sum(1 for entry in filtered_entries if entry.get('submission_kind') == 'archive'),
        'missing_required': sum(1 for entry in filtered_entries if entry.get('is_missing')),
        'uploaded': sum(
            1
            for entry in filtered_entries
            if entry.get('has_file') and not entry.get('is_missing')
        ),
    }


def _parse_pagination(request):
    try:
        limit = int(request.query_params.get('limit', DEFAULT_AUDIT_PAGE_LIMIT))
    except (TypeError, ValueError):
        limit = DEFAULT_AUDIT_PAGE_LIMIT
    try:
        offset = int(request.query_params.get('offset', 0))
    except (TypeError, ValueError):
        offset = 0
    limit = max(1, min(limit, MAX_AUDIT_PAGE_LIMIT))
    offset = max(0, offset)
    return limit, offset


def repository_audit_payload(request):
    include_ml = _query_flag(request.query_params.get('include_ml'))
    include_audit_trail = _query_flag(request.query_params.get('include_audit_trail'))
    entries, scope = scoped_entries(
        request.user,
        request=request,
        include_ml=True,
        include_audit_trail=include_audit_trail,
    )
    deliverable_id = (request.query_params.get('deliverable_id') or '').strip()
    stage_filter = (request.query_params.get('stage') or '').strip()
    view_mode = (request.query_params.get('view') or '').strip()
    team_id = (request.query_params.get('team_id') or '').strip()

    if deliverable_id and scope.get('scope') == 'admin':
        entries = augment_deliverable_missing_rows(entries, deliverable_id, stage_filter)

    filtered, suggestions = filter_and_rank_entries(entries, request.query_params)
    for entry in filtered:
        if entry['type'] == VaultEntry.TYPE_PIT:
            entry['can_override'] = scope['can_override']
        apply_list_entry_options(
            entry,
            include_ml=include_ml,
            include_audit_trail=include_audit_trail,
        )

    track = track_from_entry_type(request.query_params.get('type', ''))
    grouped_by_stage = []
    deliverable_summary = {}
    team_view_error = ''
    if view_mode == 'team' and team_id:
        try:
            team = (
                StudentTeam.objects.select_related(
                    'semester',
                    'semester__school_year',
                )
                .prefetch_related('deliverable_submissions')
                .get(pk=int(team_id))
            )
            team_view_error = resolve_team_view_error(team, track)
            if not team_view_error and team.is_capstone and track in ('capstone', 'all', ''):
                grouped_by_stage = grouped_by_stage_for_team(
                    team,
                    filtered,
                    stage_filter=stage_filter,
                    request=request,
                    include_ml=include_ml,
                    include_audit_trail=include_audit_trail,
                )
        except (StudentTeam.DoesNotExist, ValueError):
            team_view_error = 'Team not found.'
    if deliverable_id:
        deliverable_summary = deliverable_summary_payload(
            deliverable_id,
            filtered,
            stage_filter=stage_filter,
        )

    limit, offset = _parse_pagination(request)
    total_filtered = len(filtered)
    page_entries = filtered[offset:offset + limit]

    year_for_window = scope.get('pit_year_level') or ''
    upload_window = upload_window_payload(year_for_window) if year_for_window else {
        'open': False,
        'completed_events': [],
        'queue': [],
        'has_assigned_assistant': scope.get('has_assigned_assistant', False),
    }
    return {
        'entries': page_entries,
        'suggestions': suggestions,
        'counts': counts_payload(entries, filtered),
        'pagination': {
            'total': total_filtered,
            'limit': limit,
            'offset': offset,
            'has_more': offset + limit < total_filtered,
        },
        'options': options_payload(filtered, track=track),
        'scope': scope,
        'upload_window': upload_window,
        'capstone_upload_window': capstone_upload_window_payload(),
        'grouped_by_stage': grouped_by_stage,
        'deliverable_summary': deliverable_summary,
        'team_view_error': team_view_error,
        'filters': {
            'search': request.query_params.get('search', ''),
            'type': request.query_params.get('type', ''),
            'year_level': request.query_params.get('year_level', ''),
            'academic_year': request.query_params.get('academic_year', ''),
            'status': request.query_params.get('status', ''),
            'semester': request.query_params.get('semester', ''),
            'team_id': team_id,
            'stage': stage_filter,
            'deliverable_id': deliverable_id,
            'submission_kind': request.query_params.get('submission_kind', ''),
            'view': view_mode,
        },
    }


def resolve_pit_entry(user, entry_id):
    scope = repository_scope(user)
    if not scope['can_override']:
        raise PermissionDenied('You do not have permission to modify this PIT entry.')
    source_id = str(entry_id).replace('pit-', '')
    if not source_id.isdigit():
        raise ValidationError('Invalid PIT entry id.')
    entry = pit_queryset_for_scope(scope).filter(pk=int(source_id)).first()
    if entry is None:
        raise PermissionDenied('PIT entry is outside your repository audit scope.')
    return entry, scope


def mark_pit_grade_published_after_vault(team, *, semester=None, user=None):
    from django.utils import timezone

    if not team:
        return None
    if semester is None:
        semester = team.semester if getattr(team, 'semester_id', None) else get_active_semester()
    grades = TeamGrade.objects.filter(
        team=team,
        scope=TeamGrade.SCOPE_PIT,
        status=TeamGrade.STATUS_READY_FOR_ARCHIVE,
    )
    if semester:
        grades = grades.filter(semester=semester)
    grade = grades.order_by('-updated_at').first()
    if grade is None:
        return None
    grade.status = TeamGrade.STATUS_PUBLISHED
    if user is not None:
        grade.published_by = user
    grade.published_at = timezone.now()
    grade.save(update_fields=['status', 'published_by', 'published_at', 'updated_at'])
    return grade


def eligible_pit_team_ids(year_level, semester=None):
    return {
        item['team_id']
        for item in pit_vault_upload_queue(year_level, semester=semester)
    }


def eligible_pit_teams(year_level, semester=None):
    team_ids = eligible_pit_team_ids(year_level, semester=semester)
    if not team_ids:
        return StudentTeam.objects.none()
    return StudentTeam.objects.filter(pk__in=team_ids).select_related(
        'semester',
        'semester__school_year',
    )


def match_pit_team(file_name, year_level, semester=None):
    metadata = validate_pit_file_name(file_name)
    file_key = normalize(file_name)
    for team in eligible_pit_teams(year_level, semester=semester):
        project_key = normalize(team.project_title or team.name)
        team_key = normalize(team.name).replace('team', '')
        if project_key and project_key[:10] in file_key:
            return team
        if team_key and team_key in file_key:
            return team
    return None


def _no_eligible_teams_skip_reason(file_name, active_semester, selected_year=None):
    year_level = selected_year or ''
    event_names = all_completed_pit_event_names(semester=active_semester)
    event_hint = ', '.join(event_names) if event_names else 'none'
    diagnostics = pit_upload_diagnostics(year_level, active_semester) if year_level else {}
    other_events = diagnostics.get('completed_events_other_years') or []
    stage_labels = diagnostics.get('pit_stage_labels') or []
    unpublished_passed = diagnostics.get('unpublished_passed_count', 0)

    ready_count = diagnostics.get('ready_for_archive_count', 0)
    parts = [
        'No passed teams are ready to archive for your year level.',
        f'Officially complete events this semester: {event_hint}.',
    ]
    if stage_labels:
        parts.append(f'Team grade event names in use: {", ".join(stage_labels)}.')
    if ready_count:
        parts.append(f'{ready_count} team(s) are ready for archive but did not match this upload.')
    if unpublished_passed:
        parts.append(
            f'{unpublished_passed} team(s) have passing scores but are not ready for archive yet. '
            'Mark the matching PIT event officially complete in Grade Center.'
        )
    else:
        parts.append(
            'Ensure TeamGrade stage_label matches the completed event name exactly.'
        )
    return {'file_name': file_name, 'reason': ' '.join(parts)}


def _pit_team_match_skip_reason(file_name, selected_year, active_semester):
    queue = pit_vault_upload_queue(selected_year, semester=active_semester)
    pending = [item for item in queue if item['vault_status'] == 'pending']
    if pending:
        example = pending[0]['suggested_file_name']
        return {
            'file_name': file_name,
            'reason': (
                f'No eligible team matched "{file_name}". '
                f'Rename the PDF to the exact queue filename, e.g. {example}.'
            ),
        }
    return {
        'file_name': file_name,
        'reason': (
            'No eligible team matched this filename. '
            'Use format: 3rdYear.PIT301.ProjectTitle.1stSemester.pdf with the project slug from the team title.'
        ),
    }


def _save_pit_vault_entry(user, *, file_name, file_obj, selected_year, academic_year, active_semester, eligible_ids):
    if not eligible_ids:
        return None, _no_eligible_teams_skip_reason(
            file_name,
            active_semester,
            selected_year=selected_year,
        )

    try:
        metadata = validate_pit_file_name(file_name)
        if metadata['year_level'] != selected_year:
            raise ValidationError(f'{file_name} does not match {selected_year}.')
    except ValidationError as exc:
        return None, {'file_name': file_name, 'reason': '; '.join(exc.messages)}

    team = match_pit_team(file_name, selected_year, semester=active_semester)
    if team is None or team.id not in eligible_ids:
        return None, _pit_team_match_skip_reason(file_name, selected_year, active_semester)

    entry, made = VaultEntry.objects.update_or_create(
        entry_type=VaultEntry.TYPE_PIT,
        file_name=file_name,
        academic_year=academic_year,
        defaults={
            'team': team,
            'team_name': team.name if team else 'Unmatched',
            'year_level': selected_year,
            'course_code': metadata['course_code'],
            'semester_label': metadata['semester_label'],
            'stage_label': metadata['course_code'],
            'status': VaultEntry.STATUS_APPROVED,
            'uploaded_by': user,
            'metadata': {
                'project_slug': metadata['project_slug'],
                'matched': bool(team),
                'project_title': team.project_title if team else metadata['project_slug'],
            },
        },
    )
    if file_obj is not None:
        if entry.file:
            entry.file.delete(save=False)
        entry.file.save(file_name, file_obj, save=False)
        entry.file_size = str(getattr(file_obj, 'size', '') or entry.file_size or '')
        entry.save()
        message = 'PIT file uploaded with document'
    else:
        message = 'PIT file uploaded' if made else 'PIT file metadata refreshed'

    log_action(
        VaultEntry.TYPE_PIT,
        entry.id,
        entry.file_name,
        RepositoryAuditLog.ACTION_UPLOAD,
        user,
        new_status=entry.status,
        message=message,
    )
    if team:
        mark_pit_grade_published_after_vault(
            team,
            semester=active_semester,
            user=user,
        )
    return entry, None


@transaction.atomic
def upload_pit_files(user, file_names=None, uploaded_files=None, year_level=None, academic_year=None):
    scope = repository_scope(user)
    if not scope['can_upload_pit']:
        raise PermissionDenied('You do not have permission to upload PIT entries.')
    selected_year = year_level or scope['pit_year_level']
    if scope['scope'] == 'pit_lead':
        selected_year = scope['pit_year_level']
    if scope['scope'] == 'repo_assistant':
        selected_year = scope['pit_year_level']
    if selected_year not in PIT_PREFIX_BY_YEAR:
        raise ValidationError('Select a PIT year level before uploading.')
    if not pit_upload_window_open(selected_year):
        raise ValidationError(
            'Repository uploads open after a PIT event is marked officially complete in Grade Center.'
        )

    academic_year = academic_year or active_academic_year_label()
    active_semester = get_active_semester()
    eligible_ids = eligible_pit_team_ids(selected_year, semester=active_semester)
    created = []
    skipped = []

    upload_items = []
    if uploaded_files:
        for uploaded in uploaded_files:
            upload_items.append((uploaded.name, uploaded))
    if file_names:
        for raw_name in file_names:
            name = (raw_name or '').strip()
            if name:
                upload_items.append((name, None))

    if not upload_items:
        raise ValidationError(
            {'files': 'Provide at least one PIT PDF file or filename.'}
        )

    for file_name, file_obj in upload_items:
        entry, skip = _save_pit_vault_entry(
            user,
            file_name=file_name,
            file_obj=file_obj,
            selected_year=selected_year,
            academic_year=academic_year,
            active_semester=active_semester,
            eligible_ids=eligible_ids,
        )
        if skip:
            skipped.append(skip)
            continue
        if entry:
            created.append(entry)

    return created, skipped


def mark_capstone_grade_published_after_vault(team, *, stage_label=None, semester=None, user=None):
    from django.utils import timezone

    if not team:
        return None
    if semester is None:
        semester = team.semester if getattr(team, 'semester_id', None) else get_active_semester()
    grades = TeamGrade.objects.filter(
        team=team,
        scope=TeamGrade.SCOPE_CAPSTONE,
        status=TeamGrade.STATUS_READY_FOR_ARCHIVE,
    )
    if semester:
        grades = grades.filter(semester=semester)
    if stage_label:
        grades = grades.filter(stage_label=stage_label)
    grade = grades.order_by('-updated_at').first()
    if grade is None:
        return None
    grade.status = TeamGrade.STATUS_PUBLISHED
    if user is not None:
        grade.published_by = user
    grade.published_at = timezone.now()
    grade.save(update_fields=['status', 'published_by', 'published_at', 'updated_at'])
    return grade


def eligible_capstone_queue_keys(semester=None):
    return {
        (item['team_id'], item['stage_label'])
        for item in capstone_vault_upload_queue(semester=semester)
    }


def match_capstone_team(file_name, semester=None):
    file_key = normalize(file_name)
    validate_capstone_file_name(file_name)
    for item in capstone_vault_upload_queue(semester=semester):
        team = StudentTeam.objects.filter(pk=item['team_id']).first()
        if team is None:
            continue
        project_key = normalize(team.project_title or team.name)
        team_key = normalize(team.name).replace('team', '')
        if project_key and project_key[:10] in file_key:
            return team, item['stage_label']
        if team_key and team_key in file_key:
            return team, item['stage_label']
    return None, None


def _capstone_team_match_skip_reason(file_name, active_semester):
    queue = capstone_vault_upload_queue(semester=active_semester)
    pending = [item for item in queue if item['vault_status'] == 'pending']
    if pending:
        example = pending[0]['suggested_file_name']
        return {
            'file_name': file_name,
            'reason': (
                f'No eligible team matched "{file_name}". '
                f'Rename the PDF to the exact queue filename, e.g. {example}.'
            ),
        }
    return {
        'file_name': file_name,
        'reason': (
            'No eligible team matched this filename. '
            'Use format: 3rdYear.CAP301.ProjectTitle.1stSemester.pdf with the project slug from the team title.'
        ),
    }


def _no_eligible_capstone_skip_reason(file_name, active_semester):
    diagnostics = capstone_upload_diagnostics(semester=active_semester)
    completed = diagnostics.get('completed_stages') or []
    stage_hint = ', '.join(completed) if completed else 'none'
    ready_count = diagnostics.get('ready_for_archive_count', 0)
    unpublished = diagnostics.get('unpublished_passed_count', 0)
    parts = [
        'No passed Capstone teams are ready to archive.',
        f'Officially complete stages this semester: {stage_hint}.',
    ]
    if ready_count:
        parts.append(f'{ready_count} team(s) are ready for archive but did not match this upload.')
    if unpublished:
        parts.append(
            f'{unpublished} team(s) have passing scores but are not ready for archive yet. '
            'Mark the Capstone stage officially complete in Grade Center.'
        )
    else:
        parts.append('Ensure TeamGrade stage_label matches the completed defense stage exactly.')
    return {'file_name': file_name, 'reason': ' '.join(parts)}


def _save_capstone_vault_entry(
    user,
    *,
    file_name,
    file_obj,
    academic_year,
    active_semester,
    eligible_keys,
):
    if not eligible_keys:
        return None, _no_eligible_capstone_skip_reason(file_name, active_semester)

    try:
        metadata = validate_capstone_file_name(file_name)
    except ValidationError as exc:
        return None, {'file_name': file_name, 'reason': '; '.join(exc.messages)}

    team, stage_label = match_capstone_team(file_name, semester=active_semester)
    if team is None or (team.id, stage_label) not in eligible_keys:
        return None, _capstone_team_match_skip_reason(file_name, active_semester)

    entry, made = VaultEntry.objects.update_or_create(
        entry_type=VaultEntry.TYPE_CAPSTONE,
        file_name=file_name,
        academic_year=academic_year,
        defaults={
            'team': team,
            'team_name': team.name if team else 'Unmatched',
            'year_level': metadata['year_level'],
            'course_code': metadata['course_code'],
            'semester_label': metadata['semester_label'],
            'stage_label': stage_label,
            'status': VaultEntry.STATUS_APPROVED,
            'uploaded_by': user,
            'metadata': {
                'project_slug': metadata['project_slug'],
                'matched': bool(team),
                'project_title': team.project_title if team else metadata['project_slug'],
            },
        },
    )
    if file_obj is not None:
        if entry.file:
            entry.file.delete(save=False)
        entry.file.save(file_name, file_obj, save=False)
        entry.file_size = str(getattr(file_obj, 'size', '') or entry.file_size or '')
        entry.save()
        message = 'Capstone file uploaded with document'
    else:
        message = 'Capstone file uploaded' if made else 'Capstone file metadata refreshed'

    log_action(
        VaultEntry.TYPE_CAPSTONE,
        entry.id,
        entry.file_name,
        RepositoryAuditLog.ACTION_UPLOAD,
        user,
        new_status=entry.status,
        message=message,
    )
    if team:
        mark_capstone_grade_published_after_vault(
            team,
            stage_label=stage_label,
            semester=active_semester,
            user=user,
        )
    return entry, None


@transaction.atomic
def upload_capstone_files(user, file_names=None, uploaded_files=None, academic_year=None):
    scope = repository_scope(user)
    if not scope.get('can_upload_capstone'):
        raise PermissionDenied('You do not have permission to upload Capstone archive PDFs.')
    if not capstone_upload_window_open():
        raise ValidationError(
            'Capstone repository uploads open after a defense stage is marked officially complete in Grade Center.'
        )

    academic_year = academic_year or active_academic_year_label()
    active_semester = get_active_semester()
    eligible_keys = eligible_capstone_queue_keys(semester=active_semester)
    created = []
    skipped = []

    upload_items = []
    if uploaded_files:
        for uploaded in uploaded_files:
            upload_items.append((uploaded.name, uploaded))
    if file_names:
        for raw_name in file_names:
            name = (raw_name or '').strip()
            if name:
                upload_items.append((name, None))

    if not upload_items:
        raise ValidationError(
            {'files': 'Provide at least one Capstone PDF file or filename.'}
        )

    for file_name, file_obj in upload_items:
        entry, skip = _save_capstone_vault_entry(
            user,
            file_name=file_name,
            file_obj=file_obj,
            academic_year=academic_year,
            active_semester=active_semester,
            eligible_keys=eligible_keys,
        )
        if skip:
            skipped.append(skip)
            continue
        if entry:
            created.append(entry)

    return created, skipped


@transaction.atomic
def override_pit_status(user, entry_id, status):
    entry, scope = resolve_pit_entry(user, entry_id)
    if not scope['can_override']:
        raise PermissionDenied('Only admins can override PIT repository status.')
    valid = {VaultEntry.STATUS_PENDING, VaultEntry.STATUS_APPROVED, VaultEntry.STATUS_NEEDS_REVISION}
    if status not in valid:
        raise ValidationError('Invalid PIT repository status.')
    previous = entry.status
    entry.status = status
    entry.save(update_fields=['status', 'updated_at'])
    log_action(
        VaultEntry.TYPE_PIT,
        entry.id,
        entry.file_name,
        RepositoryAuditLog.ACTION_OVERRIDE,
        user,
        previous_status=previous,
        new_status=status,
        message='Admin override updated PIT repository status.',
    )
    return entry


def repository_entries_count():
    return VaultEntry.objects.filter(entry_type=VaultEntry.TYPE_PIT).count() + DeliverableSubmission.objects.filter(
        team__level__icontains='Capstone',
    ).count()


def repository_pending_count():
    """Legacy dashboard hook: pending AI gate removed; report needs-revision PIT files."""
    return VaultEntry.objects.filter(
        entry_type=VaultEntry.TYPE_PIT,
        status=VaultEntry.STATUS_NEEDS_REVISION,
    ).count()


def repository_approved_count():
    return VaultEntry.objects.filter(
        entry_type=VaultEntry.TYPE_PIT,
        status=VaultEntry.STATUS_APPROVED,
    ).count() + DeliverableSubmission.objects.filter(
        team__level__icontains='Capstone',
        deliverable_type=DeliverableSubmission.TYPE_VAULT,
    ).count()


def repository_csv(entries):
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Type', 'File Name', 'Team', 'Year Level', 'Academic Year', 'Stage/Course', 'Status', 'Uploaded By', 'Uploaded At'])
    for entry in entries:
        writer.writerow([
            'Capstone' if entry['type'] == VaultEntry.TYPE_CAPSTONE else 'PIT',
            entry['file_name'],
            entry.get('team_name') or '',
            entry.get('year_level') or '',
            entry.get('academic_year') or '',
            entry.get('stage') or '',
            entry.get('status') or '',
            entry.get('uploaded_by') or '',
            entry.get('uploaded_at') or '',
        ])
    return output.getvalue()
