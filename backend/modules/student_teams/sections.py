"""Term-scoped section editing, shared by the section editor API."""

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from academic_period_management.models import Semester
from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.scopes import visible_teams_for
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import SectionInstructorAssignment

from .models import SectionAssignment, StudentTeam
from .serializers import SectionAssignmentSerializer, display_name
from .term_scope import assert_team_writable, get_active_semester


def section_context(user, team_id, *, lock=False):
    # Lock the semester before the teams so concurrent section edits serialize.
    team = get_object_or_404(visible_teams_for(user), pk=team_id)
    active = get_active_semester()
    assert_team_writable(user, team, active=active)
    if lock:
        Semester.objects.select_for_update().get(pk=team.semester_id)
        team.refresh_from_db()
        assert_team_writable(user, team, active=active)
    if not team.section.strip():
        raise ValidationError({'section': 'Assign a section on the team before editing its section details.'})

    teams = StudentTeam.objects.filter(semester_id=team.semester_id, section=team.section)
    if lock:
        teams = teams.select_for_update()
    teams = list(teams.order_by('pk'))
    for member_team in teams:
        assert_team_writable(user, member_team, active=active)
        if member_team.year_level != team.year_level:
            raise ValidationError({'section': 'This section contains multiple year levels. Correct the team sections first.'})

    records = StudentAcademicRecord.objects.filter(semester_id=team.semester_id, section=team.section)
    if records.exclude(year_level=team.year_level).exists() or SectionInstructorAssignment.objects.filter(
        semester_id=team.semester_id, section=team.section,
    ).exclude(year_level=team.year_level).exists():
        raise PermissionDenied('This section includes students outside the team year level.')
    member_ids = StudentTeam.objects.filter(pk__in=[item.pk for item in teams]).values_list('members__pk', flat=True)
    students = get_user_model().objects.filter(role='student', is_active=True).filter(
        Q(pk__in=member_ids) | Q(pk__in=records.values('student_id'))
    ).distinct().order_by('first_name', 'last_name', 'username')
    assignment = SectionAssignment.objects.filter(semester_id=team.semester_id, section=team.section)
    if lock:
        assignment = assignment.select_for_update()
    # Materialize candidates before a rename changes the record subquery.
    return team, teams, list(students), assignment.first()


def can_manage_concept_policies(user, team):
    return bool(user and (user.is_superuser or user.role == 'admin' or
                         (team.is_pit and getattr(user, 'is_pit_lead', False))))


def section_payload(team, teams, students, assignment, *, actor=None):
    from .section_concept_policies import policy_context_payload
    from user_management.serializers import SectionInstructorAssignmentSerializer
    details = SectionAssignmentSerializer(assignment).data if assignment else {
        'section': team.section,
        'semester_id': team.semester_id,
        'year_level': team.year_level,
        'system_name': '',
        'project_manager_id': None,
        'project_manager_name': None,
    }
    can_setup = bool(actor and (actor.is_superuser or actor.role == 'admin' or
        (team.is_pit and ((getattr(actor, 'is_pit_lead', False) and actor.pit_lead_year == team.year_level) or
            SectionInstructorAssignment.objects.filter(faculty=actor, semester=team.semester,
                year_level=team.year_level, section=team.section, is_active=True).exists()))))
    reviewers = get_user_model().objects.filter(role='faculty', is_active=True)
    if team.is_pit:
        reviewers = reviewers.filter(pk__in=SectionInstructorAssignment.objects.filter(
            semester=team.semester, year_level=team.year_level, section=team.section,
            is_active=True).values('faculty_id'))
    if actor and not (actor.is_superuser or actor.role == 'admin' or
            (team.is_pit and getattr(actor, 'is_pit_lead', False) and actor.pit_lead_year == team.year_level)):
        reviewers = reviewers.filter(pk__in=SectionInstructorAssignment.objects.filter(
            semester=team.semester, year_level=team.year_level, section=team.section,
            is_active=True).values('faculty_id'))
    roster_info = None
    if team.is_pit:
        from .pit_rosters import resolve
        resolved = resolve(team.semester_id, team.year_level)
        roster_info = resolved.get(team.section)
    can_manage_instructors = bool(team.is_pit and actor and (
        actor.is_superuser or actor.role == 'admin' or
        (getattr(actor, 'is_pit_lead', False) and actor.pit_lead_year == team.year_level)))
    instructors = SectionInstructorAssignment.objects.filter(
        semester_id=team.semester_id, year_level=team.year_level, section=team.section,
        is_active=True, faculty__is_active=True,
    ).select_related('faculty', 'semester__school_year', 'assigned_by') if team.is_pit else []
    return {
        **details,
        'is_pit': team.is_pit,
        'semester_label': team.semester.display_name,
        'team_count': len(teams),
        'student_count': len(students),
        'instructors': list(SectionInstructorAssignmentSerializer(instructors, many=True).data),
        'can_manage_instructors': can_manage_instructors,
        'instructor_options': [
            {'id': faculty.pk, 'name': display_name(faculty), 'email': faculty.email}
            for faculty in get_user_model().objects.filter(is_active=True, role__in=['faculty', 'admin'])
                .order_by('last_name', 'first_name', 'username')
        ] if can_manage_instructors else [],
        'roster_info': roster_info,
        'concept_contexts': policy_context_payload(team, teams, assignment),
        'can_manage_concepts': can_manage_concept_policies(actor, team),
        'can_setup_shared_system': can_setup,
        'can_manage_roster': can_setup,
        'system_reviewers': [{'id': r.pk, 'name': display_name(r)} for r in reviewers] if can_setup else [],
        'students': [
            {'id': student.pk, 'name': display_name(student), 'username': student.username}
            for student in students
        ],
    }


@transaction.atomic
def update_section(request, team_id, data):
    team, teams, students, assignment = section_context(request.user, team_id, lock=True)
    old_section = team.section
    if data['expected_section'] != old_section:
        raise ValidationError({'section': 'The section has changed. Close and reopen the editor to load its current details.'})
    new_section = data['section']
    pm_id = data.get('project_manager_id', assignment.project_manager_id if assignment else None)
    if pm_id is not None and not any(student.pk == pm_id for student in students):
        raise ValidationError({'project_manager_id': 'Choose an active student from this section.'})

    # Never merge two classes just because they now have the same display name.
    if new_section != old_section:
        for model in (StudentTeam, StudentAcademicRecord, SectionAssignment, SectionInstructorAssignment):
            if model.objects.filter(
                semester_id=team.semester_id, section__iexact=new_section,
            ).exclude(section=old_section).exists():
                raise ValidationError({'section': 'A section with this name already exists in this term. Choose a different name.'})

    old_values = {
        'section': old_section,
        'system_name': assignment.system_name if assignment else '',
        'project_manager_id': assignment.project_manager_id if assignment else None,
        'concept_policies': assignment.concept_policies if assignment else {},
        'team_concept_policies': {str(item.pk): item.concept_policies for item in teams},
    }
    if assignment is None:
        assignment = SectionAssignment(semester_id=team.semester_id, year_level=team.year_level)
    assignment.section = new_section
    assignment.system_name = data.get('system_name', assignment.system_name)
    assignment.project_manager_id = pm_id
    if data.get('concept_policy_changes'):
        if not can_manage_concept_policies(request.user, team):
            raise PermissionDenied('Only an administrator or the scoped PIT Lead can change concept requirements and assignments.')
        from .section_concept_policies import apply_policy_changes
        apply_policy_changes(team, teams, assignment, data['concept_policy_changes'],
            confirmed=data.get('confirm_concept_changes', False), actor=request.user)
    assignment.save()

    team_ids = [item.pk for item in teams]
    if new_section != old_section:
        now = timezone.now()
        StudentTeam.objects.filter(pk__in=team_ids).update(section=new_section, updated_at=now)
        StudentAcademicRecord.objects.filter(
            semester_id=team.semester_id, section=old_section,
        ).update(section=new_section)
        SectionInstructorAssignment.objects.filter(
            semester_id=team.semester_id, section=old_section,
        ).update(section=new_section, updated_at=now)
        for item in teams:
            item.section = new_section
        team.section = new_section

    scope_values = {
        **audit_scope_metadata(scope='pit' if team.is_pit else 'capstone', team=team),
        'semester_id': team.semester_id,
        'team_ids': team_ids,
    }
    log_high_impact_action(
        category=SystemAuditLog.CATEGORY_STUDENT_TEAMS, strict=True,
        action='section.update', target=assignment, request=request,
        old_values={**scope_values, **old_values},
        new_values={
            **scope_values, 'section': new_section, 'system_name': assignment.system_name,
            'project_manager_id': pm_id,
            'concept_policies': assignment.concept_policies,
            'team_concept_policies': {str(item.pk): item.concept_policies for item in teams},
        },
    )
    return section_payload(team, teams, students, assignment, actor=request.user)
