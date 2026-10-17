"""PIT event owners choose membership limits; team reuse is independent."""
from django.db.models import Q


def pit_event_memberships(queryset, event_name):
    if event_name:
        return queryset.filter(
            Q(team__current_defense_stage=event_name)
            | Q(team__defense_schedules__event_name=event_name, team__defense_schedules__scope='pit')
        ).distinct()
    return queryset.filter(Q(team__current_defense_stage__isnull=True) | Q(team__current_defense_stage=''))


def allows_multiple(semester, event_name):
    from defense.scheduler.models import PitEventGradingConfig
    return bool(event_name and PitEventGradingConfig.objects.filter(
        semester=semester, event_name=event_name, team_membership_policy='multiple').exists())
