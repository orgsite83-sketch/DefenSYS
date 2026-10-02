"""Shared day-based availability, draft context, and complete-evaluation validation."""

import hashlib
import json
from decimal import Decimal, InvalidOperation

from django.core.exceptions import ValidationError
from django.utils import timezone

from grading.grades.models import TeamGrade
from .models import DefenseSchedule, PanelistEvaluationDraft


def grading_unavailable_reason(schedule, grade=None):
    if schedule.status != DefenseSchedule.STATUS_SCHEDULED:
        return 'This defense is closed or cancelled.'
    if schedule.scheduled_date > timezone.localdate():
        return f'Grading is locked until the scheduled date: {schedule.scheduled_date.strftime("%B %d, %Y")}.'
    if not schedule.rubric_id:
        return 'A panel rubric must be configured before grading.'
    if grade and grade.status in TeamGrade.LOCKED_STATUSES:
        return 'Grades for this defense have been finalized.'
    return ''


def evaluation_context(schedule, grade=None):
    rubric = schedule.rubric
    context = {
        'schedule': schedule.pk,
        'date': str(schedule.scheduled_date),
        'rubric': schedule.rubric_id,
        'target': rubric.target_type if rubric else None,
        'criteria': list(rubric.criteria.order_by('id').values(
            'id', 'name', 'max_score', 'target_type', 'scale',
        )) if rubric else [],
        'members': sorted(schedule.team.memberships.values_list('student_id', flat=True)),
        'attempt': grade.attempt_count if grade else 1,
    }
    return hashlib.sha256(json.dumps(context, sort_keys=True, default=str).encode()).hexdigest()


def draft_payload(draft, context):
    if draft is None or draft.context_signature != context:
        return None
    return {'submissions': draft.submissions, 'saved_at': draft.updated_at.isoformat()}


def validate_evaluation_submissions(schedule, submissions, *, partial=False):
    """Validate every member before any final write, or allow missing scores in drafts."""
    if not schedule.rubric_id:
        raise ValidationError('A panel rubric must be configured before grading.')
    if not isinstance(submissions, list) or not submissions:
        raise ValidationError('submissions must be a non-empty list.')
    rubric = schedule.rubric
    criteria = list(rubric.criteria.all())
    if not criteria:
        raise ValidationError('The assigned panel rubric has no criteria.')
    members = set(schedule.team.memberships.values_list('student_id', flat=True))
    expected = {}
    if rubric.target_type == 'team':
        expected[None] = criteria
    elif rubric.target_type == 'individual':
        expected = {student_id: criteria for student_id in members}
    else:
        team_criteria = [c for c in criteria if c.target_type == 'team']
        individual_criteria = [c for c in criteria if c.target_type == 'individual']
        if team_criteria:
            expected[None] = team_criteria
        if individual_criteria:
            expected.update({student_id: individual_criteria for student_id in members})
    if not expected or (rubric.target_type == 'individual' and not members):
        raise ValidationError('This team has no members to grade.')
    seen = set()
    result = []
    for submission in submissions:
        if not isinstance(submission, dict):
            raise ValidationError('Each submission must be an object.')
        raw_student_id = submission.get('student_id')
        try:
            student_id = int(raw_student_id) if raw_student_id not in (None, '') else None
        except (ValueError, TypeError) as exc:
            raise ValidationError('student_id must be an integer.') from exc
        if student_id not in expected:
            raise ValidationError('The submission does not match this team and rubric target.')
        if student_id in seen:
            raise ValidationError('Duplicate student or team submissions are not allowed.')
        seen.add(student_id)
        allowed = {c.pk: c for c in expected[student_id]}
        scores = submission.get('criteria_scores', [])
        if not isinstance(scores, list):
            raise ValidationError('criteria_scores must be a list.')
        # Preserve the supported legacy APK payload only for complete submissions.
        if not partial and len(scores) == len(allowed) and all(
            isinstance(s, dict) and s.get('criterion_id', s.get('id')) is None for s in scores
        ):
            scores = [dict(s, criterion_id=c.pk) for s, c in zip(scores, expected[student_id])]
        scored = set()
        clean_scores = []
        for item in scores:
            if not isinstance(item, dict):
                raise ValidationError('Each criterion score must be an object.')
            try:
                criterion_id = int(item.get('criterion_id', item.get('id')))
                score = Decimal(str(item.get('score')))
            except (TypeError, ValueError, InvalidOperation) as exc:
                raise ValidationError('Each score must have a valid criterion ID and numeric score.') from exc
            if criterion_id not in allowed or criterion_id in scored:
                raise ValidationError('Submitted criteria must exactly match the assigned panel rubric.')
            if not score.is_finite() or score < 0 or score > allowed[criterion_id].max_score:
                raise ValidationError('Score must be between 0 and max score.')
            scored.add(criterion_id)
            clean_scores.append({'criterion_id': criterion_id, 'score': float(score)})
        if not partial and scored != set(allowed):
            raise ValidationError('Score every required criterion before submitting.')
        remarks = submission.get('remarks', '')
        if not isinstance(remarks, str):
            raise ValidationError('Remarks must be text.')
        result.append({'student_id': student_id, 'criteria_scores': clean_scores, 'remarks': remarks})
    if not partial and seen != set(expected):
        raise ValidationError('Complete the evaluation for every team member before submitting.')
    return result


def save_evaluation_draft(schedule, payload, *, panelist=None, guest=None):
    owner = {'panelist': panelist} if panelist else {'guest_code_id': str(guest.guest_code_id)}
    grade = schedule.grade_records.first()
    reason = grading_unavailable_reason(schedule, grade)
    if reason:
        raise ValidationError(reason)
    if schedule.panelist_grade_submissions.filter(**owner).exists():
        raise ValidationError('Your grades have already been submitted and locked.')
    context = evaluation_context(schedule, grade)
    if payload.get('evaluation_context') != context:
        raise ValidationError('This evaluation has changed. Refresh the assignment before saving.')
    submissions = validate_evaluation_submissions(schedule, payload.get('submissions'), partial=True)
    draft, _ = PanelistEvaluationDraft.objects.update_or_create(
        schedule=schedule, **owner,
        defaults={'context_signature': context, 'submissions': submissions},
    )
    return draft_payload(draft, context)
