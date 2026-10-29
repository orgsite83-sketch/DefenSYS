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
        return False, Semester.PHASE_CAPSTONE_2
    return False, Semester.PHASE_NONE


def derive_capstone_program_phase(semester):
    """
    Calendar-driven capstone phase (no admin toggle).

    - 2nd Semester: Capstone 1 intake (3rd Year, 2nd Sem).
    - 1st Semester: Capstone 2 continuation (4th Year, 1st Sem).
    """
    if semester.label == Semester.SECOND:
        return Semester.PHASE_CAPSTONE_1
    if semester.label == Semester.FIRST:
        return Semester.PHASE_CAPSTONE_2
    return Semester.PHASE_NONE



def derive_capstone_team_creation_enabled(semester):
    """New participation starts only during a regular Capstone 1 intake."""
    phase = derive_capstone_program_phase(semester)
    return phase == Semester.PHASE_CAPSTONE_1


def normalize_capstone_flags(semester):
    """Derive and persist capstone phase from term and roster data."""
    semester.capstone_program_phase = derive_capstone_program_phase(semester)
    return ['capstone_program_phase']


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
            'can_create_capstone_teams': False,
            'message': 'Capstone 2 uses eligible teams continued at semester activation. New participation starts in a regular Capstone 1 intake.',
        }

    if semester.capstone_team_creation_enabled:
        if phase == Semester.PHASE_CAPSTONE_1:
            return {
                'mode': MODE_CAPSTONE_1_INTAKE,
                'can_create_capstone_teams': True,
                'message': (
                    'Capstone 1 intake: create new capstone teams for this term '
                    '(3rd Year, 2nd Semester).'
                ),
            }
        else:
            return {
                'mode': MODE_CAPSTONE_1_INTAKE,
                'can_create_capstone_teams': True,
                'message': 'Capstone team creation is enabled.',
            }

    return {
        'mode': MODE_OFF,
        'can_create_capstone_teams': False,
        'message': 'Capstone team creation is not open for this term.',
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
