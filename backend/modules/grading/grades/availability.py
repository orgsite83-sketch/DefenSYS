"""Submission availability is separate from required grading components."""
from django.core.exceptions import ValidationError
from django.utils import timezone

from defense.scheduler.models import DefenseSchedule
from student_teams.services import was_stage_endorsed
from .models import TeamGrade


def capstone_context_unavailable_reason(grade):
    if grade is None or not grade.schedule_id:
        return 'This team must be endorsed and scheduled before grading opens.'
    team, schedule = grade.team, grade.schedule
    if grade.project_version != team.project_version or schedule.project_version != team.project_version:
        return 'This assessment belongs to a previous project and is read-only.'
    if not grade.semester.is_active or grade.semester_id != team.semester_id:
        return 'Grading is only open for the active academic term.'
    if (schedule.team_id != team.pk or schedule.semester_id != grade.semester_id
            or schedule.scope != grade.scope or schedule.stage_label != grade.stage_label
            or (grade.defense_stage_id and schedule.defense_stage_id != grade.defense_stage_id)):
        return 'The grade must match the current defense schedule and stage.'
    if schedule.status not in (DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE):
        return 'This defense is cancelled or archived and is read-only.'
    if schedule.operation_state != 'normal':
        return f'This defense is {schedule.operation_state.replace("_", " ")}. An administrator must resume it before grading.'
    stage = grade.defense_stage or schedule.defense_stage
    # ready_for_stage supports legacy endorsements; lifecycle progress survives
    # completion and re-defense, when the mirrored ready flag may be cleared.
    if team.ready_for_stage != grade.stage_label and not (stage and was_stage_endorsed(team, stage)):
        return 'This team must be endorsed for this defense stage before grading opens.'
    return ''


def _grade_unavailable_reason(grade):
    if grade is None:
        return 'This team must be endorsed and scheduled before grading opens.'
    if grade.status in TeamGrade.LOCKED_STATUSES:
        return 'Grades for this team have been finalized and are read-only.'
    from .services import require_grade_editable
    try:
        require_grade_editable(grade)
    except ValidationError as exc:
        return ' '.join(exc.messages)
    return ''


def peer_grading_unavailable_reason(grade):
    reason = _grade_unavailable_reason(grade)
    if reason:
        return reason
    from .services import group_settings_for_grade
    if grade.scope == TeamGrade.SCOPE_PIT:
        if not group_settings_for_grade(grade).get('peer_grading_enabled'):
            return 'Peer grading is closed for this event.'
        if grade.peer_weight <= 0:
            return 'Peer grading is not required for this event.'
        from defense.scheduler.pit_config import get_pit_event_config
        config = grade.pit_event_config if grade.pit_event_config_id else get_pit_event_config(
            grade.semester, grade.stage_label, year_level=grade.team.year_level)
        if config is None or not config.peer_rubric_id:
            return 'A peer rubric must be configured before students can grade their teammates.'
        schedule = grade.schedule
        if schedule is None:
            return 'Peer grading opens after this team finishes its scheduled defense.'
        if not grade.semester.is_active or grade.semester_id != grade.team.semester_id:
            return 'Grading is only open for the active academic term.'
        if schedule.project_version != grade.team.project_version:
            return 'This assessment belongs to a previous project and is read-only.'
        if (schedule.team_id != grade.team_id or schedule.semester_id != grade.semester_id
                or schedule.scope != grade.scope or schedule.stage_label != grade.stage_label):
            return 'The grade must match the current scheduled defense and PIT event.'
        if schedule.status not in (DefenseSchedule.STATUS_SCHEDULED, DefenseSchedule.STATUS_DONE):
            return 'This defense is cancelled or archived and is read-only.'
        if schedule.operation_state != 'normal':
            return f'This defense is {schedule.operation_state.replace("_", " ")}. An administrator must resume it before grading.'
        return _peer_panel_unavailable_reason(grade)
    if not grade.semester.capstone_peer_evaluation_enabled:
        return 'Peer evaluation is disabled for this academic term.'
    reason = capstone_context_unavailable_reason(grade)
    if reason:
        return reason
    if grade.peer_weight <= 0:
        return 'Peer evaluation is not required for this defense stage.'
    return _peer_panel_unavailable_reason(grade)


def _peer_panel_unavailable_reason(grade):
    """A finished presentation needs every current evaluator, not a partial score.

    Schedule status may still be scheduled while peer grades are outstanding;
    requiring final event completion here would deadlock grade finalization.
    """
    if grade.schedule.scheduled_date > timezone.localdate():
        return 'Students can grade their teammates after their scheduled defense finishes.'
    from .corrections import evaluator_completion
    completion = evaluator_completion(grade)
    if (not completion['required'] or completion['submitted'] != completion['required']
            or grade.panel_score is None):
        return 'Peer evaluation opens after every assigned faculty and external panelist submits a complete evaluation.'
    return ''


def adviser_grading_unavailable_reason(grade):
    reason = _grade_unavailable_reason(grade)
    if reason:
        return reason
    if grade.scope != TeamGrade.SCOPE_CAPSTONE:
        return 'Adviser grading is only available for Capstone teams.'
    if not grade.semester.capstone_adviser_grading_enabled:
        return 'Adviser grading is disabled for this academic term.'
    reason = capstone_context_unavailable_reason(grade)
    if reason:
        return reason
    if grade.adviser_weight <= 0:
        return 'Adviser grading is not required for this defense stage.'
    return ''
