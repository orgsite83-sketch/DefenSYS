"""Authoritative PIT event ownership; names never grant cohort access."""
from django.core.exceptions import PermissionDenied, ValidationError

PIT_YEAR_LEVELS = ('1st Year', '2nd Year', '3rd Year')


def pit_year(value):
    value = (value or '').strip()
    return value if value in PIT_YEAR_LEVELS else ''


def require_pit_year(value):
    year = pit_year(value)
    if not year:
        raise ValidationError({'year_level': 'Select an assigned PIT year level.'})
    return year


def pit_events_for_team(team):
    from .models import PitEventGradingConfig
    if not team or not team.is_pit or not pit_year(team.year_level):
        return PitEventGradingConfig.objects.none()
    return PitEventGradingConfig.objects.filter(semester=team.semester, year_level=team.year_level)


def pit_events_for_user(user, *, semester=None):
    from authentication_access_control.scopes import is_admin_user, is_pit_lead_only, visible_teams_for
    from .models import PitEventGradingConfig
    events = PitEventGradingConfig.objects.all()
    if semester is not None:
        events = events.filter(semester=semester)
    if is_admin_user(user):
        return events
    if is_pit_lead_only(user):
        year = pit_year(getattr(user, 'pit_lead_year', ''))
        return events.filter(year_level=year) if year else events.none()
    # Independent adviser, instructor and student assignments remain valid.
    from django.db.models import Q
    allowed = Q(pk__in=[])
    # Instructors must be able to prepare their first teams in an empty section.
    from user_management.models import SectionInstructorAssignment
    for term, year in SectionInstructorAssignment.objects.filter(
            faculty=user, is_active=True).values_list('semester_id', 'year_level').distinct():
        if pit_year(year):
            allowed |= Q(semester_id=term, year_level=year)
    for term, year in visible_teams_for(user).filter(level__icontains='PIT').values_list(
            'semester_id', 'year_level').distinct():
        if pit_year(year):
            allowed |= Q(semester_id=term, year_level=year)
    return events.filter(allowed)


def require_event_management(user, config):
    from authentication_access_control.scopes import is_admin_user, is_pit_lead_only
    if is_admin_user(user):
        return
    year = pit_year(getattr(user, 'pit_lead_year', ''))
    if not is_pit_lead_only(user) or not year or config.year_level != year:
        raise PermissionDenied('This PIT event is outside your assigned year level.')
