"""One current identity, with an explicit event owning its live details.

Event snapshots and copy provenance are never inferred from save timestamps.
Callers hold the semester/event locks before changing profiles.
"""
from .models import PITRosterTeamDetails
from .pit_rosters import effective_ids


def is_current(team):
    return team.is_pit and team.pk in effective_ids(team.semester_id, team.year_level)


def activate_details(team, event, *, explicit=False):
    if not is_current(team):
        return False
    profile, _ = PITRosterTeamDetails.objects.select_for_update().get_or_create(
        team=team, event=None, defaults={'name': team.name, 'project_title': team.project_title})
    if profile.details_source_event_id and profile.details_source_event_id != event.pk and not explicit:
        return False
    changed = profile.details_source_event_id != event.pk
    if not changed and not explicit:
        return True
    profile.details_source_event = event
    detail = PITRosterTeamDetails.objects.filter(team=team, event=event).first()
    if detail:
        profile.project_title = detail.project_title
        profile.confirmed_at = None
    profile.revision += 1
    profile.save(update_fields=['details_source_event', 'project_title', 'confirmed_at', 'revision', 'updated_at'])
    return True


def sync_confirmed_details(team, event):
    """Update the current profile only from its designated, confirmed source."""
    if not is_current(team):
        return False
    profile = PITRosterTeamDetails.objects.select_for_update().filter(team=team, event=None).first()
    detail = PITRosterTeamDetails.objects.filter(team=team, event=event, confirmed_at__isnull=False).first()
    if not profile or not detail or profile.details_source_event_id != event.pk:
        return False
    from .roster_workspace import freeze_events, project_for
    from defense.scheduler.models import PitEventGradingConfig
    # Capture legacy history before updating compatibility fields on the team.
    freeze_events(team.semester, team.year_level, team.section,
        PitEventGradingConfig.objects.filter(semester_id=team.semester_id,
            year_level=team.year_level).exclude(pk=event.pk))
    project = project_for(team, event)
    profile.name, profile.project_title = detail.name, project['carry_title']
    profile.project_mode, profile.confirmed_at = detail.project_mode, detail.confirmed_at
    profile.revision += 1
    profile.save()
    team.name, team.project_title = detail.name, project['carry_title']
    team.setup_pending, team.project_pending = False, not bool(project['carry_title'])
    team.current_defense_stage = event.event_name
    team.save(update_fields=['name', 'project_title', 'setup_pending', 'project_pending',
        'current_defense_stage', 'updated_at'])
    return True


def current_student_team(owned_teams):
    """Resolve active membership through roster bindings, never updated_at."""
    from .term_scope import apply_team_scope
    from .pit_rosters import filter_teams
    from rest_framework.exceptions import ValidationError
    teams = list(filter_teams(apply_team_scope(owned_teams, 'active'), current=True).distinct()[:2])
    if len(teams) > 1:
        raise ValidationError('Your Current roster has overlapping team memberships. Ask your instructor to review it.')
    return teams[0] if teams else None
