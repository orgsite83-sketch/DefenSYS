import re
from contextlib import contextmanager
from contextvars import ContextVar
from django.contrib.auth import get_user_model

from .models import StudentTeam, TeamMembership
from .serializers import BulkTeamRowSerializer, display_name
from .team_levels import prepare_bulk_row, program_label_for_row, user_is_pit_lead_only


User = get_user_model()
_import_users = ContextVar('team_import_users', default=None)


def participation_preview(student_ids):
    from .participation import roster_preview
    from .term_scope import get_active_semester
    return roster_preview(student_ids, get_active_semester())


@contextmanager
def import_user_lookup():
    """One account projection per review; retain the normal name/ID matching rules."""
    if _import_users.get() is not None:
        yield
        return
    token = _import_users.set(list(User.objects.only(
        'id', 'username', 'first_name', 'last_name', 'role', 'is_active')))
    try:
        yield
    finally:
        _import_users.reset(token)


def _role_users(role):
    cached = _import_users.get()
    if cached is not None:
        roles = role if isinstance(role, (list, tuple, set)) else [role]
        return [u for u in cached if not role or u.role in roles]
    queryset = User.objects.all()
    if role:
        roles = role if isinstance(role, (list, tuple, set)) else [role]
        queryset = queryset.filter(role__in=roles)
    return queryset

ADVISER_STATUS_NONE = 'none'
ADVISER_STATUS_VALID = 'valid'
ADVISER_STATUS_USER_NOT_FOUND = 'user_not_found'
ADVISER_STATUS_NOT_ADVISER = 'not_adviser'
ADVISER_STATUS_INACTIVE = 'inactive'

ADVISER_FILTER_ALL = 'all'
ADVISER_FILTER_WITH_ADVISER = 'with_adviser'
ADVISER_FILTER_WITHOUT_ADVISER = 'without_adviser'


def imported_concept_requirement(data):
    """Resolve the same intent for preview and commit, before display-title fallbacks."""
    from .concept_policy import context_key, contexts_for, resolve_policy
    from .term_scope import get_active_semester
    title = (data.get('project_title') or '').strip()
    assignment = {'mode': 'proposals', 'seed_title': title,
                  'assigned_title': title, 'project_version': 1}
    candidate = StudentTeam(name=data['team_name'], project_title=title,
        level=data.get('level', ''), year_level=data.get('year_level', ''),
        section=data.get('section', ''), semester=get_active_semester(), concept_assignment=assignment,
        current_defense_stage=data.get('current_defense_stage') or None)
    contexts = contexts_for(candidate)
    if candidate.is_pit and candidate.current_defense_stage:
        contexts = contexts.filter(event_name=candidate.current_defense_stage)
    stage = contexts.first()
    if stage:
        assignment['context_key'] = context_key(stage)
    policy = resolve_policy(candidate, stage, use_round=False) if stage else {
        'mode': 'proposals', 'required_count': 1 if title else 3, 'assigned_title': '', 'seed_title': title}
    label = ('First module supplied' if data.get('system_name') else 'First concept supplied') if title else 'Concept titles needed'
    return assignment, {**policy, 'label': f'{label} · {policy["required_count"]} concept' +
        ('' if policy['required_count'] == 1 else 's'), 'stage_label': stage.label if stage else None}


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

    queryset = _role_users(role)

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
    if _import_users.get() is not None:
        return next((u for u in _role_users(role) if u.username.casefold() == raw.casefold()), None)
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
    queryset = _role_users(role)
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
    queryset = _role_users(role)
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


def _existing_team_membership_issues(member_user_ids, *, team_name='', level='', event_name=''):
    """Mirror StudentTeamWriteSerializer membership and duplicate-name checks."""
    issues = []
    if not member_user_ids:
        return issues, []

    from .term_scope import get_active_semester
    from .membership_policy import allows_multiple, pit_event_memberships
    semester = get_active_semester()
    pit = 'PIT' in level.upper()
    unrestricted = pit and allows_multiple(semester, event_name)
    existing = None
    if not pit:
        from .participation import existing_roster
        existing = existing_roster(member_user_ids, semester, team_name, level)
    memberships = TeamMembership.objects.filter(student_id__in=member_user_ids, team__semester=semester)
    if existing:
        memberships = memberships.exclude(team=existing)
    if pit:
        memberships = pit_event_memberships(memberships.filter(team__level__icontains='PIT'), event_name)
    conflicts = {}
    for membership in memberships.select_related('team', 'student').order_by('team_id', 'student_id'):
        conflicts[membership.team_id] = {'id': membership.team_id, 'name': membership.team.name,
            'event_name': membership.team.current_defense_stage or '', 'section': membership.team.section}
        if unrestricted:
            continue
        student_name = display_name(membership.student)
        issues.append(
            f'{student_name} is already assigned to team "{membership.team.name}". '
            + ('This PIT roster already exists for the active semester. '
               'Review the existing roster and its concept proposals before importing another team.'
               if pit and not event_name else
               'The selected membership policy allows one team in this context.')
        )

    if team_name and level:
        if StudentTeam.objects.filter(name=team_name, level=level, semester=semester).exclude(pk=existing.pk if existing else None).exists():
            issues.append('A team with this name already exists for this level.')

    return issues, list(conflicts.values())


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
    membership_conflicts = []
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

    # Instructors belong to a PIT section, never to the team's adviser field.
    # Preview resolves the reference without granting roles or writing assignments.
    instructor = None
    instructor_ref = (data.get('instructor_name') or '').strip()
    if instructor_ref:
        if not pit_row:
            issues.append('Instructor is only supported for PIT sections. Use Adviser for Capstone teams.')
        else:
            instructor, instructor_error = resolve_user_by_full_name(
                instructor_ref, role=['faculty', 'admin'], field_label='Instructor',
            )
            if instructor_error:
                issues.append(instructor_error)
            elif not instructor.is_active:
                issues.append(f'Instructor "{instructor_ref}" is inactive.')
            if not (data.get('section') or '').strip():
                issues.append('A section is required to assign a PIT instructor.')

    if member_user_ids:
        from .roster_enrollment import missing_enrollment_issues
        from .term_scope import get_active_semester
        issues.extend(missing_enrollment_issues(member_user_ids, get_active_semester()))

    if member_user_ids and not issues:
        if not pit_row:
            from .participation import validate_roster, existing_roster
            from .term_scope import get_active_semester
            from rest_framework.exceptions import ValidationError
            term = get_active_semester()
            current = existing_roster(member_user_ids, term, data.get('team_name', ''), data.get('level', ''))
            try:
                validate_roster(member_user_ids, term, team=current)
            except ValidationError as exc:
                detail = exc.detail.get('member_ids', []) if isinstance(exc.detail, dict) else [exc.detail]
                issues.extend(str(message) for message in detail)
        membership_issues, membership_conflicts = _existing_team_membership_issues(
                list(member_user_ids),
                team_name=(data.get('team_name') or '').strip(),
                level=(data.get('level') or '').strip(),
                event_name=(data.get('current_defense_stage') or '').strip(),
            )
        issues.extend(membership_issues)
        from .membership_policy import allows_multiple, pit_event_memberships
        from .term_scope import get_active_semester
        event_name = (data.get('current_defense_stage') or '').strip()
        if pit_row and allows_multiple(get_active_semester(), event_name):
            names = [team['name'] for team in membership_conflicts]
            if names:
                warnings.append(f'These students already belong to {", ".join(names)}. '
                    f'The multiple-team policy for "{event_name}" permits an additional roster; '
                    'existing concepts, files and approvals stay with their original teams.')

    concept_assignment, concept_requirement = imported_concept_requirement(data)
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
        'instructor_name': display_name(instructor) if instructor else instructor_ref,
        'instructor': instructor,
        'ready': ready,
        'issues': issues,
        'warnings': warnings,
        'membership_conflicts': membership_conflicts,
        'leader': leader,
        'adviser': adviser,
        'member_ref_map': member_ref_map,
        'data': data,
        'concept_assignment': concept_assignment,
        'concept_requirement': concept_requirement,
        'participation_preview': participation_preview(member_user_ids) if not pit_row and not issues else [],
    }


def preview_bulk_teams(
    rows,
    adviser_filter=ADVISER_FILTER_ALL,
    user=None,
    csv_columns=None,
    *,
    section_import=False,
    import_section='',
    section_metadata=None,
):
    if section_metadata is None:
        section_metadata = collect_bulk_section_metadata(rows, import_section=import_section)
    preview_rows = []
    checked_rows = []
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
                'instructor_name': (row.get('instructor_name') or '').strip(),
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
                'instructor_name': (row.get('instructor_name') or '').strip(),
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
        checked_rows.append((len(preview_rows), row_data, set(result['member_ref_map'].values())))
        preview_rows.append({
            'row': index,
            'sheet_row': index + 1,
            'team_name': result['team_name'] or f'Unnamed team {index}',
            'group_key': row_data.get('group_key', ''),
            'needs_name': not bool(row_data.get('team_name')),
            'needs_project': not bool(row_data.get('project_title')),
            'adviser_id': result['adviser_id'],
            'adviser_status': result['adviser_status'],
            'adviser_name': result['adviser_name'],
            'instructor_name': result['instructor_name'],
            'year_level': row_data.get('year_level', ''),
            'section': row_data.get('section', ''),
            'level': row_data.get('level', ''),
            'program_label': program_label_for_row(row_data, user) if user else '',
            'ready': result['ready'],
            'issues': result['issues'],
            'warnings': result.get('warnings', []),
            'membership_conflicts': result['membership_conflicts'],
            'concept_requirement': result['concept_requirement'],
            'participation_preview': result['participation_preview'],
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

    # Validate the file as a batch, not just against records already in the DB.
    # Mark both conflicting rows so neither is misleadingly shown as Ready.
    from .membership_policy import allows_multiple
    from .term_scope import get_active_semester
    semester = get_active_semester()
    multiple_events = {}
    for offset, (row_index, data, members) in enumerate(checked_rows):
        if 'PIT' not in data.get('level', '').upper():
            continue
        event = (data.get('current_defense_stage') or '').strip()
        if event not in multiple_events:
            multiple_events[event] = allows_multiple(semester, event)
        for other_index, other, other_members in checked_rows[:offset]:
            other_event = (other.get('current_defense_stage') or '').strip()
            same_program = ('PIT' in data.get('level', '').upper()) == ('PIT' in other.get('level', '').upper())
            same_context = not event or not other_event or event == other_event
            multiple = event and event == other_event and multiple_events[event]
            duplicate_name = bool(data['team_name'].strip()) and data['team_name'].strip().casefold() == other['team_name'].strip().casefold() and data.get('level') == other.get('level')
            if duplicate_name or (same_program and same_context and members.intersection(other_members) and not multiple):
                for current, conflict in ((row_index, other_index), (other_index, row_index)):
                    preview_rows[current]['batch_conflict'] = True
                    preview_rows[current]['issues'].append(
                        f'Conflicts with row {preview_rows[conflict]["row"]} ("{preview_rows[conflict]["team_name"]}"): '
                        + ('the team name is repeated in this file.' if duplicate_name else
                           'a student appears in both rosters. Resolve the roster or select distinct PIT events.'))
                    preview_rows[current]['ready'] = False
    # Shared sheet headers affect every team in a section. Check them during
    # review using the same authorization/enrollment rules as the transaction.
    from rest_framework.exceptions import PermissionDenied, ValidationError
    section_members = {}
    for row_index, data, members in checked_rows:
        if preview_rows[row_index]['ready']:
            section_members.setdefault((data.get('section', ''), data.get('year_level', '')), set()).update(members)
    metadata_results = {}
    for row_index, data, members in checked_rows:
        section = data.get('section', '')
        meta = section_metadata.get(section)
        if not meta:
            continue
        key = (section, data.get('year_level', ''))
        if key not in metadata_results:
            try:
                manager = validate_bulk_section_metadata(meta, user, semester, key[1], section,
                    member_ids=section_members.get(key, set()))
                metadata_results[key] = (manager, [])
            except (PermissionDenied, ValidationError) as exc:
                metadata_results[key] = (None, format_bulk_import_errors(exc.detail))
        manager, metadata_issues = metadata_results[key]
        if metadata_issues:
            preview_rows[row_index]['issues'].extend(metadata_issues)
            preview_rows[row_index]['metadata_issues'] = metadata_issues
            preview_rows[row_index]['ready'] = False
            preview_rows[row_index]['section_metadata_invalid'] = True
        elif manager and manager.pk in members and preview_rows[row_index]['ready']:
            # A manager may be joining this section in a later uploaded team.
            # Commit that team first so subsequent rows see its real membership.
            meta.setdefault('manager_member_rows', set()).add(row_index + 1)
    summary['ready'] = sum(row['ready'] for row in preview_rows)
    sections = {}
    for row in preview_rows:
        policy = row.get('concept_requirement')
        if policy:
            counts = sections.setdefault(row.get('section', ''), {'assigned': 0, 'proposals': 0})
            counts[policy['mode']] += 1
    summary['concept_sections'] = sections
    for source, result in zip(rows, preview_rows):
        if isinstance(source, dict) and source.get('group_key'):
            result['group_key'] = source['group_key']
    return preview_rows, summary


def collect_bulk_section_metadata(rows, *, import_section='', system_name='', project_manager=''):
    """Merge request/sheet headers once; conflicting headers must never win silently."""
    sections = {}

    def merge(section, system, manager):
        section = ' '.join(section.split())
        if not section or not (system or manager):
            return
        meta = sections.setdefault(section, {'system_name': '', 'project_manager': '', 'issues': []})
        for field, value in (('system_name', system), ('project_manager', manager)):
            if not value:
                continue
            if meta[field] and normalize_name(meta[field]) != normalize_name(value):
                issue = f'Use one {"System Name" if field == "system_name" else "Project Manager"} for section {section}.'
                if issue not in meta['issues']:
                    meta['issues'].append(issue)
            else:
                meta[field] = value

    merge(import_section, system_name, project_manager)
    for row in rows:
        if isinstance(row, dict):
            merge((row.get('section') or import_section).strip(),
                (row.get('system_name') or '').strip(), (row.get('project_manager') or '').strip())
    return sections


def validate_bulk_section_metadata(meta, user, semester, year, section, *, member_ids=()):
    """Validate section writes without side effects, including a joining manager."""
    from rest_framework.exceptions import ValidationError
    from user_management.academic_records.models import StudentAcademicRecord
    from .models import SectionAssignment
    from .section_access import require_section_write

    if meta.get('issues'):
        raise ValidationError(meta['issues'])
    if semester is None:
        raise ValidationError('No active semester is configured.')
    if len(meta['system_name']) > 255:
        raise ValidationError({'system_name': 'System Name must be at most 255 characters.'})
    existing = SectionAssignment.objects.filter(semester=semester, section=section).select_related('project_manager').first()
    manager = existing.project_manager if existing else None
    if meta['project_manager']:
        manager, error = resolve_user_by_full_name(meta['project_manager'], role='student', field_label='Project Manager')
        if error:
            raise ValidationError({'project_manager': error})
    if existing:
        require_section_write(user, semester, existing.year_level, existing.section)
    require_section_write(user, semester, year, section)
    if manager:
        # Saving a validated team establishes its membership and section in the
        # same transaction. Allow that prospective membership only in this year.
        joining = manager.pk in member_ids and StudentAcademicRecord.objects.filter(
            student=manager, semester=semester, year_level=year).exists()
        try:
            require_section_write(user, semester, year, section, None if joining and manager.is_active else manager)
        except ValidationError as exc:
            if isinstance(exc.detail, dict) and 'project_manager_id' in exc.detail:
                raise ValidationError({'project_manager':
                    f'Project Manager "{display_name(manager)}" must be an active student enrolled in '
                    f'{section}, {year}, in the active semester, or a member of a valid team being imported into this section. '
                    'Choose an eligible manager or correct the enrollment before importing.'}) from exc
            raise
    return manager


def format_bulk_import_errors(errors):
    """Turn serializer/API error payloads into human-readable strings."""
    if isinstance(errors, (list, tuple)):
        return [line for item in errors for line in format_bulk_import_errors(item)]
    if isinstance(errors, dict):
        lines = []
        for field, messages in errors.items():
            prefix = '' if field == 'non_field_errors' else f'{field}: '
            if isinstance(messages, (list, tuple)):
                for item in messages:
                    if isinstance(item, dict):
                        lines.extend(format_bulk_import_errors(item))
                    else:
                        lines.append(f'{prefix}{item}')
            elif isinstance(messages, dict):
                lines.extend(format_bulk_import_errors(messages))
            else:
                lines.append(f'{prefix}{messages}')
        return lines
    return [str(errors)]



def build_team_payload_from_row(result, user=None):
    data = result['data']
    member_ref_map = result['member_ref_map']
    leader = result['leader']
    adviser = result['adviser']
    pit_row = is_pit_bulk_row(data, user)

    from uuid import uuid4
    return {
        'name': data['team_name'] or f'Unnamed team {uuid4().hex}',
        'project_title': data.get('project_title') or '',
        'level': data['level'],
        'year_level': data.get('year_level') or '',
        'section': data.get('section') or '',
        'member_ids': [member_ref_map[item] for item in data['member_ids'] if item in member_ref_map],
        'leader_id': leader.id if leader else None,
        'adviser_id': None if pit_row else (adviser.id if adviser else None),
        'current_defense_stage': data.get('current_defense_stage') or None,
    }



