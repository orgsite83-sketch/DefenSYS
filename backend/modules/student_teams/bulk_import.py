from django.contrib.auth import get_user_model

from .models import StudentTeam, TeamMembership
from .serializers import BulkTeamRowSerializer, display_name
from .team_levels import prepare_bulk_row, program_label_for_row, user_is_pit_lead_only


User = get_user_model()

ADVISER_STATUS_NONE = 'none'
ADVISER_STATUS_VALID = 'valid'
ADVISER_STATUS_USER_NOT_FOUND = 'user_not_found'
ADVISER_STATUS_NOT_ADVISER = 'not_adviser'
ADVISER_STATUS_INACTIVE = 'inactive'

ADVISER_FILTER_ALL = 'all'
ADVISER_FILTER_WITH_ADVISER = 'with_adviser'
ADVISER_FILTER_WITHOUT_ADVISER = 'without_adviser'


def normalize_name(value):
    return ' '.join((value or '').strip().split()).casefold()


def _users_matching_full_name(value, *, role=None):
    normalized = normalize_name(value)
    if not normalized:
        return []

    queryset = User.objects.all()
    if role:
        queryset = queryset.filter(role=role)

    matches = []
    for user in queryset:
        if normalize_name(display_name(user)) == normalized:
            matches.append(user)
    return matches


def _user_by_username_ref(raw, *, role=None):
    queryset = User.objects.filter(username__iexact=raw)
    if role:
        queryset = queryset.filter(role=role)
    return queryset.first()


def resolve_user_by_full_name(value, *, role=None, field_label='User'):
    """
    Resolve a CSV reference by student/faculty ID (username) or full display name.
    Returns (user_or_none, error_message_or_none).
    """
    raw = (value or '').strip()
    if not raw:
        return None, None

    by_username = _user_by_username_ref(raw, role=role)
    if by_username is not None:
        return by_username, None

    matches = _users_matching_full_name(raw, role=role)
    if not matches:
        return None, f'{field_label} "{raw}": no user found with that name.'
    if len(matches) > 1:
        return None, (
            f'{field_label} "{raw}": multiple users match that name. '
            'Names must be unique in the system.'
        )
    return matches[0], None


def resolve_adviser_by_name(name):
    """
    Resolve CSV adviser_id (full name) to a User and validation status.
    Returns (user_or_none, status, display_name_or_empty).
    """
    raw = (name or '').strip()
    if not raw:
        return None, ADVISER_STATUS_NONE, ''

    normalized = normalize_name(raw)
    faculty_matches = [
        user
        for user in User.objects.filter(role__in=['faculty', 'admin'])
        if normalize_name(display_name(user)) == normalized
    ]
    if len(faculty_matches) > 1:
        return None, ADVISER_STATUS_USER_NOT_FOUND, ''
    if len(faculty_matches) == 1:
        user = faculty_matches[0]
        if not user.is_active:
            return None, ADVISER_STATUS_INACTIVE, display_name(user)
        if user.role == 'faculty' and not getattr(user, 'is_adviser', False):
            return None, ADVISER_STATUS_NOT_ADVISER, display_name(user)
        return user, ADVISER_STATUS_VALID, display_name(user)

    all_matches = _users_matching_full_name(raw)
    if not all_matches:
        return None, ADVISER_STATUS_USER_NOT_FOUND, ''
    if len(all_matches) > 1:
        return None, ADVISER_STATUS_USER_NOT_FOUND, ''
    return None, ADVISER_STATUS_NOT_ADVISER, display_name(all_matches[0])


def is_pit_bulk_row(data, user=None):
    level = (data.get('level') or '').upper()
    if 'PIT' in level:
        return True
    return bool(user and user_is_pit_lead_only(user))


def _existing_team_membership_issues(member_user_ids, *, team_name='', level=''):
    """Mirror StudentTeamWriteSerializer membership and duplicate-name checks."""
    issues = []
    if not member_user_ids:
        return issues

    for student_id in member_user_ids:
        membership = (
            TeamMembership.objects.filter(
                student_id=student_id,
                team__semester__is_active=True,
            )
            .select_related('team', 'student')
            .first()
        )
        if membership is None:
            continue
        student_name = display_name(membership.student)
        issues.append(
            f'{student_name} is already assigned to team "{membership.team.name}". '
            'A student can only be in one team at a time.'
        )

    if team_name and level:
        if StudentTeam.objects.filter(name=team_name, level=level).exists():
            issues.append('A team with this name already exists for this level.')

    return issues


def row_passes_adviser_filter(adviser_status, adviser_filter):
    if adviser_filter == ADVISER_FILTER_WITH_ADVISER:
        return adviser_status == ADVISER_STATUS_VALID
    if adviser_filter == ADVISER_FILTER_WITHOUT_ADVISER:
        return adviser_status == ADVISER_STATUS_NONE
    return True


def validate_bulk_team_row(
    data,
    adviser_filter=ADVISER_FILTER_ALL,
    user=None,
    csv_columns=None,
    *,
    section_import=False,
    import_section='',
):
    """
    Validate a parsed bulk row without writing to the DB.
    Returns dict with preview fields and import payload pieces.
    """
    issues = []
    warnings = []
    pit_row = is_pit_bulk_row(data, user)
    raw_adviser = (data.get('adviser_id') or '').strip()
    adviser_ref = '' if pit_row else raw_adviser
    if pit_row:
        if raw_adviser:
            warnings.append(
                f"PIT teams do not have advisers. The adviser_id column ('{raw_adviser}') will be ignored."
            )
        data = dict(data)
        data['adviser_id'] = ''
        adviser, adviser_status, adviser_name = None, ADVISER_STATUS_NONE, ''
    else:
        adviser, adviser_status, adviser_name = resolve_adviser_by_name(adviser_ref)

    if not pit_row and adviser_ref and adviser_status not in (ADVISER_STATUS_VALID,):
        normalized = normalize_name(adviser_ref)
        duplicate_advisers = [
            user
            for user in User.objects.filter(role__in=['faculty', 'admin'])
            if normalize_name(display_name(user)) == normalized
        ]
        if len(duplicate_advisers) > 1:
            issues.append(
                f'Adviser "{adviser_ref}": multiple users match that name. '
                'Names must be unique in the system.'
            )
        elif adviser_status == ADVISER_STATUS_USER_NOT_FOUND:
            issues.append(f'Adviser "{adviser_ref}" was not found.')
        elif adviser_status == ADVISER_STATUS_INACTIVE:
            issues.append(f'Adviser "{adviser_ref}" is inactive.')
        else:
            issues.append(f'User "{adviser_ref}" is not a project adviser.')

    member_ref_map = {}
    for member_ref in data['member_ids']:
        member_user, error = resolve_user_by_full_name(
            member_ref,
            role='student',
            field_label='Member',
        )
        if error:
            issues.append(error)
        elif member_user is not None:
            member_ref_map[member_ref] = member_user.id

    leader_ref = (data.get('leader_id') or '').strip()
    leader, leader_error = resolve_user_by_full_name(
        leader_ref,
        role='student',
        field_label='Leader',
    )
    if leader_error:
        issues.append(leader_error)
    elif leader is None and leader_ref:
        issues.append(f'Leader "{leader_ref}" must be a valid student user.')

    member_user_ids = set(member_ref_map.values())
    if leader is not None and leader.id not in member_user_ids:
        issues.append('Leader must be included in member_ids.')

    if user and not issues:
        prepared, prep_issues = prepare_bulk_row(
            data,
            user,
            member_user_ids=list(member_ref_map.values()),
            leader_user_id=leader.id if leader else None,
            csv_columns=csv_columns,
            section_import=section_import,
            import_section=import_section,
        )
        if prep_issues:
            issues.extend(prep_issues)
            data = prepared or data
        elif prepared:
            data = prepared

    if member_user_ids and not issues:
        issues.extend(
            _existing_team_membership_issues(
                list(member_user_ids),
                team_name=(data.get('team_name') or '').strip(),
                level=(data.get('level') or '').strip(),
            )
        )

    adviser_filter_ok = True if pit_row else row_passes_adviser_filter(adviser_status, adviser_filter)
    ready = (
        not issues
        and adviser_filter_ok
        and leader is not None
        and len(member_ref_map) == len(data['member_ids'])
    )

    return {
        'team_name': data['team_name'],
        'adviser_id': adviser_ref,
        'adviser_status': adviser_status,
        'adviser_name': adviser_name,
        'ready': ready,
        'issues': issues,
        'warnings': warnings,
        'leader': leader,
        'adviser': adviser,
        'member_ref_map': member_ref_map,
        'data': data,
    }


def preview_bulk_teams(
    rows,
    adviser_filter=ADVISER_FILTER_ALL,
    user=None,
    csv_columns=None,
    *,
    section_import=False,
    import_section='',
):
    preview_rows = []
    summary = {
        'total': 0,
        'with_adviser': 0,
        'without_adviser': 0,
        'adviser_invalid': 0,
        'ready': 0,
    }

    for index, row in enumerate(rows, start=1):
        prepared, prep_issues = (
            prepare_bulk_row(
                row,
                user,
                check_template=True,
                csv_columns=csv_columns,
                section_import=section_import,
                import_section=import_section,
            )
            if user
            else (row, [])
        )
        if prep_issues:
            preview_rows.append({
                'row': index,
                'sheet_row': index + 1,
                'team_name': row.get('team_name', ''),
                'adviser_id': (row.get('adviser_id') or '').strip(),
                'adviser_status': ADVISER_STATUS_NONE,
                'adviser_name': '',
                'ready': False,
                'issues': prep_issues,
            })
            summary['total'] += 1
            raw_adviser = (row.get('adviser_id') or '').strip()
            if raw_adviser:
                summary['adviser_invalid'] += 1
            else:
                summary['without_adviser'] += 1
            continue

        row_serializer = BulkTeamRowSerializer(
            data=prepared,
            context={
                'user': user,
                'section_import': section_import,
                'import_section': import_section,
            },
        )
        if not row_serializer.is_valid():
            preview_rows.append({
                'row': index,
                'sheet_row': index + 1,
                'team_name': row.get('team_name', ''),
                'adviser_id': (row.get('adviser_id') or '').strip(),
                'adviser_status': ADVISER_STATUS_NONE,
                'adviser_name': '',
                'ready': False,
                'issues': [_format_serializer_errors(row_serializer.errors)],
            })
            summary['total'] += 1
            raw_adviser = (row.get('adviser_id') or '').strip()
            if raw_adviser:
                summary['adviser_invalid'] += 1
            else:
                summary['without_adviser'] += 1
            continue

        result = validate_bulk_team_row(
            row_serializer.validated_data,
            adviser_filter=adviser_filter,
            user=user,
            csv_columns=csv_columns,
            section_import=section_import,
            import_section=import_section,
        )
        row_data = result['data']
        preview_rows.append({
            'row': index,
            'sheet_row': index + 1,
            'team_name': result['team_name'],
            'adviser_id': result['adviser_id'],
            'adviser_status': result['adviser_status'],
            'adviser_name': result['adviser_name'],
            'year_level': row_data.get('year_level', ''),
            'section': row_data.get('section', ''),
            'level': row_data.get('level', ''),
            'program_label': program_label_for_row(row_data, user) if user else '',
            'ready': result['ready'],
            'issues': result['issues'],
            'warnings': result.get('warnings', []),
        })

        summary['total'] += 1
        if result['adviser_status'] == ADVISER_STATUS_VALID:
            summary['with_adviser'] += 1
        elif result['adviser_status'] == ADVISER_STATUS_NONE:
            summary['without_adviser'] += 1
        else:
            summary['adviser_invalid'] += 1
        if result['ready']:
            summary['ready'] += 1

    return preview_rows, summary


def format_bulk_import_errors(errors):
    """Turn serializer/API error payloads into human-readable strings."""
    if isinstance(errors, list):
        return [str(item) for item in errors]
    if isinstance(errors, dict):
        lines = []
        for field, messages in errors.items():
            if isinstance(messages, (list, tuple)):
                for item in messages:
                    if isinstance(item, dict):
                        lines.extend(format_bulk_import_errors(item))
                    else:
                        lines.append(f'{field}: {item}')
            elif isinstance(messages, dict):
                lines.extend(format_bulk_import_errors(messages))
            else:
                lines.append(f'{field}: {messages}')
        return lines
    return [str(errors)]


def _format_serializer_errors(errors):
    return '; '.join(format_bulk_import_errors(errors))


def build_team_payload_from_row(result, user=None):
    data = result['data']
    member_ref_map = result['member_ref_map']
    leader = result['leader']
    adviser = result['adviser']
    pit_row = is_pit_bulk_row(data, user)

    return {
        'name': data['team_name'],
        'project_title': data.get('project_title') or data['team_name'],
        'level': data['level'],
        'year_level': data.get('year_level') or '',
        'section': data.get('section') or '',
        'member_ids': [member_ref_map[item] for item in data['member_ids'] if item in member_ref_map],
        'leader_id': leader.id if leader else None,
        'adviser_id': None if pit_row else (adviser.id if adviser else None),
    }


resolve_adviser_username = resolve_adviser_by_name
