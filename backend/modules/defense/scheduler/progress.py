"""Presentation status follows recorded assessment work, never elapsed slots."""
from django.utils import timezone
from grading.grades.models import TeamGrade, GradeAttemptHistory

DISPLAY_STATUSES = ['scheduled', 'awaiting_evaluation', 'evaluating', 'awaiting_verdict',
    'revisions_pending', 'redefense_required', 'grading_incomplete', 'awaiting_completion',
    'failed', 'project_rejected', 'assessed', 'completed', 'paused', 'postponed', 'no_show',
    'cancelled', 'archived']


def schedule_progress(schedule):
    cached = getattr(schedule, '_workflow_progress', None)
    if cached is not None:
        return cached
    grade = next(iter(schedule.grade_records.all()), None)
    if grade is None:
        grade = TeamGrade.all_objects.filter(schedule=schedule).select_related('team', 'semester', 'schedule').first()
    history = None if grade else GradeAttemptHistory.objects.filter(schedule=schedule).order_by('-id').first()
    verdict = grade.verdict if grade else history.verdict if history else ''
    result = {'verdict': verdict, 'attempt_count': grade.attempt_count if grade else history.attempt_number if history else 1,
              'panel_evaluators_submitted': 0, 'panel_evaluators_required': 0,
              'revisions_cleared_at': str(grade.revisions_cleared_at) if grade and grade.revisions_cleared_at else None}
    if schedule.status in ('cancelled', 'archived'):
        display = schedule.status
    elif history or schedule.project_version != schedule.team.project_version:
        display = 'assessed'
    elif schedule.operation_state != 'normal' and schedule.status == 'scheduled':
        display = schedule.operation_state
    elif grade:
        if grade.verdict and schedule.status == 'scheduled':
            from defense.scheduler.models import DefenseSchedule
            DefenseSchedule.objects.filter(pk=schedule.pk, status='scheduled').update(status=DefenseSchedule.STATUS_DONE)
            schedule.status = DefenseSchedule.STATUS_DONE
        from grading.grades.services import team_grading_readiness
        readiness = team_grading_readiness(grade, grade.semester, grade.scope)
        result.update(panel_evaluators_submitted=readiness['panel_evaluators_submitted'],
                      panel_evaluators_required=readiness['panel_evaluators_required'])
        if grade.status == 'published' and grade.result == 'passed':
            display = 'completed'
        elif grade.status == 'published' and grade.result == 'failed':
            display = 'failed'
        elif verdict == 'for_redefense':
            display = 'redefense_required'
        elif verdict in ('failed', 'project_rejected'):
            display = verdict
        elif verdict == 'approved_with_revisions' and not grade.revisions_cleared_at:
            display = 'revisions_pending'
        elif verdict in TeamGrade.PASSING_VERDICTS:
            display = 'awaiting_completion' if readiness['ready'] else 'grading_incomplete'
        elif grade.scope == TeamGrade.SCOPE_PIT and readiness['ready']:
            display = 'awaiting_completion'
        elif readiness['panel_complete']:
            display = 'awaiting_verdict' if schedule.scope == 'capstone' else 'grading_incomplete'
        elif readiness['panel_evaluators_submitted'] or grade.panel_score is not None:
            display = 'evaluating'
        else:
            display = 'scheduled' if schedule.scheduled_date > timezone.localdate() else 'awaiting_evaluation'
    else:
        display = 'assessed' if schedule.status == 'done' else 'scheduled' if schedule.scheduled_date > timezone.localdate() else 'awaiting_evaluation'
    result['display_status'] = display
    # Preserve an explicitly completed defense when its schedule is archived.
    # A submitted score or assessed attempt is not completion.
    result['is_completed'] = bool(grade and grade.status == TeamGrade.STATUS_PUBLISHED and grade.result == 'passed')
    schedule._workflow_progress = result
    return result
