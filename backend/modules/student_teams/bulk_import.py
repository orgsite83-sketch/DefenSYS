from contextlib import contextmanager
from defensys_backend.person_names import name_encoding_issue
from contextvars import ContextVar
from django.contrib.auth import get_user_model

from .person_names import PersonNames, PersonNameIndex
from .models import StudentTeam, TeamMembership
from .serializers import BulkTeamRowSerializer, display_name
from .team_levels import prepare_bulk_row, program_label_for_row, user_is_pit_lead_only


User = get_user_model()
_import_names = ContextVar('team_import_names', default=None)


def participation_preview(student_ids):
    from .participation import roster_preview
    from .term_scope import get_active_semester
    return roster_preview(student_ids, get_active_semester())


@contextmanager
def import_user_lookup():
    """One indexed account projection per review, including nested lookups."""
    if _import_names.get() is not None:
        yield
        return
    token = _import_names.set(PersonNameIndex(User.objects.only(
        'id', 'username', 'first_name', 'last_name', 'role', 'is_active'), _person_names))
    try:
        yield
    finally:
        _import_names.reset(token)


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

_person_names = PersonNames(PREFIX_PATTERNS, SUFFIX_PATTERNS[:-2])
clean_person_name = _person_names.clean


def normalize_name(value):
    return ' '.join((value or '').strip().split()).casefold()


def _person_index():
    cached = _import_names.get()
    if cached is not None:
        return cached
    return PersonNameIndex(User.objects.only(
        'id', 'username', 'first_name', 'last_name', 'role', 'is_active'), _person_names)


def _users_matching_full_name(value, *, role=None):
    return list(_person_index().full_matches(value, role))


def reference_resolution(value, *, role=None, field='member_ids'):
    """Review metadata exposes no suggested accounts outside existing pickers."""
    result = _person_index().resolve(value, role)
    status = 'inactive' if result.user is not None and not result.user.is_active else result.status
    projection = {'field': field, 'reference': value, 'status': status,
                  'reference_key': _person_names.key(value), 'match_kind': result.kind}
    if result.user is not None:
        projection.update(username=result.user.username, name=display_name(result.user))
        if name_encoding_issue(result.user.first_name) or name_encoding_issue(result.user.last_name):
            projection['name_warning'] = 'Account name needs repair. Identity was selected by registered ID.'
    projection['review_state'] = ('eligibility_issue' if status == 'inactive' else 'matched' if status == 'matched' else 'encoding_problem'
        if status == 'encoding_problem' else 'needs_account' if status == 'not_found' else 'needs_confirmation')
    return projection


def team_reference_resolutions(data, *, pit=False):
    members = data.get('member_ids', [])
    if isinstance(members, str):
        members = members.split(';')
    if not isinstance(members, list):
        members = []
    references = [('member_ids', ref, 'student') for ref in members]
    references.append(('leader_id', data.get('leader_id', ''), 'student'))
    references.append(('project_manager', data.get('project_manager', ''), 'student'))
    if pit:
        references.append(('instructor_name', data.get('instructor_name', ''), ['faculty', 'admin']))
    else:
        references.append(('adviser_name', data.get('adviser_name') or data.get('adviser_id', ''),
                           ['faculty', 'admin']))
    return [reference_resolution(str(ref), role=role, field=field)
            for field, ref, role in references if ref]


def _resolution_error(raw, result, field_label):
    if result.status == 'encoding_problem':
        return f'{field_label} "{raw}": name encoding problem. Use an intact source or select the registered ID and review the damaged account name.'
    if result.status == 'ambiguous':
        kind = 'share the surname' if result.kind == 'surname' else 'match that name'
        return (f'{field_label} "{raw}": multiple users {kind}. '
                'Select the correct account or use its registered ID.')
    if result.status == 'selection_required':
        reason = {'middle_initial_conflict': 'the supplied middle initials conflict with registered name details',
                  'suffix_difference': 'generational suffix differs or is omitted',
                  'surname_variant': 'surname variant needs confirmation'}.get(result.kind, 'middle-name details need review')
        return (f'{field_label} "{raw}": {reason}. '
                'Review the account or use its registered ID.')
    return (f'{field_label} "{raw}": no user found with that name. '
            'Select an account or use its registered ID.')


def resolve_user_by_full_name(value, *, role=None, field_label='User'):
    """ID first, then safe name equivalence; uncertain identities require selection."""
    raw = (value or '').strip()
    result = _person_index().resolve(raw, role)
    if result.status == 'empty':
        return None, None
    if result.user is not None:
        if not result.user.is_active:
            return None, f'{field_label} "{raw}" is inactive.'
        return result.user, None
    return None, _resolution_error(raw, result, field_label)


def resolve_adviser(name_or_username):
    """Share person matching while retaining the existing adviser-status contract."""
    raw = (name_or_username or '').strip()
    index = _person_index()
    result = index.resolve(raw, ['faculty', 'admin'])
    if result.status == 'empty':
        return None, ADVISER_STATUS_NONE, ''
    if result.user is not None:
        user = result.user
        if not user.is_active:
            return None, ADVISER_STATUS_INACTIVE, display_name(user)
        return user, ADVISER_STATUS_VALID, display_name(user)
    other = index.resolve(raw)
    if other.user is not None and other.user.role not in ('faculty', 'admin'):
        return None, ADVISER_STATUS_NOT_ADVISER, display_name(other.user)
    return None, ADVISER_STATUS_USER_NOT_FOUND, ''


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


@import_user_lookup()
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
        resolution = _person_index().resolve(adviser_ref, ['faculty', 'admin'])
        if resolution.status in ('ambiguous', 'selection_required', 'encoding_problem'):
            issues.append(_resolution_error(adviser_ref, resolution, 'Adviser'))
        elif adviser_status == ADVISER_STATUS_USER_NOT_FOUND:
            issues.append(f'Adviser "{adviser_ref}" was not found.')
        elif adviser_status == ADVISER_STATUS_INACTIVE:
            issues.append(f'Adviser "{adviser_ref}" is inactive.')
        else:
            issues.append(f'User "{adviser_ref}" is not a faculty member.')

    member_ref_map = {}
    resolved_member_count = 0
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
            resolved_member_count += 1

    leader_ref = (data.get('leader_id') or '').strip()
    leader, leader_error = resolve_user_by_full_name(
        leader_ref,
        role='student',
        field_label='Leader',
    )
    if leader_error:
        if leader_ref not in data['member_ids']:
            issues.append(leader_error)
    elif leader is None and leader_ref:
        issues.append(f'Leader "{leader_ref}" must be a valid student user.')

    member_user_ids = set(member_ref_map.values())
    if len(member_user_ids) != resolved_member_count:
        issues.append('A student is listed more than once under different names or IDs. Keep each account once.')
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
            elif (data.get('section') or '').strip():
                from .term_scope import get_active_semester
                from .team_levels import normalize_year_level, level_year
                from user_management.instructor_assignments import require_instructor_slot
                from rest_framework.exceptions import ValidationError as InstructorConflict
                try:
                    require_instructor_slot(get_active_semester(),
                        normalize_year_level(data.get('year_level')) or level_year(data.get('level', '')),
                        ' '.join(data['section'].strip().split()), instructor.pk)
                except InstructorConflict as exc:
                    issues.append(str(exc.detail['section']))
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
    resolutions = team_reference_resolutions(data, pit=pit_row)
    warnings.extend(dict.fromkeys(r['name_warning'] for r in resolutions if r.get('name_warning')))
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
        'reference_resolutions': resolutions,
    }


@import_user_lookup()
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
            'reference_resolutions': result['reference_resolutions'],
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



