from django.db import transaction
from django.utils import timezone

from grading.constants import PASS_GRADE_THRESHOLD
from .models import StudentTeam, TeamStageProgress


def get_ready_teams(semester, stage):
    from defense.scheduler.models import DefenseSchedule
    from grading.grades.models import TeamGrade

    scheduled_progress = TeamStageProgress.objects.filter(
        semester=semester,
        defense_stage=stage,
        status=TeamStageProgress.STATUS_SCHEDULED,
    )
    if scheduled_progress.exists():
        active_scheduled_team_ids = set(
            DefenseSchedule.objects.filter(
                scope=DefenseSchedule.SCOPE_CAPSTONE,
                semester=semester,
                defense_stage=stage,
                status=DefenseSchedule.STATUS_SCHEDULED,
            ).values_list('team_id', flat=True)
        )
        for progress in scheduled_progress:
            if progress.team_id not in active_scheduled_team_ids:
                grade = TeamGrade.objects.filter(
                    team=progress.team,
                    semester=semester,
                    defense_stage=stage,
                ).first()
                if not (grade and grade.result == 'passed'):
                    progress.status = TeamStageProgress.STATUS_READY
                    progress.save(update_fields=['status', 'updated_at'])

    ready_ids = set(
        TeamStageProgress.objects.filter(
            semester=semester,
            defense_stage=stage,
            status=TeamStageProgress.STATUS_READY,
        ).values_list('team_id', flat=True)
    )

    active_scheduled_ids = set(
        DefenseSchedule.objects.filter(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=semester,
            defense_stage=stage,
            status=DefenseSchedule.STATUS_SCHEDULED,
        ).values_list('team_id', flat=True)
    )
    redefense_team_ids = set(
        TeamGrade.objects.filter(
            semester=semester,
            defense_stage=stage,
            verdict=TeamGrade.VERDICT_FOR_REDEFENSE,
        ).exclude(team_id__in=active_scheduled_ids)
        .values_list('team_id', flat=True)
    )
    all_ready_ids = ready_ids | redefense_team_ids
    return StudentTeam.objects.filter(pk__in=all_ready_ids)


def get_stage_progress(team, stage):
    if not team or not stage:
        return None
    return TeamStageProgress.objects.filter(
        team=team,
        semester=team.semester,
        defense_stage=stage,
    ).first()


def is_stage_ready(team, stage):
    if not team or not stage:
        return False

    from grading.grades.models import TeamGrade
    from defense.scheduler.models import DefenseSchedule

    grade = TeamGrade.objects.filter(
        team=team,
        semester=team.semester,
        defense_stage=stage,
    ).first()
    if grade and getattr(grade, 'verdict', '') == TeamGrade.VERDICT_FOR_REDEFENSE:
        has_active = DefenseSchedule.objects.filter(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            team=team,
            defense_stage=stage,
            status=DefenseSchedule.STATUS_SCHEDULED,
        ).exists()
        return not has_active

    progress = get_stage_progress(team, stage)
    if not progress:
        return False
    if progress.status == TeamStageProgress.STATUS_READY:
        return True

    if progress.status == TeamStageProgress.STATUS_SCHEDULED:
        has_active = DefenseSchedule.objects.filter(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            team=team,
            defense_stage=stage,
            status=DefenseSchedule.STATUS_SCHEDULED,
        ).exists()
        if not has_active:
            if grade and grade.result == 'passed':
                return False
            progress.status = TeamStageProgress.STATUS_READY
            progress.save(update_fields=['status', 'updated_at'])
            return True
    return False


# Statuses that indicate endorsement already happened (ready or any later stage).
_ENDORSED_STATUSES = frozenset({
    TeamStageProgress.STATUS_READY,
    TeamStageProgress.STATUS_SCHEDULED,
    TeamStageProgress.STATUS_GRADING,
    TeamStageProgress.STATUS_PASSED,
    TeamStageProgress.STATUS_ARCHIVED,
})


def was_stage_endorsed(team, stage):
    """Return True if the team has been endorsed for this stage at any point.

    Unlike ``is_stage_ready`` (which matches only 'ready'), this also matches
    later lifecycle statuses such as 'scheduled', 'passed', etc.
    """
    progress = get_stage_progress(team, stage)
    return bool(progress and progress.status in _ENDORSED_STATUSES)


def _progress_for(team, stage, user=None):
    progress, created = TeamStageProgress.objects.get_or_create(
        team=team,
        semester=team.semester,
        defense_stage=stage,
        defaults={'created_by': user},
    )
    return progress, created


def _mirror_ready_stage(team, stage):
    label = stage.label
    if team.ready_for_stage != label or team.current_defense_stage != label:
        team.ready_for_stage = label
        team.current_defense_stage = label
        team.save(update_fields=['ready_for_stage', 'current_defense_stage', 'updated_at'])


def _mirror_team_status(team, status):
    if team.status != status:
        team.status = status
        team.save(update_fields=['status', 'updated_at'])


@transaction.atomic
def mark_stage_ready(team, stage, user=None):
    progress, _ = _progress_for(team, stage, user=user)
    progress.status = TeamStageProgress.STATUS_READY
    progress.ready_at = progress.ready_at or timezone.now()
    progress.updated_by = user
    progress.save(update_fields=['status', 'ready_at', 'updated_by', 'updated_at'])
    _mirror_ready_stage(team, stage)
    return progress


@transaction.atomic
def mark_stage_locked(team, stage, user=None):
    progress, _ = _progress_for(team, stage, user=user)
    progress.status = TeamStageProgress.STATUS_LOCKED
    progress.updated_by = user
    progress.save(update_fields=['status', 'updated_by', 'updated_at'])
    if team.ready_for_stage == stage.label:
        team.ready_for_stage = None
        team.save(update_fields=['ready_for_stage', 'updated_at'])
    return progress


@transaction.atomic
def mark_stage_scheduled(team, stage, grade=None, user=None):
    progress, _ = _progress_for(team, stage, user=user)
    progress.status = TeamStageProgress.STATUS_SCHEDULED
    progress.grade = grade or progress.grade
    progress.scheduled_at = progress.scheduled_at or timezone.now()
    progress.updated_by = user
    progress.save(update_fields=['status', 'grade', 'scheduled_at', 'updated_by', 'updated_at'])
    return progress


@transaction.atomic
def mark_stage_result(grade, user=None):
    if not grade or grade.scope != grade.SCOPE_CAPSTONE or not grade.defense_stage_id:
        return None

    progress, _ = _progress_for(grade.team, grade.defense_stage, user=user)
    verdict = getattr(grade, 'verdict', '')
    if verdict:
        is_passed = verdict in ('approved', 'approved_with_revisions')
    else:
        is_passed = grade.final_grade is not None and grade.final_grade >= PASS_GRADE_THRESHOLD

    if is_passed:
        progress.status = TeamStageProgress.STATUS_PASSED
        team_status = StudentTeam.STATUS_APPROVED
        grade.team.current_defense_stage = grade.defense_stage.label
        team_update_fields = ['current_defense_stage', 'updated_at']
        if grade.team.ready_for_stage == grade.defense_stage.label:
            grade.team.ready_for_stage = None
            team_update_fields.append('ready_for_stage')
        grade.team.save(update_fields=team_update_fields)
    else:
        progress.status = TeamStageProgress.STATUS_FAILED
        if verdict == 'for_redefense':
            team_status = grade.team.status or StudentTeam.STATUS_APPROVED
        else:
            team_status = StudentTeam.STATUS_FAILED

    progress.grade = grade
    progress.graded_at = progress.graded_at or timezone.now()
    progress.updated_by = user
    progress.save(update_fields=['status', 'grade', 'graded_at', 'updated_by', 'updated_at'])
    _mirror_team_status(grade.team, team_status)
    return progress
