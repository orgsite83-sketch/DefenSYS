"""Presentation status follows recorded assessment work, never elapsed slots."""
from django.utils import timezone
from grading.grades.models import TeamGrade, GradeAttemptHistory

DISPLAY_STATUSES = ['scheduled', 'awaiting_evaluation', 'evaluating', 'awaiting_verdict', 'awaiting_concept_selection',
    'revisions_pending', 'redefense_required', 'grading_incomplete', 'awaiting_completion',
    'pending_post_defense',
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
    metadata = evidence.outcome_metadata if evidence else {}
    from grading.grades.outcome_rules import automatic_outcomes
    concept_retry = False
    if schedule.scope == 'pit':
        from repository.deliverables.models import ConceptRound
        concept_retry = ConceptRound.objects.filter(schedule=schedule, verdict='for_redefense').exists()
    result = {'verdict': 'failed' if metadata.get('closure', {}).get('failed') else verdict,
              'hearing_outcome': verdict, 'outcome_metadata': metadata,
              'automatic_outcomes': automatic_outcomes(schedule),
              'attempt_count': grade.attempt_count if grade else history.attempt_number if history else 1,
              'panel_evaluators_submitted': 0, 'panel_evaluators_required': 0,
              'revisions_cleared_at': str(evidence.revisions_cleared_at) if verdict and evidence.revisions_cleared_at else None,
              'revision_deadline': str(evidence.revision_deadline) if verdict and evidence.revision_deadline else None,
              'verdict_remarks': evidence.verdict_remarks if verdict else '',
              # These fields belong to this schedule, unlike the board's legacy
              # grade_status lookup which can fall back to another stage attempt.
              'grade_status': grade.status if grade else None,
              'published_result': grade.result if grade and grade.status == TeamGrade.STATUS_PUBLISHED else None}
    completed = False
    if grade:
        from grading.grades.services import team_grading_readiness
        readiness = team_grading_readiness(grade, grade.semester, grade.scope)
        from grading.grades.outcome_rules import outcome_payload
        rule = outcome_payload(grade) if uses_verdict else None
        from grading.grades.defense_workflow import legacy_finalized_pass
        legacy_pass = legacy_finalized_pass(grade)
        post_complete = None
        approved = uses_verdict and verdict in TeamGrade.PASSING_VERDICTS
        if approved or legacy_pass:
            from repository.deliverables.services import post_deliverables_complete
            post_complete = post_deliverables_complete(grade.team, grade.stage_label)
        completed = grade.status == TeamGrade.STATUS_PUBLISHED
        grading_complete = (readiness['ready'] and grade.is_complete) or (
            not rule and completed and grade.final_grade is not None)
        if uses_verdict:
            from grading.grades.defense_workflow import passed_and_cleared
            completed = (completed and (passed_and_cleared(grade) or legacy_pass) and post_complete is True
                         and (not rule or readiness['ready'] and grade.is_complete))
        result.update(panel_evaluators_submitted=readiness['panel_evaluators_submitted'],
                      panel_evaluators_required=readiness['panel_evaluators_required'],
                      panel_complete=readiness['panel_complete'],
                      grading_complete=grading_complete,
                      missing_components=[] if grading_complete else readiness['missing_components'],
                      assessment_finalized=grade.status == TeamGrade.STATUS_PUBLISHED,
                      defense_approved=approved if uses_verdict and not legacy_pass else None, post_defense_complete=post_complete,
                      outcome_rule=rule)
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
        if grade.closed_as_failed:
            display = 'failed'
        elif verdict == 'for_redefense' or concept_retry:
            display = 'redefense_required'
        elif verdict in ('failed', 'project_rejected'):
            display = verdict
        elif completed:
            display = 'completed'
        elif verdict == 'approved_with_revisions' and not grade.revisions_cleared_at:
            display = 'revisions_pending'
        elif (approved or legacy_pass) and not post_complete:
            display = 'pending_post_defense'
        elif verdict in TeamGrade.PASSING_VERDICTS:
            display = 'awaiting_completion' if readiness['ready'] and grade.is_complete else 'grading_incomplete'
        elif not uses_verdict and readiness['ready']:
            display = 'awaiting_completion'
        elif readiness['panel_complete']:
            if rule and rule['automatic']:
                display = 'awaiting_concept_selection' if rule['per_concept'] else 'evaluating'
            else:
                display = ('awaiting_concept_selection' if rule and rule['per_concept']
                           and rule['outcome'] == 'approved' else 'awaiting_verdict') if uses_verdict else 'grading_incomplete'
        elif readiness['panel_evaluators_submitted'] or grade.panel_score is not None:
            display = 'evaluating'
        else:
            display = 'scheduled' if schedule.scheduled_date > timezone.localdate() else 'awaiting_evaluation'
    else:
        display = 'assessed' if schedule.status == 'done' else 'scheduled' if schedule.scheduled_date > timezone.localdate() else 'awaiting_evaluation'
    result['display_status'] = display
    # Preserve an explicitly completed defense when its schedule is archived.
    # A submitted score or assessed attempt is not completion.
    result['is_completed'] = bool(completed)
    setattr(schedule, cache_key, result)
    return result
