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
            return explicit_level
        if not year:
            year, issues = infer_year_level_from_members(
                member_ids,
                semester,
                leader_id=leader_id,
            )
            if issues:
                raise ValueError(issues[0])
        return f'{year} Capstone'

    if user_is_pit_lead_only(user):
        if explicit_level and 'CAPSTONE' in explicit_level.upper():
            raise ValueError('PIT Leads can only manage PIT teams.')
        if explicit_level and 'PIT' in explicit_level.upper():
            return explicit_level
        year = year or (getattr(user, 'pit_lead_year', None) or '').strip()
        if not year:
            raise ValueError('year_level or pit_lead_year is required for PIT teams.')
        return f'{year} PIT'

    if explicit_level:
        return explicit_level
    if year:
        return f'{year} Capstone'
    raise ValueError('level or year_level is required.')


def prepare_bulk_row(row, user, *, member_user_ids=None, leader_user_id=None, semester=None):
    """Normalize CSV row level/year_level for the requesting user."""
    data = dict(row)
    explicit_year = normalize_year_level(data.get('year_level', ''))

    if user_is_admin(user):
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
