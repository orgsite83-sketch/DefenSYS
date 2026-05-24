"""WebSocket channel group names and membership resolution."""

import re

from channels.db import database_sync_to_async
from django.contrib.auth import get_user_model

from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam
from student_teams.term_scope import get_active_semester

User = get_user_model()


def pit_group_name(semester_id: int, event_label: str) -> str:
    slug = re.sub(r'[^a-zA-Z0-9]+', '_', (event_label or '').strip().lower()).strip('_')
    return f'pit_{semester_id}_{slug or "event"}'


def semester_group_name(semester_id: int) -> str:
    return f'semester_{semester_id}'


def user_group_name(user_id: int) -> str:
    return f'user_{user_id}'


def _student_team_for_user(user):
    team = (
        StudentTeam.objects.select_related('semester')
        .filter(memberships__student=user)
        .order_by('-updated_at', '-id')
        .first()
    )
    if team:
        return team
    if user.team_id:
        try:
            return StudentTeam.objects.select_related('semester').get(pk=int(user.team_id))
        except (StudentTeam.DoesNotExist, ValueError, TypeError):
            return None
    return None


def groups_for_user(user) -> set[str]:
    """Channel groups a connected client should join."""
    groups = {user_group_name(user.pk)}

    active = get_active_semester()
    if active is not None:
        groups.add(semester_group_name(active.id))

    team = _student_team_for_user(user)
    if team is None:
        return groups

    groups.add(semester_group_name(team.semester_id))

    if not team.is_capstone:
        pit_grade = (
            TeamGrade.objects.filter(team=team, scope=TeamGrade.SCOPE_PIT)
            .order_by('-updated_at', '-id')
            .first()
        )
        if pit_grade and pit_grade.stage_label:
            groups.add(pit_group_name(team.semester_id, pit_grade.stage_label))

    return groups


def broadcast_groups_for_capstone_semester(semester_id: int) -> list[str]:
    return [semester_group_name(semester_id)]


def broadcast_groups_for_pit_event(semester_id: int, event_label: str) -> list[str]:
    return [pit_group_name(semester_id, event_label)]


@database_sync_to_async
def groups_for_user_async(user) -> list[str]:
    return list(groups_for_user(user))
