from django.utils import timezone

from .models import TeamAdviserAssignment


MAX_ACTIVE_CAPSTONE_TEAMS = 4


def active_adviser_teams(adviser_id, *, exclude_team_id=None):
    """Count current open projects, never historical roster/grade copies."""
    from .models import StudentTeam
    from django.db.models import F, Q
    teams = StudentTeam.objects.filter(adviser_id=adviser_id, level__icontains='Capstone').exclude(
        pk=exclude_team_id).filter(Q(semester__is_active=True) | Q(
            term_participations__project_version=F('project_version'),
            term_participations__closed_at__isnull=True)).distinct()
    result = []
    for team in teams:
        latest = team.term_participations.filter(project_version=team.project_version).order_by('-pk').first()
        if team.status == StudentTeam.STATUS_FAILED or (latest and latest.closed_at and latest.outcome in ('completed', 'failed')):
            continue
        from grading.grades.models import TeamGrade
        if TeamGrade.all_objects.filter(team=team, project_version=team.project_version, status='published').exists():
            from .capstone_lifecycle import project_outcome
            outcome, _, _ = project_outcome(team)
            if outcome in ('completed', 'failed'):
                continue
        result.append(team)
    return result


def validate_adviser_capacity(team, adviser_id):
    from django.core.exceptions import ValidationError
    if adviser_id and team.is_capstone and len(active_adviser_teams(adviser_id, exclude_team_id=team.pk)) >= MAX_ACTIVE_CAPSTONE_TEAMS:
        raise ValidationError({'adviser': 'An adviser can supervise at most four concurrent active Capstone teams.'})


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
