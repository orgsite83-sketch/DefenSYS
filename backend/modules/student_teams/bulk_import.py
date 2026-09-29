import re
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


PREFIX_PATTERNS = [
    r'associate\s+professor',
    r'assistant\s+professor',
    r'assoc\.?\s*prof\.?',
    r'asst\.?\s*prof\.?',
    r'prof(?:essor)?\.?',
    r'dr\.?',
    r'doctor',
    r'engr\.?',
    r'engineer',
    r'atty\.?',
    r'attorney',
    r'arch(?:itect)?\.?',
    r'dean',
    r'chair(?:person)?',
    r'inst(?:ructor)?\.?',
    r'lect(?:urer)?\.?',
    r'hon(?:orable)?\.?',
    r'rev(?:erend)?\.?',
    r'pastor|pst\.?',
    r'fr\.?|father',
    r'mr\.?',
    r'mrs\.?',
    r'ms\.?',
    r'mx\.?',
    r'sir',
    r'ma[\'\’]?am|mam',
]

SUFFIX_PATTERNS = [
    r'ph\.?d\.?',
    r'd\.?eng\.?',
    r'd\.?i\.?t\.?',
    r'd\.?b\.?a\.?',
    r'ed\.?d\.?',
    r'm\.?d\.?',
    r'j\.?d\.?',
    r'sc\.?d\.?',
    r'm\.?sc\.?',
    r'm\.?s\.?',
    r'm\.?a\.?',
    r'm\.?eng\.?',
    r'm\.?i\.?t\.?',
    r'm\.?s\.?i\.?t\.?',
    r'm\.?b\.?a\.?',
    r'm\.?p\.?a\.?',
    r'm\.?ed\.?',
    r'b\.?sc\.?',
    r'b\.?s\.?',
    r'b\.?a\.?',
    r'b\.?s\.?i\.?t\.?',
    r'p\.?e\.?',
    r'c\.?p\.?a\.?',
    r'rce|ece|ree|rme',
    r'pmp|cisa|cissp',
    r'jr\.?|sr\.?',
    r'ii|iii|iv|v',
]

PREFIX_RE = re.compile(r'^(?:' + '|'.join(PREFIX_PATTERNS) + r')\b[\s\.]*', re.IGNORECASE)
SUFFIX_RE = re.compile(r'(?:[\s,\.]+|\b)(?:' + '|'.join(SUFFIX_PATTERNS) + r')\.?$', re.IGNORECASE)
SUFFIX_ISOLATED_RE = re.compile(r'^(?:' + '|'.join(SUFFIX_PATTERNS) + r')\.?$', re.IGNORECASE)


def _strip_token(token):
    prev = None
    s = (token or '').strip()
    while s and s != prev:
        prev = s
        s = SUFFIX_RE.sub('', s).strip()
        s = PREFIX_RE.sub('', s).strip()
    return s


def clean_person_name(name):
    """
    Strip academic, professional, and courtesy titles/honorifics (e.g. 'Prof.', 'Dr.',
    'Engr.', 'Atty.', 'PhD', 'MSIT') from a person's name string so it can match
    a user registered in the system.
    """
    if not name:
        return ''
    s = name.strip()
    prev = None
    while s and s != prev:
        prev = s
        s = SUFFIX_RE.sub('', s).strip()
        s = PREFIX_RE.sub('', s).strip()

    if ',' in s:
        raw_parts = [p.strip() for p in s.split(',')]
        valid_parts = []
        for p in raw_parts:
            if not p or SUFFIX_ISOLATED_RE.match(p.strip().rstrip('.')):
                continue
            cleaned = _strip_token(p)
            if cleaned:
                valid_parts.append(cleaned)
        if len(valid_parts) == 2:
            return f'{valid_parts[1]} {valid_parts[0]}'
        elif len(valid_parts) == 1:
            return valid_parts[0]
        elif valid_parts:
            return ' '.join(valid_parts)

    return _strip_token(s)


def normalize_name(value):
    return ' '.join((value or '').strip().split()).casefold()


def _users_matching_full_name(value, *, role=None):
    normalized = normalize_name(value)
    if not normalized:
        return []

    queryset = User.objects.all()
    if role:
        if isinstance(role, (list, tuple, set)):
            queryset = queryset.filter(role__in=role)
        else:
            queryset = queryset.filter(role=role)

    matches = []
    cleaned_input = normalize_name(clean_person_name(value))
    for user in queryset:
        d_name = display_name(user)
        user_norm = normalize_name(d_name)
        if user_norm == normalized:
            matches.append(user)
        elif cleaned_input:
            user_clean = normalize_name(clean_person_name(d_name))
            if user_clean == cleaned_input or user_norm == cleaned_input:
                matches.append(user)
    return matches


def _user_by_username_ref(raw, *, role=None):
    queryset = User.objects.filter(username__iexact=raw)
    if role:
        if isinstance(role, (list, tuple, set)):
            queryset = queryset.filter(role__in=role)
        else:
            queryset = queryset.filter(role=role)
    return queryset.first()


def _users_matching_initial_and_surname(surname, initial, *, role=None):
    clean_sur = clean_person_name(surname)
    norm_surname = normalize_name(clean_sur or surname)
    clean_init = clean_person_name(initial)
    norm_initial = normalize_name((clean_init or initial).rstrip('.'))
    if not norm_surname or not norm_initial:
        return []
    queryset = User.objects.all()
    if role:
        if isinstance(role, (list, tuple, set)):
            queryset = queryset.filter(role__in=role)
        else:
            queryset = queryset.filter(role=role)
    matches = []
    for user in queryset:
        user_last = normalize_name(user.last_name)
        user_last_clean = normalize_name(clean_person_name(user.last_name))
        user_first = normalize_name(user.first_name)
        user_first_clean = normalize_name(clean_person_name(user.first_name))
        last_matches = (user_last == norm_surname or user_last_clean == norm_surname)
        first_matches = (user_first.startswith(norm_initial) or user_first_clean.startswith(norm_initial))
        if last_matches and first_matches:
            matches.append(user)
    return matches


def _users_matching_surname_only(surname, *, role=None):
    clean_sur = clean_person_name(surname)
    norm_surname = normalize_name(clean_sur or surname)
    if not norm_surname:
        return []
    queryset = User.objects.all()
    if role:
        if isinstance(role, (list, tuple, set)):
            queryset = queryset.filter(role__in=role)
        else:
            queryset = queryset.filter(role=role)
    matches = []
    for user in queryset:
        user_last = normalize_name(user.last_name)
        user_last_clean = normalize_name(clean_person_name(user.last_name))
        if user_last == norm_surname or user_last_clean == norm_surname:
            matches.append(user)
    return matches


def _resolve_user_by_name_or_id(raw, *, role=None, field_label='User'):
    # 1. By ID (username)
    by_username = _user_by_username_ref(raw, role=role)
    if by_username is not None:
        return by_username, None

    # 2. Exact full display name
    matches = _users_matching_full_name(raw, role=role)
    if len(matches) == 1:
        return matches[0], None
    if len(matches) > 1:
        candidates = [f"{display_name(u)} ({u.username})" for u in matches]
        return None, (
            f'{field_label} "{raw}": multiple users match that name ({", ".join(candidates)}). '
            'Use Student ID to specify.'
        )

    # 3. Inverted name with comma ("Last, First")
    if ',' in raw:
        parts = [p.strip() for p in raw.split(',', 1)]
        last_part, first_part = parts[0], parts[1]

        clean_initial = first_part.rstrip('.').strip()
        if len(clean_initial) == 1 and clean_initial.isalpha():
            initial_matches = _users_matching_initial_and_surname(last_part, clean_initial, role=role)
            if len(initial_matches) == 1:
                return initial_matches[0], None
            if len(initial_matches) > 1:
                candidates = [f"{display_name(u)} ({u.username})" for u in initial_matches]
                return None, (
                    f'{field_label} "{raw}": multiple users match surname "{last_part}" with initial "{clean_initial}" '
                    f'({", ".join(candidates)}). Please specify full name or Student ID.'
                )

        inverted = f"{first_part} {last_part}"
        inverted_matches = _users_matching_full_name(inverted, role=role)
        if len(inverted_matches) == 1:
            return inverted_matches[0], None
        if len(inverted_matches) > 1:
            candidates = [f"{display_name(u)} ({u.username})" for u in inverted_matches]
            return None, (
                f'{field_label} "{raw}": multiple users match that name ({", ".join(candidates)}). '
                'Use Student ID to specify.'
            )

    # 4. Space-separated Initial + Surname ("M. Garcia" or "Garcia M.")
    words = raw.split()
    if len(words) == 2:
        w0_clean = words[0].rstrip('.').strip()
        w1_clean = words[1].rstrip('.').strip()
        if len(w0_clean) == 1 and w0_clean.isalpha():
            initial_matches = _users_matching_initial_and_surname(words[1], w0_clean, role=role)
            if len(initial_matches) == 1:
                return initial_matches[0], None
            if len(initial_matches) > 1:
                candidates = [f"{display_name(u)} ({u.username})" for u in initial_matches]
                return None, (
                    f'{field_label} "{raw}": multiple users match surname "{words[1]}" with initial "{w0_clean}" '
                    f'({", ".join(candidates)}). Please specify full name or Student ID.'
                )
        elif len(w1_clean) == 1 and w1_clean.isalpha():
            initial_matches = _users_matching_initial_and_surname(words[0], w1_clean, role=role)
            if len(initial_matches) == 1:
                return initial_matches[0], None
            if len(initial_matches) > 1:
                candidates = [f"{display_name(u)} ({u.username})" for u in initial_matches]
                return None, (
                    f'{field_label} "{raw}": multiple users match surname "{words[0]}" with initial "{w1_clean}" '
                    f'({", ".join(candidates)}). Please specify full name or Student ID.'
                )

    # 5. Surname lookup (e.g. "Baguingco", "Dela Cruz", "Santos")
    if not (',' in raw):
        surname_matches = _users_matching_surname_only(raw, role=role)
        if len(surname_matches) == 1:
            return surname_matches[0], None
        if len(surname_matches) > 1:
            candidates = [f"{display_name(u)} ({u.username})" for u in surname_matches]
            return None, (
                f'{field_label} "{raw}": multiple users share the surname "{raw}" '
                f'({", ".join(candidates)}). Please specify their first name or Student ID.'
            )

    return None, f'{field_label} "{raw}": no user found with that name.'


def resolve_user_by_full_name(value, *, role=None, field_label='User'):
    """
    Resolve a CSV reference by student/faculty ID (username) or full display name,
    with smart support for:
    - Exact student/faculty ID
    - Full name ("First Last")
    - Inverted name with comma ("Last, First")
    - Surname + Initial ("Garcia, M." / "M. Garcia")
    - Unique surname within cohort ("Baguingco")
    - Academic/courtesy titles and honorifics ("Prof. Jonathan Beltran", "Dr. Beltran")
    Returns (user_or_none, error_message_or_none).
    """
    raw = (value or '').strip()
    if not raw:
        return None, None

    user, error = _resolve_user_by_name_or_id(raw, role=role, field_label=field_label)
    if user is not None:
        return user, None

    cleaned = clean_person_name(raw)
    if cleaned and normalize_name(cleaned) != normalize_name(raw):
        c_user, c_error = _resolve_user_by_name_or_id(cleaned, role=role, field_label=field_label)
        if c_user is not None:
            return c_user, None
        if c_error and 'multiple users' in c_error:
            return None, c_error

    return None, error


def resolve_adviser(name_or_username):
    """
    Resolve CSV adviser reference (full name, surname, or username/faculty ID) to a User and validation status.
    Supports academic titles and honorifics (e.g., 'Prof. Jonathan Beltran', 'Dr. Beltran', 'Jonathan Beltran, PhD').
    Returns (user_or_none, status, display_name_or_empty).
    """
    raw = (name_or_username or '').strip()
    if not raw:
        return None, ADVISER_STATUS_NONE, ''

    # 1. Try resolving by username first (matching role=['faculty', 'admin'])
    user = _user_by_username_ref(raw, role=['faculty', 'admin'])
    if user:
        if not user.is_active:
            return None, ADVISER_STATUS_INACTIVE, display_name(user)
        return user, ADVISER_STATUS_VALID, display_name(user)

    # 2. Try resolving by full name
    faculty_matches = _users_matching_full_name(raw, role=['faculty', 'admin'])
    if len(faculty_matches) == 1:
        user = faculty_matches[0]
        if not user.is_active:
            return None, ADVISER_STATUS_INACTIVE, display_name(user)
        return user, ADVISER_STATUS_VALID, display_name(user)

    # 3. Try inverted name "Last, First"
    if ',' in raw:
        parts = [p.strip() for p in raw.split(',', 1)]
        inverted = f"{parts[1]} {parts[0]}"
        inv_matches = _users_matching_full_name(inverted, role=['faculty', 'admin'])
        if len(inv_matches) == 1:
            user = inv_matches[0]
            if not user.is_active:
                return None, ADVISER_STATUS_INACTIVE, display_name(user)
            return user, ADVISER_STATUS_VALID, display_name(user)

    # 4. Try single surname lookup for faculty
    words = raw.split()
    if len(words) == 1 and not (',' in raw):
        sur_matches = _users_matching_surname_only(raw, role=['faculty', 'admin'])
        if len(sur_matches) == 1:
            user = sur_matches[0]
            if not user.is_active:
                return None, ADVISER_STATUS_INACTIVE, display_name(user)
            return user, ADVISER_STATUS_VALID, display_name(user)

    # 5. Smart title / honorific fallback (e.g. "Prof. Jonathan Beltran", "Dr. Beltran", "Jonathan Beltran, PhD")
    cleaned = clean_person_name(raw)
    if cleaned and normalize_name(cleaned) != normalize_name(raw):
        c_user = _user_by_username_ref(cleaned, role=['faculty', 'admin'])
        if c_user:
            if not c_user.is_active:
                return None, ADVISER_STATUS_INACTIVE, display_name(c_user)
            return c_user, ADVISER_STATUS_VALID, display_name(c_user)

        c_matches = _users_matching_full_name(cleaned, role=['faculty', 'admin'])
        if len(c_matches) == 1:
            user = c_matches[0]
            if not user.is_active:
                return None, ADVISER_STATUS_INACTIVE, display_name(user)
            return user, ADVISER_STATUS_VALID, display_name(user)

        if ',' in cleaned:
            parts = [p.strip() for p in cleaned.split(',', 1)]
            inverted = f"{parts[1]} {parts[0]}"
            inv_matches = _users_matching_full_name(inverted, role=['faculty', 'admin'])
            if len(inv_matches) == 1:
                user = inv_matches[0]
                if not user.is_active:
                    return None, ADVISER_STATUS_INACTIVE, display_name(user)
                return user, ADVISER_STATUS_VALID, display_name(user)

        c_words = cleaned.split()
        if len(c_words) == 1 and not (',' in cleaned):
            sur_matches = _users_matching_surname_only(cleaned, role=['faculty', 'admin'])
            if len(sur_matches) == 1:
                user = sur_matches[0]
                if not user.is_active:
                    return None, ADVISER_STATUS_INACTIVE, display_name(user)
                return user, ADVISER_STATUS_VALID, display_name(user)

        if len(c_words) == 2:
            w0 = c_words[0].rstrip('.').strip()
            w1 = c_words[1].rstrip('.').strip()
            if len(w0) == 1 and w0.isalpha():
                init_matches = _users_matching_initial_and_surname(c_words[1], w0, role=['faculty', 'admin'])
                if len(init_matches) == 1:
                    user = init_matches[0]
                    if not user.is_active:
                        return None, ADVISER_STATUS_INACTIVE, display_name(user)
                    return user, ADVISER_STATUS_VALID, display_name(user)
            elif len(w1) == 1 and w1.isalpha():
                init_matches = _users_matching_initial_and_surname(c_words[0], w1, role=['faculty', 'admin'])
                if len(init_matches) == 1:
                    user = init_matches[0]
                    if not user.is_active:
                        return None, ADVISER_STATUS_INACTIVE, display_name(user)
                    return user, ADVISER_STATUS_VALID, display_name(user)

    all_matches = _users_matching_full_name(raw)
    if not all_matches and cleaned:
        all_matches = _users_matching_full_name(cleaned)
    if not all_matches:
        any_user = _user_by_username_ref(raw) or (cleaned and _user_by_username_ref(cleaned))
        if any_user:
            return None, ADVISER_STATUS_NOT_ADVISER, display_name(any_user)
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
    raw_adviser = (data.get('adviser_name') or data.get('adviser_id') or '').strip()
    adviser_ref = '' if pit_row else raw_adviser
    if pit_row:
        if raw_adviser:
            column_name = 'adviser_name' if data.get('adviser_name') else 'adviser_id'
            warnings.append(
                f"PIT teams do not have advisers. The {column_name} column ('{raw_adviser}') will be ignored."
            )
        data = dict(data)
        data['adviser_name'] = ''
        data['adviser_id'] = ''
        adviser, adviser_status, adviser_name = None, ADVISER_STATUS_NONE, ''
    else:
        adviser, adviser_status, adviser_name = resolve_adviser(adviser_ref)

    if not pit_row and adviser_ref and adviser_status not in (ADVISER_STATUS_VALID,):
        normalized = normalize_name(adviser_ref)
        duplicate_advisers = _users_matching_full_name(adviser_ref, role=['faculty', 'admin'])
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
            issues.append(f'User "{adviser_ref}" is not a faculty member.')

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

    pit_row = is_pit_bulk_row(data, user)
    if pit_row:
        if raw_adviser and not any("PIT teams do not have advisers" in w for w in warnings):
            column_name = 'adviser_name' if data.get('adviser_name') else 'adviser_id'
            warnings.append(
                f"PIT teams do not have advisers. The {column_name} column ('{raw_adviser}') will be ignored."
            )
        data = dict(data)
        data['adviser_name'] = ''
        data['adviser_id'] = ''
        adviser, adviser_status, adviser_name = None, ADVISER_STATUS_NONE, ''
        adviser_ref = ''
        # Remove any adviser-related issues since PIT teams do not have advisers
        issues = [
            issue for issue in issues
            if not (issue.startswith('Adviser "') or issue.endswith('is not a project adviser.'))
        ]

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
        'ready': 0,
        'with_adviser': 0,
        'without_adviser': 0,
        'adviser_invalid': 0,
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
                'adviser_id': (row.get('adviser_id') or row.get('adviser_name') or '').strip(),
                'adviser_name': (row.get('adviser_name') or row.get('adviser_id') or '').strip(),
                'adviser_status': ADVISER_STATUS_NONE,
                'section': (row.get('section') or '').strip(),
                'ready': False,
                'issues': prep_issues,
            })
            summary['total'] += 1
            raw_adviser = (row.get('adviser_id') or row.get('adviser_name') or '').strip()
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
                'adviser_id': (row.get('adviser_id') or row.get('adviser_name') or '').strip(),
                'adviser_name': (row.get('adviser_name') or row.get('adviser_id') or '').strip(),
                'adviser_status': ADVISER_STATUS_NONE,
                'section': (row.get('section') or '').strip(),
                'ready': False,
                'issues': ['; '.join(format_bulk_import_errors(row_serializer.errors))],
            })
            summary['total'] += 1
            raw_adviser = (row.get('adviser_id') or row.get('adviser_name') or '').strip()
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



