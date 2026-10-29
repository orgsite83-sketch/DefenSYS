"""Year/term authorization for legacy section routes, including empty sections."""
from django.db.models import Q
from rest_framework.exceptions import PermissionDenied, ValidationError
from authentication_access_control.scopes import is_admin_user, is_pit_lead_only
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import SectionInstructorAssignment
from .models import SectionAssignment, StudentTeam
from .team_levels import is_capstone_scope, YEAR_LEVEL_CHOICES


def sections_for(user):
    sections = SectionAssignment.objects.select_related('semester')
    if is_admin_user(user):
        return sections
    allowed = Q(pk__in=[])
    if user.role == 'faculty':
        if is_pit_lead_only(user) and user.pit_lead_year:
            pit = Q(year_level__in=['1st Year', '2nd Year']) | (Q(year_level='3rd Year') & ~Q(semester__label='2nd Semester'))
            allowed |= Q(year_level=user.pit_lead_year) & pit
        for term, year, section in SectionInstructorAssignment.objects.filter(faculty=user, is_active=True).values_list('semester_id', 'year_level', 'section'):
            allowed |= Q(semester_id=term, year_level=year, section=section)
        teams = StudentTeam.objects.filter(adviser=user)
    elif user.role == 'student':
        teams = StudentTeam.objects.filter(memberships__student=user)
    else:
        teams = StudentTeam.objects.none()
    for term, year, section in teams.values_list('semester_id', 'year_level', 'section').distinct():
        allowed |= Q(semester_id=term, year_level=year, section=section)
    return sections.filter(allowed).distinct()


def require_section_write(user, semester, year, section, pm=None):
    if year not in YEAR_LEVEL_CHOICES or not section:
        raise ValidationError('Select a valid year and section.')
    if not semester.is_active:
        raise PermissionDenied('Historical sections are read-only.')
    if is_capstone_scope(year, semester):
        from .section_years import capstone_section_issue
        issue = capstone_section_issue(section, year)
        if issue:
            raise ValidationError({'section': issue})
    if not is_admin_user(user):
        if is_capstone_scope(year, semester):
            raise PermissionDenied('Only Admin can manage Capstone sections.')
        if is_pit_lead_only(user):
            if not user.pit_lead_year or year != user.pit_lead_year:
                raise PermissionDenied('This section is outside your PIT year scope.')
        elif not SectionInstructorAssignment.objects.filter(faculty=user, semester=semester,
                year_level=year, section=section, is_active=True).exists():
            raise PermissionDenied('An assigned PIT section is required.')
        if StudentTeam.objects.filter(semester=semester, section=section).exclude(level__icontains='PIT').exists():
            raise PermissionDenied('This section contains Capstone teams.')
    if StudentTeam.objects.filter(semester=semester, section=section).exclude(year_level=year).exists():
        raise ValidationError('This section contains teams from another year.')
    if StudentAcademicRecord.objects.filter(semester=semester, section=section).exclude(year_level=year).exists():
        raise ValidationError('This section contains enrollment records from another year.')
    if pm:
        enrolled = StudentAcademicRecord.objects.filter(student=pm, semester=semester, year_level=year, section=section).exists()
        member = StudentTeam.objects.filter(semester=semester, year_level=year, section=section, memberships__student=pm).exists()
        if not pm.is_active or not (enrolled or member):
            raise ValidationError({'project_manager_id': 'Choose an active student enrolled in this section.'})


def audit_section(request, assignment, action, old=None):
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    values = {'semester_id': assignment.semester_id, 'year_level': assignment.year_level,
        'section': assignment.section, 'system_name': assignment.system_name,
        'project_manager_id': assignment.project_manager_id,
        'scope': 'capstone' if is_capstone_scope(assignment.year_level, assignment.semester) else 'pit'}
    log_high_impact_action(category=SystemAuditLog.CATEGORY_STUDENT_TEAMS,
        action=action, target=assignment, request=request, old_values=old or {},
        new_values=values if action != 'section_assignment.delete' else {**values, 'deleted': True}, strict=True)
