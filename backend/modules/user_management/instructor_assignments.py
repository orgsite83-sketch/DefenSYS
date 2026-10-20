"""Audited, atomic management of current PIT section assignments."""
from django.contrib.auth import get_user_model
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError

from academic_period_management.models import Semester
from academic_period_management.services import active_semester
from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from student_teams.team_levels import is_capstone_scope
from .models import SectionInstructorAssignment


class AssignmentChanged(APIException):
    status_code = 409
    default_detail = 'This assignment is no longer active. Refresh before changing its instructor.'


def _admin(actor):
    return actor.is_superuser or actor.role == 'admin'


def _current_period(actor, year, assignment=None):
    period = active_semester()
    if not period:
        raise ValidationError('No active semester is configured.')
    if not _admin(actor) and year != (actor.pit_lead_year or '').strip():
        raise PermissionDenied('This assignment is outside your PIT scope.')
    if assignment and assignment.semester_id != period.pk:
        raise PermissionDenied('Historical instructor assignments are read-only.')
    if year not in ('1st Year', '2nd Year', '3rd Year') or is_capstone_scope(year, period):
        raise ValidationError({'year_level': 'Section instructors can only be managed for the active PIT cohort.'})
    # Serialize replacements within the term, including a swap to an existing
    # assignment. Never deactivate the old instructor in a separate request.
    return Semester.objects.select_for_update().get(pk=period.pk)


def _faculty(value):
    try:
        if isinstance(value, bool):
            raise ValueError
        pk = int(value)
    except (TypeError, ValueError):
        raise ValidationError({'faculty_id': 'Select an active faculty user.'})
    user = get_user_model().objects.filter(pk=pk, role__in=['faculty', 'admin'], is_active=True).first()
    if not user:
        raise ValidationError({'faculty_id': 'Select an active faculty user.'})
    return user


def _values(assignment):
    return {'assignment_id': assignment.pk, 'faculty_id': assignment.faculty_id,
        'semester_id': assignment.semester_id, 'scope': 'pit', 'year_level': assignment.year_level,
        'section': assignment.section, 'is_active': assignment.is_active}


def _audit(actor, action, assignment, old, *, request=None, reason='', **extra):
    if not isinstance(reason, str):
        raise ValidationError({'reason': 'A reason must be text.'})
    log_high_impact_action(category=SystemAuditLog.CATEGORY_USER_MANAGEMENT,
        action=f'pit_instructor.{action}', target=assignment, actor=actor, request=request,
        reason=reason.strip() or f'Section instructor {action} for {assignment.section}.',
        old_values=old, new_values={**_values(assignment), **extra}, strict=True)


@transaction.atomic
def assign_instructor(actor, faculty_id, year, section, *, request=None):
    period = _current_period(actor, year)
    faculty = _faculty(faculty_id)
    section = ' '.join((section or '').strip().split())
    if not section:
        raise ValidationError({'section': 'Section is required.'})
    assignment = SectionInstructorAssignment.objects.select_for_update().filter(
        faculty=faculty, semester=period, year_level=year, section=section).first()
    old = _values(assignment) if assignment else {}
    if assignment and assignment.is_active:
        return assignment
    if assignment:
        assignment.is_active = True
        assignment.assigned_by = actor
        assignment.save(update_fields=['is_active', 'assigned_by', 'updated_at'])
    else:
        assignment = SectionInstructorAssignment.objects.create(faculty=faculty, semester=period,
            year_level=year, section=section, assigned_by=actor)
    _audit(actor, 'restore' if old else 'assign', assignment, old, request=request)
    return assignment


@transaction.atomic
def update_instructor_assignment(actor, assignment_id, changes, *, request=None):
    original = get_object_or_404(SectionInstructorAssignment, pk=assignment_id)
    _current_period(actor, original.year_level, original)
    assignment = SectionInstructorAssignment.objects.select_for_update().get(pk=assignment_id)
    old = _values(assignment)
    if 'faculty_id' in changes or 'faculty' in changes:
        if 'is_active' in changes or 'section' in changes:
            raise ValidationError('Change the instructor separately from the section or assignment status.')
        if not assignment.is_active:
            raise AssignmentChanged()
        faculty = _faculty(changes.get('faculty_id', changes.get('faculty')))
        if faculty.pk == assignment.faculty_id:
            return assignment, None
        replacement = SectionInstructorAssignment.objects.select_for_update().filter(
            faculty=faculty, semester_id=assignment.semester_id,
            year_level=assignment.year_level, section=assignment.section).first()
        replacement_before = _values(replacement) if replacement else {}
        assignment.is_active = False
        assignment.save(update_fields=['is_active', 'updated_at'])
        if replacement:
            replacement.is_active = True
            replacement.assigned_by = actor
            replacement.save(update_fields=['is_active', 'assigned_by', 'updated_at'])
        else:
            replacement = SectionInstructorAssignment.objects.create(faculty=faculty,
                semester_id=assignment.semester_id, year_level=assignment.year_level,
                section=assignment.section, assigned_by=actor)
        _audit(actor, 'replace', replacement, {**old, 'replacement': replacement_before}, request=request,
            reason=changes.get('reason', ''), replaced_assignment_id=assignment.pk,
            previous_faculty_id=assignment.faculty_id)
        return replacement, assignment
    if not {'is_active', 'section'}.intersection(changes):
        raise ValidationError('Choose an assignment change.')
    if 'is_active' in changes:
        if not isinstance(changes['is_active'], bool):
            raise ValidationError({'is_active': 'Use true or false.'})
        if changes['is_active']:
            _faculty(assignment.faculty_id)
        assignment.is_active = changes['is_active']
    if 'section' in changes:
        if not _admin(actor):
            raise PermissionDenied('Only administrators can move an assignment to another section.')
        section = changes['section']
        if not isinstance(section, str) or not section.strip():
            raise ValidationError({'section': 'Section is required.'})
        assignment.section = ' '.join(section.strip().split())
        if SectionInstructorAssignment.objects.filter(faculty_id=assignment.faculty_id,
                semester_id=assignment.semester_id, year_level=assignment.year_level,
                section=assignment.section).exclude(pk=assignment.pk).exists():
            raise ValidationError({'section': 'This instructor already has an assignment for that section.'})
    if _values(assignment) != old:
        assignment.assigned_by = actor
        assignment.save(update_fields=['is_active', 'section', 'assigned_by', 'updated_at'])
        action = 'remove' if not assignment.is_active else 'restore' if not old['is_active'] else 'change'
        _audit(actor, action, assignment, old, request=request, reason=changes.get('reason', ''))
    return assignment, None
