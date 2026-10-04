"""Source-level corrections and explicit published amendments with permanent evidence."""
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework import serializers

from authentication_access_control.audit import log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from defense.scheduler.operations import StaleOperation
from .models import TeamGrade, PanelistCriterionScore, PanelistGradeSubmission, GradeBreakdown
from .correction_models import GradeCorrection


def protected_grade(grade):
    from .services import group_settings_for_grade
    return (grade.status == 'published' or bool(group_settings_for_grade(grade).get('is_officially_complete'))
            or bool(grade.schedule_id and grade.schedule.status in ('done', 'archived')))


def evaluator_completion(grade):
    """Require a complete team/member evaluation from every assigned identity."""
    schedule = grade.schedule
    if not schedule:
        return {'submitted': 0, 'required': 0}
    expected = {(pid, None) for pid in schedule.panel_assignments.values_list('panelist_id', flat=True)}
    expected |= {(None, str(pk)) for pk in schedule.guest_invitations.filter(is_active=True).values_list('pk', flat=True)}
    expected |= {(None, str(pk)) for pk in schedule.guest_panelist_codes.filter(is_active=True).values_list('pk', flat=True)}
    rows = list(grade.panelist_submissions.filter(schedule=schedule, is_void=False).prefetch_related('criterion_scores'))
    from defense.scheduler.panelist_evaluation import validate_evaluation_submissions
    complete = 0
    for pid, gid in expected:
        submissions = [{'student_id': row.student_id,
                        'criteria_scores': [{'criterion_id': score.criterion_id, 'score': str(score.score)} for score in row.criterion_scores.all()],
                        'remarks': row.remarks}
                       for row in rows if row.panelist_id == pid and row.guest_code_id == gid]
        try:
            validate_evaluation_submissions(schedule, submissions)
            complete += 1
        except Exception as exc:
            from django.core.exceptions import ValidationError as DjangoValidationError
            if not isinstance(exc, DjangoValidationError):
                raise
    return {'submitted': complete, 'required': len(expected)}


def snapshot(grade):
    grade.refresh_from_db()
    fields = ('panel_score', 'adviser_score', 'peer_score', 'final_grade', 'status', 'verdict',
              'panel_score_is_override', 'adviser_score_is_override', 'peer_score_is_override')
    values = {name: str(getattr(grade, name)) if isinstance(getattr(grade, name), Decimal) else getattr(grade, name) for name in fields}
    values['updated_at'] = grade.updated_at.isoformat()
    values['grade_id'] = grade.pk
    values['team_name'] = grade.team.name
    values['stage_label'] = grade.stage_label
    values['scope'] = grade.scope
    values['adviser_grading_enabled'] = grade.scope == 'capstone' and grade.semester.capstone_adviser_grading_enabled
    values['individual_grading'] = bool(grade.schedule_id and grade.schedule.rubric and grade.schedule.rubric.target_type in ('individual', 'both'))
    values['attempt_count'] = grade.attempt_count
    values['published_at'] = grade.published_at.isoformat() if grade.published_at else None
    values['schedule_id'] = grade.schedule_id
    values['schedule_revision'] = grade.schedule.revision if grade.schedule_id else None
    values['team_status'] = grade.team.status
    values['criteria'] = [{'id': row.pk, 'submission_id': row.submission_id, 'score': str(row.score), 'max_score': str(row.max_score_snapshot),
                           'criterion': row.criterion_name_snapshot, 'student_id': row.submission.student_id,
                           'student_name': (row.submission.student.get_full_name() or row.submission.student.username) if row.submission.student else 'Team',
                           'evaluator': (row.submission.panelist.get_full_name() or row.submission.panelist.username) if row.submission.panelist else row.submission.guest_name}
                          for row in PanelistCriterionScore.objects.filter(submission__team_grade=grade).select_related('submission__panelist', 'submission__student').order_by('pk')]
    values['submissions'] = list(grade.panelist_submissions.order_by('pk').values('id', 'is_void'))
    values['students'] = [{'id': row.pk, 'student_name': row.student.get_full_name() or row.student.username, 'panel_score': str(row.panel_score) if row.panel_score is not None else None,
                          'adviser_score': str(row.adviser_score) if row.adviser_score is not None else None,
                          'peer_score': str(row.peer_score) if row.peer_score is not None else None,
                          'final_grade': str(row.final_grade) if row.final_grade is not None else None}
                         for row in grade.student_grades.select_related('student').order_by('pk')]
    return values


def correction_payload(item):
    return {'id': item.pk, 'status': item.status, 'reason': item.reason, 'approval_reason': item.approval_reason,
            'requested_by': item.requested_by_id, 'requested_by_name': (item.requested_by.get_full_name() or item.requested_by.username) if item.requested_by else '',
            'approved_by': item.approved_by_id,
            'approved_by_name': (item.approved_by.get_full_name() or item.approved_by.username) if item.approved_by else '',
            'requires_approval': item.requires_approval,
            'changes': item.changes, 'before': item.before, 'after': item.after,
            'created_at': item.created_at.isoformat(), 'applied_at': item.applied_at.isoformat() if item.applied_at else None}


def correction_details(grade):
    rows = []
    guest_references = {str(i['id']): i['email'] for i in grade.schedule.guest_invitations.values('id', 'email')} if grade.schedule_id else {}
    for submission in grade.panelist_submissions.select_related('panelist', 'student').prefetch_related('criterion_scores').order_by('pk'):
        evaluator = (submission.panelist.get_full_name() or submission.panelist.username) if submission.panelist else submission.guest_name
        for score in submission.criterion_scores.all():
            rows.append({'id': score.pk, 'submission_id': submission.pk, 'evaluator': evaluator,
                         'evaluator_key': f'faculty:{submission.panelist_id}' if submission.panelist_id else f'guest:{submission.guest_code_id}',
                         'evaluator_reference': submission.panelist.username if submission.panelist_id else guest_references.get(submission.guest_code_id, 'External evaluator'),
                         'student_id': submission.student_id,
                         'student_reference': submission.student.username if submission.student_id else 'Team',
                         'student': (submission.student.get_full_name() or submission.student.username) if submission.student else 'Team',
                         'criterion': score.criterion_name_snapshot, 'score': str(score.score),
                         'max_score': str(score.max_score_snapshot), 'is_void': submission.is_void})
    from .services import group_settings_for_grade
    return {'scores': rows, 'updated_at': grade.updated_at.isoformat(),
            'requires_approval': protected_grade(grade),
            'history': [correction_payload(c) for c in grade.corrections.select_related('requested_by', 'approved_by')],
            'completion': evaluator_completion(grade), 'grade': snapshot(grade)}


def _decimal(value, maximum=Decimal('100')):
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        raise ValidationError('Enter a numeric score.')
    if not number.is_finite() or number < 0 or number > maximum:
        raise ValidationError(f'Score must be between 0 and {maximum}.')
    return number.quantize(Decimal('0.01'))


def _source_breakdowns(submission, score=None):
    from .services import panelist_remark_key_for_user, guest_panelist_remark_key
    key = panelist_remark_key_for_user(submission.panelist) if submission.panelist else guest_panelist_remark_key(submission.guest_name, submission.guest_code)
    from django.db.models import Q
    rows = GradeBreakdown.objects.filter(team_grade=submission.team_grade, evaluation_type='panel', student_id=submission.student_id)
    rows = rows.filter(Q(source_submission=submission) | Q(source_submission__isnull=True, remarks__startswith=key))
    if score:
        rows = rows.filter(criterion_name=score.criterion_name_snapshot, display_order=score.display_order)
    return rows


def _perform_change(grade, changes):
    from .services import recompute_panel_score
    if not isinstance(changes, dict) or len(changes) != 1:
        raise ValidationError('Correct one criterion, one evaluation, or aggregate scores per request.')
    if 'criterion' in changes:
        item = changes['criterion']
        if not isinstance(item, dict) or set(item) != {'id', 'score'}:
            raise ValidationError('Select a criterion score and its corrected value.')
        row_id = serializers.IntegerField(min_value=1).run_validation(item['id'])
        row = PanelistCriterionScore.objects.select_related('submission__panelist').filter(pk=row_id, submission__team_grade=grade).first()
        if not row or row.submission.is_void:
            raise ValidationError('This score is missing or belongs to a voided evaluation.')
        if grade.panel_score_is_override:
            raise ValidationError('An aggregate panel override is active. Resolve that override before correcting the source evaluation.')
        value = _decimal(item['score'], row.max_score_snapshot)
        if value == row.score:
            raise ValidationError('The corrected score matches the recorded score.')
        row.score = value
        row.save(update_fields=['score', 'updated_at'])
        _source_breakdowns(row.submission, row).update(score=value, source_submission=row.submission)
        recompute_panel_score(grade)
    elif 'void_submission' in changes:
        submission_id = serializers.IntegerField(min_value=1).run_validation(changes['void_submission'])
        submission = grade.panelist_submissions.filter(pk=submission_id, is_void=False).first()
        if not submission:
            raise ValidationError('Select an active evaluation belonging to this grade.')
        if grade.status == 'published':
            raise ValidationError('A published grade cannot become incomplete. Resolve the published record before voiding an evaluation.')
        if grade.panel_score_is_override:
            raise ValidationError('Resolve the aggregate panel override before voiding a source evaluation.')
        submission.is_void = True
        submission.voided_at = timezone.now()
        submission.save(update_fields=['is_void', 'voided_at', 'updated_at'])
        _source_breakdowns(submission).update(is_void=True, source_submission=submission)
        recompute_panel_score(grade)
    elif 'aggregate' in changes:
        values = changes['aggregate']
        if not isinstance(values, dict) or not values or set(values) - {'panel_score', 'adviser_score', 'peer_score'}:
            raise ValidationError('Choose supported grade components.')
        if 'panel_score' in values and grade.panelist_submissions.exists():
            raise ValidationError('Correct the panelist criterion score instead of overriding its calculated average.')
        if 'adviser_score' in values and (grade.scope == 'pit' or not grade.semester.capstone_adviser_grading_enabled):
            raise ValidationError({'adviser_score': 'Adviser grading is disabled for this grade.'})
        if grade.student_grades.exists() and grade.schedule_id and grade.schedule.rubric and grade.schedule.rubric.target_type in ('individual', 'both'):
            raise ValidationError('Use the source evaluation for individual grading; an aggregate override would not correct student scores.')
        changed = False
        for name, value in values.items():
            value = _decimal(value) if value is not None else None
            changed |= getattr(grade, name) != value
            setattr(grade, name, value)
            setattr(grade, name.replace('_score', '_score_is_override'), True)
        if not changed:
            raise ValidationError('There are no changed scores.')
        grade.save()
    elif changes.get('clear_panel_override') is True:
        if not grade.panel_score_is_override:
            raise ValidationError('There is no aggregate panel override to remove.')
        grade.panel_score_is_override = False
        grade.save()
        recompute_panel_score(grade)
    else:
        raise ValidationError('Unsupported correction type.')
    grade.refresh_from_db()


def _change(grade, changes):
    from django.core.exceptions import ValidationError as DjangoValidationError
    try:
        _perform_change(grade, changes)
    except DjangoValidationError as exc:
        raise ValidationError(exc.message_dict if hasattr(exc, 'message_dict') else exc.messages) from exc


def _check_progression(before, after, protected):
    if not protected:
        return
    def passed(value):
        from grading.constants import PASS_GRADE_THRESHOLD
        return value is not None and Decimal(value) >= PASS_GRADE_THRESHOLD
    pairs = [(before['final_grade'], after['final_grade'])]
    previous_students = {row['id']: row for row in before['students']}
    pairs += [(previous_students[row['id']]['final_grade'], row['final_grade']) for row in after['students'] if row['id'] in previous_students]
    if any(passed(a) != passed(b) for a, b in pairs):
        raise ValidationError('This amendment changes a passing result. Reopen the stage and reconcile downstream progression before applying it.')


@transaction.atomic
def request_correction(grade_id, actor, data, request=None):
    # Match the schedule-then-grade lock order used by submissions and operations.
    schedule_id = TeamGrade.objects.values_list('schedule_id', flat=True).get(pk=grade_id)
    if schedule_id:
        from defense.scheduler.models import DefenseSchedule
        DefenseSchedule.objects.select_for_update().get(pk=schedule_id)
    grade = TeamGrade.objects.select_for_update().get(pk=grade_id)
    reason = serializers.CharField(min_length=5, max_length=2000).run_validation(data.get('reason', ''))
    before = snapshot(grade)
    if data.get('expected_updated_at') != before['updated_at']:
        raise StaleOperation()
    from .services import group_settings_for_grade
    protected = protected_grade(grade)
    changes = data.get('changes')
    # Calculate a real preview inside a savepoint; never persist preview writes.
    with transaction.atomic():
        _change(grade, changes)
        after = snapshot(grade)
        _check_progression(before, after, protected)
        transaction.set_rollback(True)
    if data.get('preview') is True:
        return {'before': before, 'after': after, 'requires_approval': protected}
    grade.refresh_from_db()
    correction = GradeCorrection.objects.create(grade=grade, requested_by=actor, reason=reason,
        changes=changes, before=before, after=after, requires_approval=protected)
    if not protected:
        _apply(correction, grade, actor, reason, request)
    else:
        log_high_impact_action(category=SystemAuditLog.CATEGORY_GRADE_CENTER, action='grade.amendment_requested', target=grade,
            old_values=before, new_values={'correction_id': correction.pk, 'changes': changes}, reason=reason, actor=actor, request=request, strict=True)
    return correction_payload(correction)


def _apply(correction, grade, actor, approval_reason, request):
    _change(grade, correction.changes)
    after = snapshot(grade)
    _check_progression(correction.before, after, correction.requires_approval)
    if 'void_submission' in correction.changes:
        grade.panelist_submissions.filter(pk=correction.changes['void_submission']).update(void_reason=correction.reason)
    correction.after = after
    correction.status = 'applied'
    correction.approved_by = actor
    correction.approval_reason = approval_reason
    correction.applied_at = timezone.now()
    correction.save()
    log_high_impact_action(category=SystemAuditLog.CATEGORY_GRADE_CENTER, action='grade.correction_applied', target=grade,
        old_values=correction.before, new_values={**after, 'correction_id': correction.pk, 'original_requester': correction.requested_by_id},
        reason=correction.reason, actor=actor, request=request, strict=True)


@transaction.atomic
def review_correction(grade_id, correction_id, actor, data, request=None):
    schedule_id = TeamGrade.objects.values_list('schedule_id', flat=True).get(pk=grade_id)
    if schedule_id:
        from defense.scheduler.models import DefenseSchedule
        DefenseSchedule.objects.select_for_update().get(pk=schedule_id)
    grade = TeamGrade.objects.select_for_update().get(pk=grade_id)
    item = GradeCorrection.objects.select_for_update().filter(pk=correction_id, grade=grade).first()
    if not item or item.status != 'pending':
        raise ValidationError('This amendment is missing or has already been reviewed.')
    reason = str(data.get('reason', '')).strip()
    if len(reason) < 5:
        raise ValidationError('Enter an approval or rejection reason.')
    if data.get('action') == 'reject':
        item.status, item.approved_by, item.approval_reason = 'rejected', actor, reason
        item.save()
        log_high_impact_action(category=SystemAuditLog.CATEGORY_GRADE_CENTER, action='grade.amendment_rejected', target=grade,
            new_values={'correction_id': item.pk}, reason=reason, actor=actor, request=request, strict=True)
    elif data.get('action') == 'approve' and data.get('acknowledge_published_change') is True:
        if snapshot(grade) != item.before:
            raise StaleOperation('The grade changed after this amendment was requested. Reject it and request a fresh correction.')
        _apply(item, grade, actor, reason, request)
    else:
        raise ValidationError('Explicitly acknowledge the published amendment before approving it.')
    return correction_payload(item)
