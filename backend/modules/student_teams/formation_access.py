"""Creation permissions use current instructor assignments, including empty sections."""
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import BasePermission

from user_management.models import SectionInstructorAssignment
from .team_levels import user_is_admin, user_is_pit_lead_only, is_capstone_scope
from .term_scope import get_active_semester


def instructor_sections(user, semester, year=None):
    assignments = SectionInstructorAssignment.objects.filter(
        faculty=user, semester=semester, is_active=True)
    if year:
        assignments = assignments.filter(year_level=year)
    # Capstone rosters are finalized by the school and imported by Admin.
    # An old instructor assignment never creates Capstone formation authority.
    assignments = assignments.exclude(year_level='4th Year')
    if is_capstone_scope('3rd Year', semester):
        assignments = assignments.exclude(year_level='3rd Year')
    return assignments


def is_manager(user):
    return user_is_admin(user) or user_is_pit_lead_only(user)


def allowed_sections(user, semester, year):
    if is_manager(user):
        return None
    return set(instructor_sections(user, semester, year).values_list('section', flat=True))


def require_formation_scope(user, semester, level, section=None):
    year = level.rsplit(' ', 1)[0]
    if user_is_admin(user):
        return
    if user_is_pit_lead_only(user):
        if 'PIT' not in level or year != (user.pit_lead_year or '').strip():
            raise PermissionDenied('This roster is outside your assigned PIT year level.')
        return
    sections = allowed_sections(user, semester, year)
    if getattr(user, 'role', None) != 'faculty' or not sections:
        raise PermissionDenied('An active instructor assignment is required to form teams.')
    expected = f'{year} {"Capstone" if is_capstone_scope(year, semester) else "PIT"}'
    if level != expected:
        raise PermissionDenied('This program is outside your instructor assignment.')
    if section is not None and section not in sections:
        raise PermissionDenied('Choose one of your assigned sections.')


def require_generation_scope(user, semester, level, section=None):
    """Generation belongs to assigned PIT instructors, even for multi-role faculty."""
    year = level.rsplit(' ', 1)[0]
    sections = set(instructor_sections(user, semester, year).values_list('section', flat=True))
    if getattr(user, 'role', None) != 'faculty' or 'PIT' not in level or not sections:
        raise PermissionDenied('Only an assigned PIT instructor can generate teams.')
    if section is not None and section not in sections:
        raise PermissionDenied('Choose one of your assigned PIT sections.')


class CanGenerateTeams(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.role == 'faculty' and
                    instructor_sections(user, get_active_semester()).exists())


class CanFormTeams(BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and (
            is_manager(user) or (user.role == 'faculty' and
                instructor_sections(user, get_active_semester()).exists())))


def check_member_sections(user, semester, level, section, member_ids, *, importing=False):
    """A team label never grants access to another instructor's students."""
    from user_management.academic_records.models import StudentAcademicRecord
    require_formation_scope(user, semester, level, section if section else None)
    records = list(StudentAcademicRecord.objects.filter(
        semester=semester, student_id__in=member_ids))
    year = level.rsplit(' ', 1)[0]
    if len(records) != len(set(member_ids)) or any(r.year_level != year for r in records):
        raise ValidationError('Every member must be enrolled in the selected year and active semester.')
    permitted = allowed_sections(user, semester, year)
    if permitted is not None:
        if any(r.section and r.section.upper() != 'BSIT' and r.section not in permitted for r in records):
            raise PermissionDenied('Some students belong to another instructor\'s section. Ask your lead to correct their enrollment.')
        if not importing and any(r.section not in permitted for r in records):
            raise PermissionDenied('Assign students to your section before generating teams.')
