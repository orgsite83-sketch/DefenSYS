"""Narrow a multi-role account to the authority of one requested workspace.

The empty workspace retains resource-level access for students and older clients.
Explicit unknown workspaces fail closed. Workspace selection never grants a role.
"""
from django.db.models import Q

from .scopes import (
    grade_records_for, is_admin_user,
    manageable_schedules_for, manageable_teams_for,
    section_instructor_section_filters, visible_schedules_for, visible_teams_for,
)
from .workspace_roles import is_adviser, is_institutional_staff, is_pit_lead, pit_teams_for


def workspace_teams_for(user, workspace=''):
    workspace = (workspace or '').strip()
    if workspace == 'operations':
        return manageable_teams_for(user)
    base = visible_teams_for(user)
    if not workspace:
        return base
    if workspace == 'pit_lead':
        return pit_teams_for(user, base)
    if workspace == 'adviser':
        return base.filter(level__icontains='Capstone', adviser=user) if is_adviser(user) else base.none()
    if workspace == 'instructor':
        return base.filter(section_instructor_section_filters(user), level__icontains='PIT') if is_institutional_staff(user) else base.none()
    return base.none()


def workspace_schedules_for(user, workspace=''):
    workspace = (workspace or '').strip()
    if workspace == 'operations':
        return manageable_schedules_for(user)
    base = visible_schedules_for(user)
    if not workspace:
        return base
    if workspace == 'pit_lead':
        return base.filter(scope='pit', team__in=workspace_teams_for(user, workspace))
    if workspace == 'adviser':
        return base.filter(scope='capstone', team__in=workspace_teams_for(user, workspace))
    if workspace == 'instructor':
        return base.filter(scope='pit', team__in=workspace_teams_for(user, workspace))
    if workspace == 'panelist':
        return base.filter(panel_assignments__panelist=user).distinct() if is_institutional_staff(user) and user.is_panelist else base.none()
    if workspace == 'documenter':
        return base.filter(scope='capstone', documenter=user) if is_institutional_staff(user) and user.is_documenter else base.none()
    return base.none()


def workspace_grades_for(user, workspace='', *, include_previous_projects=False):
    workspace = (workspace or '').strip()
    base = grade_records_for(user, include_previous_projects=include_previous_projects)
    if not workspace:
        return base
    if workspace == 'pit_lead':
        return base.filter(scope='pit', team__in=workspace_teams_for(user, workspace)).filter(
            Q(pit_event_config__year_level=user.pit_lead_year)
            | Q(pit_event_config__isnull=True)) if is_pit_lead(user) else base.none()
    if workspace == 'operations':
        if is_admin_user(user):
            return base
        from .scopes import pit_grade_filters
        return base.filter(pit_grade_filters(user))
    if workspace == 'adviser':
        return base.filter(scope='capstone', team__in=workspace_teams_for(user, workspace))
    if workspace == 'instructor':
        return base.filter(scope='pit', team__in=workspace_teams_for(user, workspace))
    if workspace == 'panelist':
        return base.filter(schedule__panel_assignments__panelist=user).distinct() if is_institutional_staff(user) and user.is_panelist else base.none()
    return base.none()
