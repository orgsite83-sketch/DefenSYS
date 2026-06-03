"""Active semester vs historical term scoping for teams and PIT cohorts."""

from academic_period_management.models import Semester
from user_management.academic_records.models import StudentAcademicRecord

from .team_levels import normalize_year_level, user_is_admin, user_is_pit_lead_only

TERM_ACTIVE = 'active'
TERM_HISTORICAL = 'historical'

PIT_MODE_ACTIVE = 'active'
PIT_MODE_AUDIT = 'audit'

AUDIT_MESSAGE = (
    'Capstone intake term — your PIT roster for this year is historical only. '
    'View past teams and students; new PIT assignments are closed for this term.'
)

HISTORICAL_TEAM_MESSAGE = (
    'This team belongs to a prior term and is read-only while another semester is active.'
)


def get_active_semester():
    return Semester.objects.select_related('school_year').filter(is_active=True).first()


def term_status_for_team(team, active=None):
    active = active if active is not None else get_active_semester()
    if active is None:
        return TERM_HISTORICAL
    if team.semester_id == active.id:
        return TERM_ACTIVE
    return TERM_HISTORICAL


def pit_lead_operating_mode(user, active=None):
    """
    PIT Lead roster mode on the active term.

    audit — capstone intake on 3rd Year 2nd Sem: no active PIT roster (history only).
    active — normal PIT management on the active term.
    """
    if not user_is_pit_lead_only(user):
        return PIT_MODE_ACTIVE

    active = active if active is not None else get_active_semester()
    if active is None:
        return PIT_MODE_AUDIT

    pit_year = normalize_year_level(getattr(user, 'pit_lead_year', None) or '')
    if (
        pit_year == StudentAcademicRecord.THIRD_YEAR
        and active.label == Semester.SECOND
        and active.capstone_program_phase == Semester.PHASE_CAPSTONE_1
    ):
        return PIT_MODE_AUDIT

    return PIT_MODE_ACTIVE


def pit_lead_operating_message(user, active=None):
    if pit_lead_operating_mode(user, active=active) == PIT_MODE_AUDIT:
        return AUDIT_MESSAGE
    return ''


def team_is_editable(user, team, active=None):
    if not user or not getattr(user, 'is_authenticated', False):
        return False

    if term_status_for_team(team, active=active) != TERM_ACTIVE:
        return False

    if user_is_admin(user):
        return 'Capstone' in (team.level or '')

    if user_is_pit_lead_only(user):
        if pit_lead_operating_mode(user, active=active) == PIT_MODE_AUDIT:
            return False
        pit_year = normalize_year_level(getattr(user, 'pit_lead_year', None) or '')
        if 'PIT' not in (team.level or ''):
            return False
        return normalize_year_level(team.year_level) == pit_year

    if getattr(user, 'role', None) == 'faculty' and 'PIT' in (team.level or ''):
        from user_management.models import PitInstructorAssignment

        return PitInstructorAssignment.objects.filter(
            faculty=user,
            semester=team.semester,
            year_level=normalize_year_level(team.year_level),
            section=team.section,
            is_active=True,
        ).exists()

    return False


def assert_team_writable(user, team, active=None):
    from rest_framework.exceptions import PermissionDenied

    if team_is_editable(user, team, active=active):
        return

    if term_status_for_team(team, active=active) == TERM_HISTORICAL:
        raise PermissionDenied(HISTORICAL_TEAM_MESSAGE)

    raise PermissionDenied('You do not have permission to modify this team.')


def assert_active_semester_for_create(user, semester, active=None):
    """Writes must target the currently active semester."""
    from rest_framework.exceptions import PermissionDenied, ValidationError

    active = active if active is not None else get_active_semester()
    if active is None:
        raise ValidationError({'semester_id': 'No active semester is configured.'})
    if semester.id != active.id:
        raise PermissionDenied('Teams can only be created or updated on the active semester.')

    if user_is_pit_lead_only(user) and pit_lead_operating_mode(user, active=active) == PIT_MODE_AUDIT:
        raise PermissionDenied(AUDIT_MESSAGE)


def apply_team_scope(queryset, scope='active', user=None):
    """
    scope: active (default) | history | all
    """
    active = get_active_semester()
    normalized = (scope or 'active').strip().lower()

    if normalized == 'all':
        if user and user_is_admin(user):
            return queryset
        normalized = 'active'

    if normalized == 'history':
        if active:
            return queryset.exclude(semester_id=active.id)
        return queryset

    if active:
        return queryset.filter(semester_id=active.id)
    return queryset.none()


def pit_roster_student_ids(active, *, pit_lead_year, historical=False):
    """Student IDs from academic records for PIT cohort."""
    if not active or not pit_lead_year:
        return []

    pit_year = normalize_year_level(pit_lead_year)
    if not pit_year:
        return []

    records = StudentAcademicRecord.objects.filter(year_level=pit_year)
    if historical:
        records = records.exclude(semester_id=active.id)
    else:
        records = records.filter(semester_id=active.id)

    return list(records.values_list('student_id', flat=True).distinct())


def term_scope_payload(user):
    """PIT scope metadata only; active_semester object comes from SemesterSerializer in options_payload."""
    active = get_active_semester()
    payload = {
        'active_semester_id': active.id if active else None,
    }
    if user_is_pit_lead_only(user):
        mode = pit_lead_operating_mode(user, active=active)
        payload['operating_mode'] = mode
        message = pit_lead_operating_message(user, active=active)
        if message:
            payload['operating_message'] = message
    return payload
