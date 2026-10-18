"""Narrow a multi-role account to the authority of one requested workspace.

The empty workspace retains resource-level access for students and older clients.
Explicit unknown workspaces fail closed. Workspace selection never grants a role.
"""
from .scopes import (
    grade_records_for, is_admin_user,
    manageable_schedules_for, manageable_teams_for,
    section_instructor_section_filters, visible_schedules_for, visible_teams_for,
)


def workspace_teams_for(user, workspace=''):
    workspace = (workspace or '').strip()
    if workspace == 'operations':
        return manageable_teams_for(user)
    base = visible_teams_for(user)
    if not workspace:
        return base
    if workspace == 'adviser':
        return base.filter(level__icontains='Capstone', adviser=user)
    if workspace == 'instructor':
        return base.filter(section_instructor_section_filters(user), level__icontains='PIT')
    return base.none()


def workspace_schedules_for(user, workspace=''):
    workspace = (workspace or '').strip()
    if workspace == 'operations':
        return manageable_schedules_for(user)
    base = visible_schedules_for(user)
    if not workspace:
        return base
    if workspace == 'adviser':
        return base.filter(scope='capstone', team__adviser=user)
    if workspace == 'instructor':
        return base.filter(scope='pit', team__in=workspace_teams_for(user, workspace))
    if workspace == 'panelist':
        return base.filter(panel_assignments__panelist=user).distinct()
    if workspace == 'documenter':
        return base.filter(scope='capstone', documenter=user)
    return base.none()


def workspace_grades_for(user, workspace='', *, include_previous_projects=False):
    workspace = (workspace or '').strip()
    base = grade_records_for(user, include_previous_projects=include_previous_projects)
    if not workspace:
        return base
    if workspace == 'operations':
        if is_admin_user(user):
            return base
        from .scopes import pit_grade_filters
        return base.filter(pit_grade_filters(user))
    if workspace == 'adviser':
        return base.filter(scope='capstone', team__adviser=user)
    if workspace == 'instructor':
        return base.filter(scope='pit', team__in=workspace_teams_for(user, workspace))
    if workspace == 'panelist':
        return base.filter(schedule__panel_assignments__panelist=user).distinct()
    return base.none()
