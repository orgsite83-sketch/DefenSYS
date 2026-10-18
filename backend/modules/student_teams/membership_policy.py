"""PIT event owners choose membership limits; team reuse is independent."""
from django.db.models import Q


def pit_event_memberships(queryset, event_name):
    if event_name:
        unassigned = queryset.filter(
            Q(team__current_defense_stage__isnull=True) | Q(team__current_defense_stage='')
        ).exclude(team__defense_schedules__scope='pit').exclude(
            team__concept_rounds__pit_event_config__isnull=False)
        return queryset.filter(
            Q(team__current_defense_stage=event_name)
            | Q(team__defense_schedules__event_name=event_name, team__defense_schedules__scope='pit')
            | Q(team__concept_rounds__pit_event_config__event_name=event_name)
            # An unassigned roster is not a free membership bucket. It must
            # remain visible when a later event workflow checks availability.
            | Q(pk__in=unassigned.values('pk'))
        ).distinct()
    # Roster creation without an event must check the entire semester's PIT
    # rosters, including older teams that were created with an event attached.
    return queryset


def allows_multiple(semester, event_name):
    from defense.scheduler.models import PitEventGradingConfig
    return bool(event_name and PitEventGradingConfig.objects.filter(
        semester=semester, event_name=event_name, team_membership_policy='multiple').exists())
