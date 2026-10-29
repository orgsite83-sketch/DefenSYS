from django.db import transaction
from django.core.exceptions import ValidationError
from django.db.models import Exists, OuterRef, Q
from django.utils import timezone

from grading.constants import PASS_GRADE_THRESHOLD
from .models import StudentTeam, TeamStageProgress


def stage_readiness_candidates(teams, stage=None):
    """Cheap superset; every candidate still goes through is_stage_ready.

    Never cache eligibility or replace progression, concept clearance, verdict,
    or participation checks. Include active schedules so an assessed attempt can be
    distinguished from an active presentation without rewriting its status.
    """
    from grading.grades.models import TeamGrade
    from defense.scheduler.models import DefenseSchedule

    identity = {'team_id': OuterRef('pk'), 'semester_id': OuterRef('semester_id')}
    progress = TeamStageProgress.objects.filter(**identity, status__in=(
        TeamStageProgress.STATUS_READY, TeamStageProgress.STATUS_SCHEDULED,
    ))
    redefense = TeamGrade.objects.filter(**identity, verdict=TeamGrade.VERDICT_FOR_REDEFENSE)
    schedules = DefenseSchedule.objects.filter(
        **identity, scope=DefenseSchedule.SCOPE_CAPSTONE,
        project_version=OuterRef('project_version'), status=DefenseSchedule.STATUS_SCHEDULED,
    )
    if stage is not None:
        progress = progress.filter(defense_stage=stage)
        redefense = redefense.filter(defense_stage=stage)
        schedules = schedules.filter(defense_stage=stage)
    return teams.filter(
        Exists(progress) | Exists(redefense) | Exists(schedules)
    ).select_related('semester')


def get_ready_teams(semester, stage):
    candidates = stage_readiness_candidates(StudentTeam.objects.filter(semester=semester), stage)
    ids = [team.pk for team in candidates if is_stage_ready(team, stage)]
    return StudentTeam.objects.filter(pk__in=ids)


def stage_progression_blocker(team, stage):
    """Require prior stages to be officially passed and cleared on this project."""
    if team.is_capstone:
        from .capstone_lifecycle import requirements_for, stage_cleared
        required = requirements_for(team)
        position = next((i for i, item in enumerate(required) if item['id'] == stage.pk), None)
        if position is None:
            return 'This stage is not part of the project\'s applicable sequence.'
        for previous in required[:position]:
            if not stage_cleared(team, previous):
                return f'{previous["label"]} must be completed, passed, and cleared before {stage.label}.'
        return ''
    from defense.stages.models import DefenseStage
    for previous in DefenseStage.objects.filter(is_active=True, display_order__lt=stage.display_order):
        progress = get_stage_progress(team, previous)
        if not progress or progress.status not in (TeamStageProgress.STATUS_PASSED, TeamStageProgress.STATUS_ARCHIVED):
            return f'{previous.label} must be completed, passed, and cleared before {stage.label}.'
        from grading.grades.models import TeamGrade
        from grading.grades.defense_workflow import passed_and_cleared, legacy_finalized_pass
        grade = TeamGrade.objects.filter(team=team, semester=team.semester, defense_stage=previous).first()
        if grade and (grade.status != TeamGrade.STATUS_PUBLISHED or not (passed_and_cleared(grade) or legacy_finalized_pass(grade))):
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

    from .participation import closed_failure
    if team.is_capstone and (team.participation_review_reason or closed_failure(team)):
        return False
    if stage_progression_blocker(team, stage):
        return False
    active_scheds = DefenseSchedule.objects.filter(
        scope='capstone', team=team, semester=team.semester, defense_stage=stage,
        project_version=team.project_version, status='scheduled',
    )
    has_active = False
    for sched in active_scheds:
        sched_grade = sched.grade_records.first()
        # Readiness is also used by GET serializers. An assessed attempt is not
        # active, but status repair belongs to an explicit scheduling operation.
        if not (sched_grade and sched_grade.verdict):
            has_active = True
    if has_active:
        return False
    grade = TeamGrade.objects.filter(
        team=team,
        semester=team.semester,
        defense_stage=stage,
    ).first()
    if team.is_capstone:
        from .capstone_lifecycle import latest_stage_assessment
        grade = latest_stage_assessment(team, stage.pk)
    from repository.deliverables.concepts import clearance_blocker
    if clearance_blocker(team, stage):
        return False
    from repository.section_concepts.shared_deliverables import resolve, required_complete as shared_complete
    shared_profile = resolve(team, stage)
    if shared_profile and not shared_complete(shared_profile):
        return False
    from repository.deliverables.services import required_complete, get_deliverable_definitions_for_team
    if get_deliverable_definitions_for_team(team, stage.label) and not required_complete(team, stage.label):
        return False
    if grade and not grade.closed_as_failed and getattr(grade, 'verdict', '') == TeamGrade.VERDICT_FOR_REDEFENSE:
        from grading.grades.outcome_rules import policy_for
        if policy_for(grade.schedule).get('version') == 1:
            progress = get_stage_progress(team, stage)
            if not progress or progress.status != TeamStageProgress.STATUS_READY or not (
                progress.ready_at and grade.verdict_at and progress.ready_at > grade.verdict_at):
                return False
            return True
        return not grade.redefense_verification_required or bool(grade.redefense_verified_at)
    if grade and grade.result == 'failed':
        return False
    if grade and grade.verdict in TeamGrade.PASSING_VERDICTS:
        return False


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
    from repository.deliverables.concepts import enabled, clearance_valid
    if enabled(stage):
        return clearance_valid(team, stage)
    if team.is_pit:
        from .pit_rosters import endorsed
        return bool(stage and endorsed(team, stage.label))
    progress = get_stage_progress(team, stage)
    if progress and progress.status == TeamStageProgress.STATUS_REDEFENSE:
        from grading.grades.models import TeamGrade
        from grading.grades.outcome_rules import policy_for
        grade = TeamGrade.objects.filter(team=team, defense_stage=stage, semester=team.semester).first()
        if grade and policy_for(grade.schedule).get('version') == 1:
            return False
    return bool(progress and (progress.status in _ENDORSED_STATUSES or (
        progress.status == TeamStageProgress.STATUS_FAILED and progress.ready_at)))


def _progress_for(team, stage, user=None, *, semester=None, project_version=None):
    progress, created = TeamStageProgress.all_objects.get_or_create(
        team=team,
        semester=semester or team.semester,
        defense_stage=stage,
        project_version=project_version or team.project_version,
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
    from .capstone_lifecycle import latest_stage_assessment
    grade = latest_stage_assessment(team, stage.pk)
    from .participation import require_open
    require_open(team)
    if grade and grade.result == 'failed':
        raise ValidationError('This participation is finalized as Failed. Return through a new Capstone 1 intake.')
    if grade and grade.verdict in TeamGrade.PASSING_VERDICTS:
        raise ValidationError('This defense is approved. Complete its required grading and revision clearance instead of re-endorsing it.')
    if team.is_capstone:
        from .capstone_lifecycle import capture_participation
        capture_participation(team)
    progress, _ = _progress_for(team, stage, user=user)
    progress.status = TeamStageProgress.STATUS_READY
    from grading.grades.outcome_rules import policy_for
    needs_new_endorsement = bool(grade and grade.verdict == 'for_redefense'
                                and policy_for(grade.schedule).get('version') == 1)
    progress.ready_at = timezone.now() if needs_new_endorsement else progress.ready_at or timezone.now()
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

    if grade.project_version != grade.team.project_version:
        return None
    progress, _ = _progress_for(grade.team, grade.defense_stage, user=user,
        semester=grade.semester, project_version=grade.project_version)
    verdict = getattr(grade, 'verdict', '')
    from grading.grades.defense_workflow import passed_and_cleared, legacy_finalized_pass
    from repository.deliverables.services import post_deliverables_complete
    lbl = grade.defense_stage.label if grade.defense_stage_id else grade.stage_label
    from .capstone_lifecycle import evidence_team, requirements_for
    requirement = next((r for r in requirements_for(grade.team) if r['id'] == grade.defense_stage_id), None)
    post_done = post_deliverables_complete(evidence_team(grade.team, grade, requirement), grade.stage_label or lbl)
    is_passed = grade.status == grade.STATUS_PUBLISHED and (passed_and_cleared(grade) or legacy_finalized_pass(grade)) and post_done

    if is_passed:
        progress.status = TeamStageProgress.STATUS_PASSED
        team_status = StudentTeam.STATUS_APPROVED
        if grade.semester_id == grade.team.semester_id:
            grade.team.current_defense_stage = grade.defense_stage.label
            team_update_fields = ['current_defense_stage', 'updated_at']
            if grade.team.ready_for_stage == grade.defense_stage.label:
                grade.team.ready_for_stage = None
                team_update_fields.append('ready_for_stage')
            grade.team.save(update_fields=team_update_fields)
    else:
        if grade.closed_as_failed:
            progress.status = TeamStageProgress.STATUS_FAILED
            team_status = StudentTeam.STATUS_FAILED
        elif verdict == 'for_redefense':
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
    if grade.semester_id == grade.team.semester_id:
        _mirror_team_status(grade.team, team_status)
        if grade.status == grade.STATUS_PUBLISHED and grade.result == 'failed':
            from .participation import finalize_failed
            finalize_failed(grade.team, actor=user)
    return progress
