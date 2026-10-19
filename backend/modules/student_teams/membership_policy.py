"""PIT event owners choose membership limits; team reuse is independent."""
from django.db.models import Q


def pit_event_memberships(queryset, event_name):
    from .pit_rosters import membership_queryset
    return membership_queryset(queryset, event_name)


def allows_multiple(semester, event_name):
    from defense.scheduler.models import PitEventGradingConfig
    return bool(event_name and PitEventGradingConfig.objects.filter(
        semester=semester, event_name=event_name, team_membership_policy='multiple').exists())
