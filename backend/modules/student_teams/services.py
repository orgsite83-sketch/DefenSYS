from django.db import transaction
from django.core.exceptions import ValidationError
from django.utils import timezone

from grading.constants import PASS_GRADE_THRESHOLD
from .models import StudentTeam, TeamStageProgress


def get_ready_teams(semester, stage):
    ids = [team.pk for team in StudentTeam.objects.filter(semester=semester) if is_stage_ready(team, stage)]
    return StudentTeam.objects.filter(pk__in=ids)


def stage_progression_blocker(team, stage):
    """Require prior stages to be officially passed and cleared on this project."""
    from defense.stages.models import DefenseStage
    for previous in DefenseStage.objects.filter(is_active=True, display_order__lt=stage.display_order):
        progress = get_stage_progress(team, previous)
        if not progress or progress.status not in (TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_ARCHIVED):
            return f'{previous.label} must be completed, passed, and cleared before {stage.label}.'
        from repository.deliverables.services import post_deliverables_complete
        if not post_deliverables_complete(team, previous.label):
            return f'Post-defense deliverables for {previous.label} must be approved by the adviser before proceeding to {stage.label}.'
    return ''


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

    if stage_progression_blocker(team, stage):
        return False
    active_scheds = DefenseSchedule.objects.filter(
        scope='capstone', team=team, semester=team.semester, defense_stage=stage,
        project_version=team.project_version, status='scheduled',
    )
    has_active = False
    for sched in active_scheds:
        sched_grade = sched.grade_records.first()
        if sched_grade and sched_grade.verdict:
            sched.status = DefenseSchedule.STATUS_DONE
            sched.save(update_fields=['status', 'updated_at'])
        else:
            has_active = True
    if has_active:
        return False
    from grading.grades.defense_workflow import recovery_for, replacement_for
    grade = TeamGrade.objects.filter(
        team=team,
        semester=team.semester,
        defense_stage=stage,
    ).first()
    if grade and getattr(grade, 'verdict', '') == TeamGrade.VERDICT_FOR_REDEFENSE:
        return not grade.redefense_verification_required or bool(grade.redefense_verified_at)
    if grade and grade.verdict in ('failed', 'project_rejected'):
        return bool(recovery_for(team, stage))
    if grade and grade.verdict in TeamGrade.PASSING_VERDICTS:
        return False
    if replacement_for(team, stage):
        from repository.deliverables.services import required_complete
        return required_complete(team, stage.label)

    progress = get_stage_progress(team, stage)
    if not progress:
        return False
    if progress.status == TeamStageProgress.STATUS_READY:
        return True

    if progress.status == TeamStageProgress.STATUS_SCHEDULED:
        return not (grade and grade.result == 'passed')
    return False


# Statuses that indicate endorsement already happened (ready or any later stage).
_ENDORSED_STATUSES = frozenset({
    TeamStageProgress.STATUS_READY,
    TeamStageProgress.STATUS_SCHEDULED,
    TeamStageProgress.STATUS_GRADING,
    TeamStageProgress.STATUS_PASSED,
    TeamStageProgress.STATUS_ARCHIVED,
    TeamStageProgress.STATUS_REVISIONS,
    TeamStageProgress.STATUS_REDEFENSE,
})


def was_stage_endorsed(team, stage):
    """Return True if the team has been endorsed for this stage at any point.

    Unlike ``is_stage_ready`` (which matches only 'ready'), this also matches
    later lifecycle statuses such as 'scheduled', 'passed', etc.
    """
    progress = get_stage_progress(team, stage)
    return bool(progress and (progress.status in _ENDORSED_STATUSES or (
        progress.status == TeamStageProgress.STATUS_FAILED and progress.ready_at)))


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
    blocker = stage_progression_blocker(team, stage)
    if blocker:
        raise ValidationError(blocker)
    from grading.grades.models import TeamGrade
    from grading.grades.defense_workflow import recovery_for
    grade = TeamGrade.objects.filter(team=team, defense_stage=stage, semester=team.semester).first()
    if grade and grade.verdict in ('failed', 'project_rejected') and not recovery_for(team, stage):
        raise ValidationError('An authorized recovery decision is required before scheduling another attempt.')
    if grade and grade.verdict in TeamGrade.PASSING_VERDICTS:
        raise ValidationError('This defense is approved. Complete its required grading and revision clearance instead of re-endorsing it.')
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
    from grading.grades.defense_workflow import passed_and_cleared
    from repository.deliverables.services import post_deliverables_complete
    lbl = grade.defense_stage.label if grade.defense_stage_id else grade.stage_label
    post_done = post_deliverables_complete(grade.team, lbl)
    is_passed = grade.status == grade.STATUS_PUBLISHED and passed_and_cleared(grade) and post_done

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
        if verdict == 'for_redefense':
            progress.status = TeamStageProgress.STATUS_REDEFENSE
            team_status = grade.team.status or StudentTeam.STATUS_APPROVED
        elif verdict == 'approved_with_revisions' and not grade.revisions_cleared_at:
            progress.status = TeamStageProgress.STATUS_REVISIONS
            team_status = grade.team.status
        elif verdict in ('failed', 'project_rejected'):
            progress.status = TeamStageProgress.STATUS_FAILED
            team_status = StudentTeam.STATUS_FAILED
        else:
            progress.status = TeamStageProgress.STATUS_GRADING
            team_status = grade.team.status

    progress.grade = grade
    progress.graded_at = progress.graded_at or timezone.now()
    progress.updated_by = user
    progress.save(update_fields=['status', 'grade', 'graded_at', 'updated_by', 'updated_at'])
    _mirror_team_status(grade.team, team_status)
    return progress
