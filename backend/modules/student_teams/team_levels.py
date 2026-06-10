from academic_period_management.models import Semester
from user_management.academic_records.models import StudentAcademicRecord

from .models import StudentTeam

YEAR_LEVEL_CHOICES = ('1st Year', '2nd Year', '3rd Year', '4th Year')
DEFAULT_CAPSTONE_YEAR = '3rd Year'


def level_year(level):
    if level.startswith('1st Year'):
        return '1st Year'
    if level.startswith('2nd Year'):
        return '2nd Year'
    if level.startswith('3rd Year'):
        return '3rd Year'
    if level.startswith('4th Year'):
        return '4th Year'
    return ''


def user_is_admin(user):
    return bool(
        user
        and user.is_authenticated
        and (user.is_superuser or getattr(user, 'role', None) == 'admin')
    )


def user_is_pit_lead_only(user):
    return bool(
        user
        and user.is_authenticated
        and getattr(user, 'is_pit_lead', False)
        and not user_is_admin(user)
    )


def levels_for_user(user):
    all_levels = [choice[0] for choice in StudentTeam.LEVEL_CHOICES]
    if user_is_admin(user):
        return [level for level in all_levels if 'Capstone' in level]
    if user_is_pit_lead_only(user):
        return [level for level in all_levels if 'PIT' in level]
    return all_levels


def normalize_year_level(value):
    raw = (value or '').strip()
    if not raw:
        return ''
    lowered = raw.casefold()
    for year in YEAR_LEVEL_CHOICES:
        if lowered.startswith(year.casefold()):
            return year
    return raw


def _active_semester(semester=None):
    if semester is not None:
        return semester
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def _year_levels_for_students(member_ids, semester):
    if not member_ids:
        return []

    active = _active_semester(semester)
    if active is None:
        return []

    years = []
    for student_id in member_ids:
        record = (
            StudentAcademicRecord.objects.filter(student_id=student_id, semester=active)
            .order_by('-created_at', '-id')
            .first()
        )
        if record and record.year_level:
            normalized = normalize_year_level(record.year_level)
            if normalized:
                years.append(normalized)
    return years


def _sections_for_students(member_ids, semester):
    if not member_ids:
        return []

    active = _active_semester(semester)
    if active is None:
        return []

    sections = []
    for student_id in member_ids:
        record = (
            StudentAcademicRecord.objects.filter(student_id=student_id, semester=active)
            .order_by('-created_at', '-id')
            .first()
        )
        if record and record.section:
            section = ' '.join(record.section.strip().split())
            if section:
                sections.append(section)
    return sections


def infer_year_level_from_members(member_ids, semester=None, *, leader_id=None):
    """
    Infer capstone cohort year from member academic records on the active semester.
    Returns (year_level, issues). Rejects mixed cohorts; prefers leader's year when valid.
    Empty member_ids returns (DEFAULT_CAPSTONE_YEAR, []).
    """
    member_ids = [int(item) for item in (member_ids or []) if item]
    if not member_ids:
        return DEFAULT_CAPSTONE_YEAR, []

    years = _year_levels_for_students(member_ids, semester)
    if not years:
        return DEFAULT_CAPSTONE_YEAR, []

    unique = sorted(set(years))
    if len(unique) > 1:
        return '', [
            'Team members belong to different year levels '
            f'({", ".join(unique)}). Use students from the same cohort.'
        ]

    if leader_id:
        leader_years = _year_levels_for_students([leader_id], semester)
        if leader_years:
            return leader_years[0], []

    return unique[0], []


def infer_section_from_members(member_ids, semester=None, *, required=False):
    member_ids = [int(item) for item in (member_ids or []) if item]
    if not member_ids:
        return '', []

    sections = _sections_for_students(member_ids, semester)
    if not sections:
        if required:
            return '', ['Team members do not have a section in their academic records.']
        return '', []

    unique = sorted(set(sections))
    if len(unique) > 1:
        return '', [
            'Team members belong to different sections '
            f'({", ".join(unique)}). Use students from the same section.'
        ]

    return unique[0], []


def resolve_team_level(*, user, year_level='', level='', member_ids=None, semester=None, leader_id=None):
    """
    Derive canonical StudentTeam.level from role + year_level.
    Admins: "{year} Capstone". PIT Leads: "{pit_lead_year or year} PIT".
    """
    explicit_level = (level or '').strip()
    year = normalize_year_level(year_level)

    if user_is_admin(user):
        if explicit_level and 'PIT' in explicit_level.upper():
            raise ValueError('Admins can only manage capstone teams.')
        if explicit_level and 'CAPSTONE' in explicit_level.upper():
            resolved = explicit_level
        else:
            if not year:
                year, issues = infer_year_level_from_members(
                    member_ids,
                    semester,
                    leader_id=leader_id,
                )
                if issues:
                    raise ValueError(issues[0])
            resolved = f'{year} Capstone'

    elif user_is_pit_lead_only(user):
        if explicit_level and 'CAPSTONE' in explicit_level.upper():
            raise ValueError('PIT Leads can only manage PIT teams.')
        pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
        if explicit_level and 'PIT' in explicit_level.upper():
            level_year_val = level_year(explicit_level)
            if pit_year and level_year_val and level_year_val != pit_year:
                raise ValueError(
                    f'Cannot create {explicit_level} team: '
                    f'your PIT scope is {pit_year}.'
                )
            resolved = explicit_level
        else:
            year = year or pit_year
            if not year:
                raise ValueError('year_level or pit_lead_year is required for PIT teams.')
            if pit_year and year != pit_year:
                raise ValueError(
                    f'Cannot create {year} PIT team: '
                    f'your PIT scope is {pit_year}.'
                )
            resolved = f'{year} PIT'

    else:
        if explicit_level:
            resolved = explicit_level
        elif year:
            resolved = f'{year} Capstone'
        else:
            raise ValueError('level or year_level is required.')

    valid_levels = [choice[0] for choice in StudentTeam.LEVEL_CHOICES]
    if resolved not in valid_levels:
        raise ValueError(f"'{resolved}' is not a valid team program level.")
    return resolved


def _normalize_csv_columns(columns):
    return {
        (column or '').strip().lower().replace(' ', '_')
        for column in (columns or [])
    }


def prepare_bulk_row(
    row,
    user,
    *,
    member_user_ids=None,
    leader_user_id=None,
    semester=None,
    check_template=False,
    csv_columns=None,
    section_import=False,
    import_section='',
):
    """Normalize CSV row level/year_level for the requesting user."""
    is_admin = user_is_admin(user)
    is_pit_lead = user_is_pit_lead_only(user)
    section_import = bool(section_import)

    if check_template:
        # Use explicit CSV columns when available; fall back to row keys for backwards compat
        columns_to_check = set(csv_columns) if csv_columns else set(row.keys())
        normalized_columns = _normalize_csv_columns(columns_to_check)
        pit_template = {'team_name', 'project_title', 'member_ids', 'leader_id'}
        if is_pit_lead or (is_admin and section_import):
            if normalized_columns & {'adviser_id', 'year_level'}:
                return None, [
                    "Wrong Template: PIT import templates should not contain 'adviser_id' or 'year_level' columns."
                ]
            if not pit_template.issubset(normalized_columns):
                return None, [
                    "Wrong Template: PIT import templates must contain 'team_name', 'project_title', 'member_ids', and 'leader_id' columns."
                ]
        elif is_admin:
            is_client_template = 'team_name' in normalized_columns and (
                'team_members' in normalized_columns or 'members' in normalized_columns
            )
            is_defensys_template = 'adviser_id' in normalized_columns and 'year_level' in normalized_columns
            if not (is_client_template or is_defensys_template):
                return None, [
                    "Wrong Template: Capstone import templates must contain 'year_level' and 'adviser_id' columns (or 'Team Name' and 'Team Members' for client format)."
                ]

    data = dict(row)
    if section_import and is_admin:
        year = normalize_year_level(data.get('year_level', '')) or '2nd Year'
        data['year_level'] = year
        data['level'] = f'{year} PIT'
        section = ' '.join((import_section or data.get('section') or '').strip().split())
        if section:
            data['section'] = section
        return data, []
    explicit_year = normalize_year_level(data.get('year_level', ''))

    if is_admin:
        if member_user_ids:
            inferred, issues = infer_year_level_from_members(
                member_user_ids,
                semester,
                leader_id=leader_user_id,
            )
            if issues:
                return None, issues
            data['year_level'] = inferred
        elif explicit_year:
            data['year_level'] = explicit_year
        else:
            data['year_level'] = DEFAULT_CAPSTONE_YEAR
    elif user_is_pit_lead_only(user):
        if member_user_ids:
            inferred, issues = infer_year_level_from_members(
                member_user_ids,
                semester,
                leader_id=leader_user_id,
            )
            if issues:
                return None, issues
            pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
            if pit_year and inferred != pit_year:
                return None, [
                    f'Students are enrolled in {inferred} but your PIT scope is {pit_year}.'
                ]
            data['year_level'] = inferred
            section, section_issues = infer_section_from_members(
                member_user_ids,
                semester,
                required=False,
            )
            if section_issues:
                return None, section_issues
            if section:
                data['section'] = section
        elif explicit_year:
            data['year_level'] = explicit_year
        else:
            data['year_level'] = (getattr(user, 'pit_lead_year', None) or '').strip()
    elif explicit_year:
        data['year_level'] = explicit_year

    try:
        data['level'] = resolve_team_level(
            user=user,
            year_level=data.get('year_level', ''),
            level=data.get('level', ''),
            member_ids=member_user_ids,
            semester=semester,
            leader_id=leader_user_id,
        )
    except ValueError as exc:
        return None, [str(exc)]
    data['year_level'] = level_year(data['level'])
    return data, []


def program_label_for_row(data, user):
    level = (data.get('level') or '').strip()
    year = normalize_year_level(data.get('year_level', '')) or level_year(level)
    if user_is_pit_lead_only(user):
        return f'{year} PIT' if year else 'PIT'
    if user_is_admin(user):
        return f'Capstone · {year}' if year else 'Capstone'
    return level or ''
