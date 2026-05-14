import csv
import io
import re
from datetime import datetime

from django.conf import settings
from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.db.models import Q

from academic_period_management.models import Semester, SchoolYear
from capstone_deliverables.models import DeliverableSubmission
from capstone_deliverables.services import DELIVERABLE_DEFINITIONS, STAGE_OPTIONS, display_name
from digital_vault.models import PIT_SEMESTER_LABELS, PIT_YEAR_PREFIX_LABELS, VaultEntry
from student_teams.models import StudentTeam
from .models import RepositoryAuditLog


PIT_PREFIX_BY_YEAR = {
    '1st Year': '1stYear',
    '2nd Year': '2ndYear',
    '3rd Year': '3rdYear',
}

SAMPLE_PIT_PROJECTS = {
    '1st Year': [
        {'team_name': 'Team ByteForce', 'project': 'SmartAttendanceSystem', 'course': 'PIT101'},
        {'team_name': 'Team CodeSpark', 'project': 'OnlineQuizPlatform', 'course': 'PIT101'},
        {'team_name': 'Team DataFlow', 'project': 'StudentGradeTracker', 'course': 'PIT102'},
    ],
    '2nd Year': [
        {'team_name': 'Team LogicBridge', 'project': 'PeerTutoringMatchingSystem', 'course': 'PIT201'},
        {'team_name': 'Team MindMap', 'project': 'CollaborativeNoteApp', 'course': 'PIT201'},
        {'team_name': 'Team NodeLink', 'project': 'CampusSocialNetwork', 'course': 'PIT202'},
    ],
    '3rd Year': [
        {'team_name': 'Team VaultSync', 'project': 'CloudFileSyncSystem', 'course': 'PIT301'},
        {'team_name': 'Team WebCraft', 'project': 'LowCodeWebsiteBuilder', 'course': 'PIT301'},
        {'team_name': 'Team XcelTrack', 'project': 'AcademicPerformanceDashboard', 'course': 'PIT302'},
    ],
}

PIT_FILENAME_RE = re.compile(
    r'^(?P<prefix>1stYear|2ndYear|3rdYear)\.(?P<course>[A-Za-z0-9]+)\.'
    r'(?P<project>[A-Za-z0-9_-]+)\.(?P<semester>1stSemester|2ndSemester|Summer)\.pdf$',
    re.IGNORECASE,
)

STATUS_OPTIONS = [
    {'value': '', 'label': 'All Statuses'},
    {'value': VaultEntry.STATUS_PENDING, 'label': 'Pending AI'},
    {'value': VaultEntry.STATUS_APPROVED, 'label': 'Approved'},
    {'value': VaultEntry.STATUS_NEEDS_REVISION, 'label': 'Needs Revision'},
    {'value': 'Pre-Defense', 'label': 'Pre-Defense'},
    {'value': 'Vault Submission', 'label': 'Vault Submission'},
]

TYPE_OPTIONS = [
    {'value': '', 'label': 'All Types'},
    {'value': VaultEntry.TYPE_CAPSTONE, 'label': 'Capstone'},
    {'value': VaultEntry.TYPE_PIT, 'label': 'PIT'},
]


def is_admin(user):
    return getattr(user, 'role', None) == 'admin' or getattr(user, 'is_superuser', False)


def repository_scope(user):
    if is_admin(user):
        return {
            'scope': 'admin',
            'label': 'Admin repository audit',
            'pit_year_level': '',
            'can_upload_pit': True,
            'can_classify': True,
            'can_override': True,
            'can_demo_fill': bool(getattr(settings, 'ENABLE_PROTOTYPE_TOOLS', False)),
            'can_export': True,
        }
    if getattr(user, 'role', None) == 'faculty' and getattr(user, 'is_pit_lead', False):
        return {
            'scope': 'pit_lead',
            'label': 'PIT lead repository audit',
            'pit_year_level': user.pit_lead_year or '',
            'can_upload_pit': bool(user.pit_lead_year),
            'can_classify': bool(user.pit_lead_year),
            'can_override': False,
            'can_demo_fill': False,
            'can_export': True,
        }
    if getattr(user, 'role', None) == 'faculty' and getattr(user, 'is_repo_assistant', False):
        return {
            'scope': 'repo_assistant',
            'label': 'Repository assistant PIT uploads',
            'pit_year_level': '',
            'can_upload_pit': True,
            'can_classify': True,
            'can_override': False,
            'can_demo_fill': False,
            'can_export': True,
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
    if scope['scope'] == 'pit_lead':
        queryset = queryset.filter(year_level=scope['pit_year_level'])
    return queryset


def capstone_queryset_for_scope(scope):
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


def audit_trail(entry_type, source_id, file_name):
    logs = RepositoryAuditLog.objects.filter(entry_type=entry_type)
    if source_id:
        logs = logs.filter(source_id=source_id)
    else:
        logs = logs.filter(file_name=file_name)
    return [
        {
            'id': log.id,
            'action': log.action,
            'previous_status': log.previous_status,
            'new_status': log.new_status,
            'message': log.message,
            'actor': display_name(log.actor) or 'System',
            'created_at': log.created_at,
        }
        for log in logs[:8]
    ]


def pit_entry_payload(entry):
    return {
        'id': f'pit-{entry.id}',
        'source_id': entry.id,
        'type': VaultEntry.TYPE_PIT,
        'file_name': entry.file_name,
        'file_size': entry.file_size,
        'file_url': entry.file_url if hasattr(entry, 'file_url') else (entry.file.url if entry.file else ''),
        'deliverable_id': '',
        'deliverable_label': entry.file_name,
        'team_id': entry.team_id,
        'team_name': entry.team_name or (entry.team.name if entry.team else 'Unmatched'),
        'project_title': entry.metadata.get('project_title', '') if isinstance(entry.metadata, dict) else '',
        'year_level': entry.year_level,
        'academic_year': entry.academic_year,
        'semester': entry.semester_label,
        'stage': entry.stage_label or entry.course_code,
        'course_code': entry.course_code,
        'status': entry.status,
        'uploaded_by': entry.uploaded_by_name or display_name(entry.uploaded_by) or 'PIT Lead',
        'uploaded_at': entry.uploaded_at,
        'can_classify': entry.status == VaultEntry.STATUS_PENDING,
        'can_override': True,
        'audit_trail': audit_trail(VaultEntry.TYPE_PIT, entry.id, entry.file_name),
    }


def capstone_entry_payload(submission):
    team = submission.team
    is_vault = submission.deliverable_type == DeliverableSubmission.TYPE_VAULT
    return {
        'id': f'capstone-{submission.id}',
        'source_id': submission.id,
        'type': VaultEntry.TYPE_CAPSTONE,
        'file_name': submission.file_name,
        'file_size': submission.file_size,
        'file_url': submission.file_url if hasattr(submission, 'file_url') else (submission.file.url if submission.file else ''),
        'deliverable_id': submission.deliverable_id,
        'deliverable_label': submission.label,
        'team_id': team.id,
        'team_name': team.name,
        'project_title': team.project_title,
        'year_level': team.year_level,
        'academic_year': team.semester.school_year.label,
        'semester': team.semester.label,
        'stage': submission.stage_label,
        'course_code': '',
        'status': 'Vault Submission' if is_vault else 'Pre-Defense',
        'uploaded_by': display_name(submission.uploaded_by) or 'System',
        'uploaded_at': submission.uploaded_at,
        'can_classify': False,
        'can_override': False,
        'audit_trail': audit_trail(VaultEntry.TYPE_CAPSTONE, submission.id, submission.file_name),
    }


def scoped_entries(user):
    scope = repository_scope(user)
    entries = [pit_entry_payload(entry) for entry in pit_queryset_for_scope(scope)]
    entries.extend(capstone_entry_payload(submission) for submission in capstone_queryset_for_scope(scope))
    return sorted(entries, key=lambda item: item.get('uploaded_at'), reverse=True), scope


def matches_search(entry, search):
    if not search:
        return True
    text = ' '.join(
        str(entry.get(key) or '')
        for key in [
            'file_name',
            'deliverable_id',
            'deliverable_label',
            'team_name',
            'project_title',
            'stage',
            'course_code',
            'uploaded_by',
        ]
    ).lower()
    return search.lower() in text


def filter_entries(entries, query_params):
    search = query_params.get('search', '').strip()
    entry_type = query_params.get('type', '').strip()
    year_level = query_params.get('year_level', '').strip()
    academic_year = query_params.get('academic_year', '').strip()
    status = query_params.get('status', '').strip()
    semester = query_params.get('semester', '').strip()
    team_id = query_params.get('team_id', '').strip()
    stage = query_params.get('stage', '').strip()

    filtered = []
    for entry in entries:
        if entry_type and entry['type'] != entry_type:
            continue
        if year_level and entry.get('year_level') != year_level:
            continue
        if academic_year and entry.get('academic_year') != academic_year:
            continue
        if status and entry.get('status') != status:
            continue
        if semester and entry.get('semester') != semester:
            continue
        if team_id and str(entry.get('team_id') or '') != team_id:
            continue
        if stage and entry.get('stage') != stage:
            continue
        if not matches_search(entry, search):
            continue
        filtered.append(entry)
    return filtered


def counts_payload(entries, filtered_entries):
    return {
        'total': len(entries),
        'filtered': len(filtered_entries),
        'pit': sum(1 for entry in entries if entry['type'] == VaultEntry.TYPE_PIT),
        'capstone': sum(1 for entry in entries if entry['type'] == VaultEntry.TYPE_CAPSTONE),
        'pending': sum(1 for entry in entries if entry['status'] == VaultEntry.STATUS_PENDING),
        'approved': sum(1 for entry in entries if entry['status'] in [VaultEntry.STATUS_APPROVED, 'Vault Submission']),
        'needs_revision': sum(1 for entry in entries if entry['status'] == VaultEntry.STATUS_NEEDS_REVISION),
        'pre_defense': sum(1 for entry in entries if entry['status'] == 'Pre-Defense'),
        'vault_submissions': sum(1 for entry in entries if entry['status'] == 'Vault Submission'),
    }


def options_payload(entries):
    year_levels = sorted({entry['year_level'] for entry in entries if entry.get('year_level')})
    academic_years = {entry['academic_year'] for entry in entries if entry.get('academic_year')}
    academic_years.update(SchoolYear.objects.values_list('label', flat=True))
    semesters = sorted({entry['semester'] for entry in entries if entry.get('semester')})
    stages = sorted({entry['stage'] for entry in entries if entry.get('stage')})
    teams = sorted(
        {
            (entry['team_id'], entry['team_name'])
            for entry in entries
            if entry.get('team_id') and entry.get('team_name')
        },
        key=lambda item: item[1],
    )
    return {
        'type_options': TYPE_OPTIONS,
        'status_options': STATUS_OPTIONS,
        'year_levels': sorted(set(['1st Year', '2nd Year', '3rd Year', '4th Year'] + year_levels)),
        'academic_years': sorted(academic_years, reverse=True),
        'semesters': sorted(set(['1st Semester', '2nd Semester', 'Summer'] + semesters)),
        'stage_options': sorted(set(STAGE_OPTIONS + stages)),
        'teams': [{'id': team_id, 'name': name} for team_id, name in teams],
    }


def repository_audit_payload(request):
    entries, scope = scoped_entries(request.user)
    filtered = filter_entries(entries, request.query_params)
    for entry in filtered:
        if entry['type'] == VaultEntry.TYPE_PIT:
            entry['can_override'] = scope['can_override']
            entry['can_classify'] = scope['can_classify'] and entry['status'] == VaultEntry.STATUS_PENDING
    return {
        'entries': filtered,
        'counts': counts_payload(entries, filtered),
        'options': options_payload(entries),
        'scope': scope,
        'filters': {
            'search': request.query_params.get('search', ''),
            'type': request.query_params.get('type', ''),
            'year_level': request.query_params.get('year_level', ''),
            'academic_year': request.query_params.get('academic_year', ''),
            'status': request.query_params.get('status', ''),
            'semester': request.query_params.get('semester', ''),
            'team_id': request.query_params.get('team_id', ''),
            'stage': request.query_params.get('stage', ''),
        },
    }


def log_action(entry_type, source_id, file_name, action, actor, previous_status='', new_status='', message=''):
    return RepositoryAuditLog.objects.create(
        entry_type=entry_type,
        source_id=source_id,
        file_name=file_name,
        action=action,
        previous_status=previous_status or '',
        new_status=new_status or '',
        message=message,
        actor=actor,
    )


def resolve_pit_entry(user, entry_id):
    scope = repository_scope(user)
    if not (scope['can_classify'] or scope['can_override']):
        raise PermissionDenied('You do not have permission to modify this PIT entry.')
    source_id = str(entry_id).replace('pit-', '')
    if not source_id.isdigit():
        raise ValidationError('Invalid PIT entry id.')
    entry = pit_queryset_for_scope(scope).filter(pk=int(source_id)).first()
    if entry is None:
        raise PermissionDenied('PIT entry is outside your repository audit scope.')
    return entry, scope


def approved_pit_teams(year_level):
    if not year_level:
        return StudentTeam.objects.none()
    return StudentTeam.objects.filter(
        year_level=year_level,
        level__icontains='PIT',
        status=StudentTeam.STATUS_APPROVED,
    ).select_related('semester', 'semester__school_year')


def match_pit_team(file_name, year_level):
    metadata = validate_pit_file_name(file_name)
    file_key = normalize(file_name)
    for team in approved_pit_teams(year_level):
        project_key = normalize(team.project_title or team.name)
        team_key = normalize(team.name).replace('team', '')
        if project_key and project_key[:10] in file_key:
            return team
        if team_key and team_key in file_key:
            return team
    return None


@transaction.atomic
def upload_pit_files(user, file_names, year_level=None, academic_year=None):
    scope = repository_scope(user)
    if not scope['can_upload_pit']:
        raise PermissionDenied('You do not have permission to upload PIT entries.')
    selected_year = year_level or scope['pit_year_level']
    if scope['scope'] == 'pit_lead':
        selected_year = scope['pit_year_level']
    if selected_year not in PIT_PREFIX_BY_YEAR:
        raise ValidationError('Select a PIT year level before uploading.')

    academic_year = academic_year or active_academic_year_label()
    created = []
    skipped = []

    for raw_name in file_names:
        file_name = (raw_name or '').strip()
        if not file_name:
            continue
        try:
            metadata = validate_pit_file_name(file_name)
            if metadata['year_level'] != selected_year:
                raise ValidationError(f'{file_name} does not match {selected_year}.')
        except ValidationError as exc:
            skipped.append({'file_name': file_name, 'reason': '; '.join(exc.messages)})
            continue

        team = match_pit_team(file_name, selected_year)
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
                'status': VaultEntry.STATUS_PENDING,
                'uploaded_by': user,
                'metadata': {
                    'project_slug': metadata['project_slug'],
                    'matched': bool(team),
                    'project_title': team.project_title if team else metadata['project_slug'],
                },
            },
        )
        log_action(
            VaultEntry.TYPE_PIT,
            entry.id,
            entry.file_name,
            RepositoryAuditLog.ACTION_UPLOAD,
            user,
            new_status=entry.status,
            message='PIT file uploaded' if made else 'PIT file metadata refreshed',
        )
        created.append(entry)

    return created, skipped


@transaction.atomic
def classify_pit_entry(user, entry_id):
    entry, scope = resolve_pit_entry(user, entry_id)
    if not scope['can_classify']:
        raise PermissionDenied('You do not have permission to classify PIT entries.')
    previous = entry.status
    entry.status = VaultEntry.STATUS_APPROVED
    entry.save(update_fields=['status', 'updated_at'])
    log_action(
        VaultEntry.TYPE_PIT,
        entry.id,
        entry.file_name,
        RepositoryAuditLog.ACTION_CLASSIFY,
        user,
        previous_status=previous,
        new_status=entry.status,
        message='AI classification approved this PIT file.',
    )
    return entry


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


@transaction.atomic
def demo_fill_pit(user, year_level, academic_year=None):
    if not repository_scope(user)['can_demo_fill']:
        raise PermissionDenied('Only admins can run repository demo fill.')
    if year_level not in PIT_PREFIX_BY_YEAR:
        raise ValidationError('Select a PIT year level.')
    prefix = PIT_PREFIX_BY_YEAR[year_level]
    academic_year = academic_year or active_academic_year_label()
    sources = []
    teams = list(approved_pit_teams(year_level))
    if teams:
        for team in teams:
            sources.append({
                'team': team,
                'team_name': team.name,
                'project': normalize(team.project_title or team.name)[:40] or 'Project',
                'course': 'PIT101' if year_level == '1st Year' else 'PIT201' if year_level == '2nd Year' else 'PIT301',
            })
    else:
        sources = SAMPLE_PIT_PROJECTS.get(year_level, [])

    file_names = [
        f'{prefix}.{source["course"]}.{source["project"]}.1stSemester.pdf'
        for source in sources
    ]
    entries, skipped = upload_pit_files(user, file_names, year_level=year_level, academic_year=academic_year)
    for entry in entries:
        log_action(
            VaultEntry.TYPE_PIT,
            entry.id,
            entry.file_name,
            RepositoryAuditLog.ACTION_DEMO_FILL,
            user,
            new_status=entry.status,
            message=f'Demo fill generated PIT sample for {year_level}.',
        )
    return entries, skipped


@transaction.atomic
def demo_fill_capstone(user, stage_label, fill_pre=True, fill_vault=False, endorse=False):
    if not repository_scope(user)['can_demo_fill']:
        raise PermissionDenied('Only admins can run repository demo fill.')
    if stage_label not in DELIVERABLE_DEFINITIONS:
        raise ValidationError('Unknown Capstone stage.')
    definitions = DELIVERABLE_DEFINITIONS[stage_label]
    teams = StudentTeam.objects.filter(level__icontains='Capstone').select_related('semester', 'adviser')
    created = 0
    for team in teams:
        for definition in definitions:
            if definition['type'] == DeliverableSubmission.TYPE_PRE and not fill_pre:
                continue
            if definition['type'] == DeliverableSubmission.TYPE_VAULT and not fill_vault:
                continue
            safe_name = re.sub(r'[^A-Za-z0-9]+', '_', definition['label']).strip('_')
            submission, made = DeliverableSubmission.objects.update_or_create(
                team=team,
                stage_label=stage_label,
                deliverable_id=definition['id'],
                defaults={
                    'label': definition['label'],
                    'deliverable_type': definition['type'],
                    'required': definition['required'],
                    'file_name': f'{team.name.replace(" ", "_")}_{safe_name}.pdf',
                    'file_size': '512 KB',
                    'uploaded_by': user,
                },
            )
            if made:
                created += 1
            log_action(
                VaultEntry.TYPE_CAPSTONE,
                submission.id,
                submission.file_name,
                RepositoryAuditLog.ACTION_DEMO_FILL,
                user,
                new_status='Vault Submission' if definition['type'] == DeliverableSubmission.TYPE_VAULT else 'Pre-Defense',
                message=f'Demo fill generated Capstone file for {stage_label}.',
            )
        if endorse and fill_pre:
            team.ready_for_stage = stage_label
            team.current_defense_stage = stage_label
            team.save(update_fields=['ready_for_stage', 'current_defense_stage', 'updated_at'])
    return created


def repository_entries_count():
    return VaultEntry.objects.filter(entry_type=VaultEntry.TYPE_PIT).count() + DeliverableSubmission.objects.filter(
        team__level__icontains='Capstone',
    ).count()


def repository_pending_count():
    return VaultEntry.objects.filter(entry_type=VaultEntry.TYPE_PIT, status=VaultEntry.STATUS_PENDING).count()


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
