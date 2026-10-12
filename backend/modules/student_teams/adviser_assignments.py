from django.utils import timezone

from .models import TeamAdviserAssignment


def adviser_user_id(adviser):
    return adviser.id if adviser is not None else None


def adviser_assignment_conflict(team, adviser_id):
    """Changing an adviser must not create a conflict on a current open panel."""
    if not team.pk or adviser_id is None:
        return ''
    from defense.scheduler.models import SchedulePanelist
    if SchedulePanelist.objects.filter(
        schedule__team_id=team.pk, schedule__project_version=team.project_version,
        schedule__status='scheduled', panelist_id=adviser_id,
    ).exists():
        return 'This faculty member is on an active defense panel for this team. Replace them on the panel before assigning them as adviser.'
    return ''


def record_team_adviser_change(team, previous_adviser_id, new_adviser, assigned_by=None, reason=''):
    """
    Close the open assignment row and create a new one when the team's adviser changes.
    """
    new_adviser_id = adviser_user_id(new_adviser)
    if previous_adviser_id == new_adviser_id:
        return

    now = timezone.now()
    TeamAdviserAssignment.objects.filter(team=team, ended_at__isnull=True).update(ended_at=now)
    TeamAdviserAssignment.objects.create(
        team=team,
        adviser=new_adviser,
        assigned_by=assigned_by,
        reason=(reason or '').strip()[:255],
    )
