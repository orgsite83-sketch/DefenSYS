"""Presentation status follows recorded assessment work, never elapsed slots."""
from django.utils import timezone
from grading.grades.models import TeamGrade, GradeAttemptHistory

DISPLAY_STATUSES = ['scheduled', 'awaiting_evaluation', 'evaluating', 'awaiting_verdict',
    'revisions_pending', 'redefense_required', 'grading_incomplete', 'awaiting_completion',
    'failed', 'project_rejected', 'assessed', 'completed', 'paused', 'postponed', 'no_show',
    'cancelled', 'archived']


def schedule_progress(schedule, *, reconcile_status=True):
    # Deliverable/status presentations must be read-only. Keep their cache
    # separate so a later operational caller can still reconcile stale status.
    cache_key = '_workflow_progress' if reconcile_status else '_workflow_progress_readonly'
    cached = getattr(schedule, cache_key, None)
    if cached is not None:
        return cached
    grade = next(iter(schedule.grade_records.all()), None)
    if grade is None:
        grade = TeamGrade.all_objects.filter(schedule=schedule).select_related('team', 'semester', 'schedule').first()
    history = None if grade else GradeAttemptHistory.objects.filter(schedule=schedule).order_by('-id').first()
    verdict = ''
    uses_verdict = schedule.scope == 'capstone'
    if uses_verdict:
        verdict = grade.verdict if grade else history.verdict if history else ''
    evidence = grade or history
    concept_retry = False
    if schedule.scope == 'pit':
        from repository.deliverables.models import ConceptRound
        concept_retry = ConceptRound.objects.filter(schedule=schedule, verdict='for_redefense').exists()
    result = {'verdict': verdict, 'attempt_count': grade.attempt_count if grade else history.attempt_number if history else 1,
              'panel_evaluators_submitted': 0, 'panel_evaluators_required': 0,
              'revisions_cleared_at': str(evidence.revisions_cleared_at) if verdict and evidence.revisions_cleared_at else None,
              'revision_deadline': str(evidence.revision_deadline) if verdict and evidence.revision_deadline else None,
              'verdict_remarks': evidence.verdict_remarks if verdict else '',
              # These fields belong to this schedule, unlike the board's legacy
              # grade_status lookup which can fall back to another stage attempt.
              'grade_status': grade.status if grade else None,
              'published_result': grade.result if grade and grade.status == TeamGrade.STATUS_PUBLISHED else None}
    if schedule.status in ('cancelled', 'archived'):
        display = schedule.status
    elif history or schedule.project_version != schedule.team.project_version:
        display = 'assessed'
    elif schedule.operation_state != 'normal' and schedule.status == 'scheduled':
        display = schedule.operation_state
    elif grade:
        if reconcile_status and verdict and schedule.status == 'scheduled':
            from defense.scheduler.models import DefenseSchedule
            DefenseSchedule.objects.filter(pk=schedule.pk, status='scheduled').update(status=DefenseSchedule.STATUS_DONE)
            schedule.status = DefenseSchedule.STATUS_DONE
        from grading.grades.services import team_grading_readiness
        readiness = team_grading_readiness(grade, grade.semester, grade.scope)
        result.update(panel_evaluators_submitted=readiness['panel_evaluators_submitted'],
                      panel_evaluators_required=readiness['panel_evaluators_required'])
        if grade.status == 'published' and (not uses_verdict or grade.result == 'passed'):
            display = 'completed'
        elif grade.status == 'published' and grade.result == 'failed':
            display = 'failed'
        elif verdict == 'for_redefense' or concept_retry:
            display = 'redefense_required'
        elif verdict in ('failed', 'project_rejected'):
            display = verdict
        elif verdict == 'approved_with_revisions' and not grade.revisions_cleared_at:
            display = 'revisions_pending'
        elif verdict in TeamGrade.PASSING_VERDICTS:
            display = 'awaiting_completion' if readiness['ready'] else 'grading_incomplete'
        elif not uses_verdict and readiness['ready']:
            display = 'awaiting_completion'
        elif readiness['panel_complete']:
            display = 'awaiting_verdict' if uses_verdict else 'grading_incomplete'
        elif readiness['panel_evaluators_submitted'] or grade.panel_score is not None:
            display = 'evaluating'
        else:
            display = 'scheduled' if schedule.scheduled_date > timezone.localdate() else 'awaiting_evaluation'
    else:
        display = 'assessed' if schedule.status == 'done' else 'scheduled' if schedule.scheduled_date > timezone.localdate() else 'awaiting_evaluation'
    result['display_status'] = display
    # Preserve an explicitly completed defense when its schedule is archived.
    # A submitted score or assessed attempt is not completion.
    result['is_completed'] = bool(grade and grade.status == TeamGrade.STATUS_PUBLISHED
                                  and (not uses_verdict or grade.result == 'passed'))
    setattr(schedule, cache_key, result)
    return result
