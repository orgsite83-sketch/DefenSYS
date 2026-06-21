"""Capstone operating window for admin team intake vs rollover continuation."""

from .models import Semester

MODE_OFF = 'off'
MODE_CAPSTONE_1_INTAKE = 'capstone_1_intake'
MODE_CAPSTONE_2_CONTINUE = 'capstone_2_continue'


def default_capstone_flags_for_label(label):
    """Suggested defaults when creating or activating a semester."""
    if label == Semester.SECOND:
        return True, Semester.PHASE_CAPSTONE_1
    if label == Semester.FIRST:
        return False, Semester.PHASE_NONE
    return False, Semester.PHASE_NONE


def _fourth_year_capstone_teams_on_semester(semester):
    if semester.pk is None:
        return False

    from student_teams.models import StudentTeam

    return StudentTeam.objects.filter(
        semester=semester,
        year_level='4th Year',
        level__icontains='Capstone',
    ).exists()


def _fourth_year_students_enrolled_on_semester(semester):
    if semester.pk is None:
        return False

    from user_management.academic_records.models import StudentAcademicRecord

    return StudentAcademicRecord.objects.filter(
        semester=semester,
        year_level=StudentAcademicRecord.FOURTH_YEAR,
    ).exists()


def derive_capstone_program_phase(semester):
    """
    Calendar-driven capstone phase (no admin toggle).

    - 2nd Semester: Capstone 1 intake (3rd Year, 2nd Sem).
    - 1st Semester: Capstone 2 when 4th-year capstone teams or enrolled students exist on this term.
    """
    if semester.label == Semester.SECOND:
        return Semester.PHASE_CAPSTONE_1
    if semester.label == Semester.FIRST:
        if (
            _fourth_year_capstone_teams_on_semester(semester)
            or _fourth_year_students_enrolled_on_semester(semester)
        ):
            return Semester.PHASE_CAPSTONE_2
        return Semester.PHASE_NONE
    return Semester.PHASE_NONE



def derive_capstone_team_creation_enabled(semester):
    """Team creation open during Capstone 1 intake and Capstone 2 continuation."""
    phase = derive_capstone_program_phase(semester)
    return phase in (Semester.PHASE_CAPSTONE_1, Semester.PHASE_CAPSTONE_2)


def normalize_capstone_flags(semester):
    """Derive and persist capstone phase + team-creation flag from term and roster data."""
    semester.capstone_program_phase = derive_capstone_program_phase(semester)
    semester.capstone_team_creation_enabled = derive_capstone_team_creation_enabled(
        semester
    )
    return ['capstone_program_phase', 'capstone_team_creation_enabled']


def sync_capstone_flags_after_rollover(active_semester, team_updates):
    """Refresh 1st Semester capstone flags after capstone teams are bumped."""
    if team_updates <= 0 or active_semester is None:
        return

    first_semester = active_semester.school_year.semesters.filter(
        label=Semester.FIRST,
    ).first()
    if first_semester is None:
        return

    normalize_capstone_flags(first_semester)
    first_semester.save(
        update_fields=['capstone_program_phase', 'capstone_team_creation_enabled'],
    )


def capstone_operating_mode(semester):
    """
    Resolve how the capstone admin should use Student Teams for the active term.

    Returns dict: mode, can_create_capstone_teams, message.
    """
    if semester is None:
        return {
            'mode': MODE_OFF,
            'can_create_capstone_teams': False,
            'message': 'No active semester is configured.',
        }

    phase = derive_capstone_program_phase(semester)

    if phase == Semester.PHASE_CAPSTONE_2:
        return {
            'mode': MODE_CAPSTONE_2_CONTINUE,
            'can_create_capstone_teams': True,
            'message': (
                'Capstone 2 term: teams carry over from the previous term. '
                'New teams can also be created or imported if needed.'
            ),
        }

    if derive_capstone_team_creation_enabled(semester):
        return {
            'mode': MODE_CAPSTONE_1_INTAKE,
            'can_create_capstone_teams': True,
            'message': (
                'Capstone 1 intake: create new capstone teams for this term '
                '(3rd Year, 2nd Semester).'
            ),
        }

    return {
        'mode': MODE_OFF,
        'can_create_capstone_teams': False,
        'message': (
            'Capstone team creation is not open for this term. '
            'Activate 2nd Semester for Capstone 1 intake, or run Student Records '
            'rollover before continuing in 1st Semester.'
        ),
    }


def capstone_mode_payload(semester):
    """API-friendly capstone window metadata."""
    info = capstone_operating_mode(semester)
    return {
        'capstone_mode': info['mode'],
        'can_create_capstone_teams': info['can_create_capstone_teams'],
        'capstone_mode_message': info['message'],
    }


def assert_capstone_team_creation_allowed(semester):
    """Raise ValueError when capstone team create/import is not permitted."""
    info = capstone_operating_mode(semester)
    if not info['can_create_capstone_teams']:
        raise ValueError(info['message'])
