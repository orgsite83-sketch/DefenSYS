from django.utils import timezone

from .models import TeamAdviserAssignment


MAX_ACTIVE_CAPSTONE_TEAMS = 4


def active_adviser_teams(adviser_id, *, exclude_team_id=None):
    """Count current open projects, never historical roster/grade copies."""
    return [team for team in active_teams_by_adviser([adviser_id]).get(adviser_id, [])
            if team.pk != exclude_team_id]


def active_teams_by_adviser(adviser_ids):
    """Resolve all requested advisers together; lifecycle evidence remains authoritative."""
    from .models import StudentTeam
    from django.db.models import Exists, F, OuterRef, Q
    from grading.grades.models import TeamGrade
    teams = StudentTeam.objects.filter(adviser_id__in=adviser_ids, level__icontains='Capstone').filter(
        Q(semester__is_active=True) | Q(
            term_participations__project_version=F('project_version'),
            term_participations__outcome__in=['open', 'needs_review'])).distinct().select_related(
                'semester__school_year', 'intake_semester__school_year').prefetch_related('term_participations').annotate(
                    has_published_capacity_grade=Exists(TeamGrade.all_objects.filter(
                        team_id=OuterRef('pk'), project_version=OuterRef('project_version'), status='published')))
    result = {pk: [] for pk in adviser_ids}
    for team in teams:
        latest = max((row for row in team.term_participations.all() if row.project_version == team.project_version),
                     key=lambda row: row.pk, default=None)
        if team.status == StudentTeam.STATUS_FAILED or (latest and latest.closed_at and latest.outcome in ('completed', 'failed')):
            continue
        if team.has_published_capacity_grade:
            from .capstone_lifecycle import project_outcome
            outcome, _, _ = project_outcome(team)
            if outcome in ('completed', 'failed'):
                continue
        result[team.adviser_id].append(team)
    return result


def validate_adviser_capacity(team, adviser_id):
    from django.core.exceptions import ValidationError
    if not adviser_id or not team.is_capstone or team.status == team.STATUS_FAILED:
        return
    from .models import StudentTeam
    from .adviser_capacity import effective_exception
    active = active_adviser_teams(adviser_id)
    previous = StudentTeam.objects.filter(pk=team.pk).first() if team.pk else None
    # Continuing the same open project does not consume a new place, even after
    # the authorization ends. A restart or transfer must be checked afresh.
    same_intake = previous and (previous.intake_semester_id == team.intake_semester_id or (
        previous.intake_semester_id is None and team.intake_semester_id == previous.semester_id))
    if previous and previous.adviser_id == adviser_id and previous.project_version == team.project_version \
            and same_intake and previous.is_capstone \
            and any(row.pk == team.pk for row in active):
        return
    exception = effective_exception(adviser_id, team=team)
    limit = exception.approved_limit if exception else MAX_ACTIVE_CAPSTONE_TEAMS
    count = len([row for row in active if row.pk != team.pk])
    if count + 1 > limit:
        kind = 'approved' if exception else 'standard'
        raise ValidationError({'adviser': f'This adviser has {len(active)} active Capstone teams. '
                               f'The {kind} limit is {limit}.'})


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
