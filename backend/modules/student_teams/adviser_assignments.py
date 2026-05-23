from django.utils import timezone

from .models import TeamAdviserAssignment


def adviser_user_id(adviser):
    return adviser.id if adviser is not None else None


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
