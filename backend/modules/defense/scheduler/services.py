from rest_framework import status
from rest_framework.exceptions import ValidationError, APIException
from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from .models import DefenseSchedule
from django.db import transaction

class ScheduleDeletionBlocked(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_detail = 'This schedule has panelist grades already submitted. Deleting it will permanently remove those individual scores. Consider cancelling the schedule instead.'
    default_code = 'has_grade_data'

    def __init__(self, detail=None, code=None):
        if detail is None:
            detail = {
                'detail': self.default_detail,
                'code': self.default_code
            }
        super().__init__(detail, code)


VALID_TRANSITIONS = {
    DefenseSchedule.STATUS_SCHEDULED: [
        DefenseSchedule.STATUS_DONE,
        DefenseSchedule.STATUS_CANCELLED,
    ],
    DefenseSchedule.STATUS_DONE: [
        DefenseSchedule.STATUS_ARCHIVED,
    ],
    DefenseSchedule.STATUS_CANCELLED: [
        DefenseSchedule.STATUS_SCHEDULED,
    ],
    DefenseSchedule.STATUS_ARCHIVED: [],
}

def schedule_audit_values(schedule, **extra):
    values = {
        **audit_scope_metadata(scope=schedule.scope, team=schedule.team),
        'schedule_id': schedule.pk,
        'scheduled_date': schedule.scheduled_date.isoformat() if schedule.scheduled_date else '',
        'start_time': schedule.start_time.isoformat() if schedule.start_time else '',
        'room': schedule.room,
        'stage_label': schedule.stage_label,
    }
    values.update(extra)
    return values

@transaction.atomic
def transition_schedule_status(schedule, new_status, *, actor=None, reason='', request=None):
    """Single source of truth for schedule status transitions."""
    schedule = DefenseSchedule.objects.select_for_update().get(pk=schedule.pk)
    old_status = schedule.status
    if new_status == old_status:
        return schedule

    allowed = VALID_TRANSITIONS.get(old_status, [])
    if new_status not in allowed:
        raise ValidationError({'status': f'Cannot change status from "{old_status}" to "{new_status}".'})

    if new_status == DefenseSchedule.STATUS_DONE:
        from grading.grades.services import team_grading_readiness
        grade = schedule.grade_records.first()
        if not grade or not team_grading_readiness(grade, grade.semester, grade.scope)['ready']:
            raise ValidationError('Complete all required evaluators and grading components before closing this defense.')
    schedule.status = new_status
    schedule.revision += 1
    schedule.save(update_fields=['status', 'revision', 'updated_at'])

    # Log transition
    log_high_impact_action(
        category=SystemAuditLog.CATEGORY_SCHEDULING,
        action='schedule.status_change',
        target=schedule,
        actor=actor,
        old_values=schedule_audit_values(schedule, status=old_status),
        new_values=schedule_audit_values(schedule, status=new_status, reason=reason),
        request=request,
        reason=reason,
        strict=True,
    )
    return schedule


def deletion_blockers(schedule):
    """Protect authored content; scaffold rows and zero-valued scores differ."""
    from django.db.models import Q
    from defense.minutes.models import DefenseMinutes
    from grading.grades.models import TeamGrade
    blockers = []
    if schedule.panelist_grade_submissions.exists():
        blockers.append('This schedule has panelist grades already submitted (including voided evaluations).')
    if any(any(item.get('criteria_scores') or str(item.get('remarks', '')).strip()
               for item in draft.submissions if isinstance(item, dict))
           for draft in schedule.evaluation_drafts.all()):
        blockers.append('Saved evaluation drafts contain scores or remarks.')
    minutes = DefenseMinutes.objects.filter(schedule=schedule).first()
    if minutes and (minutes.status != 'draft' or minutes.pdf_file or minutes.revisions.exists()
                    or minutes.documenter_signed_at or minutes.adviser_signed_at or minutes.chairman_signed_at
                    or any(c.comments.strip() for c in minutes.panelist_comments.all())):
        blockers.append('Minutes contain comments, signatures, or a generated document.')
    grades = TeamGrade.objects.filter(team_id=schedule.team_id, semester_id=schedule.semester_id, scope=schedule.scope)
    grades = grades.filter(defense_stage_id=schedule.defense_stage_id) if schedule.scope == 'capstone' else grades.filter(stage_label__iexact=schedule.event_name)
    for grade in grades:
        if (any(getattr(grade, name) is not None for name in ('panel_score', 'adviser_score', 'peer_score', 'final_grade'))
                or grade.verdict or grade.status == 'published' or grade.published_at
                or grade.breakdowns.exists() or grade.peer_evaluation_submissions.exists()
                or grade.panelist_submissions.exists() or grade.attempt_history.exists() or grade.corrections.exists()
                or grade.student_grades.filter(Q(panel_score__isnull=False) | Q(adviser_score__isnull=False) | Q(peer_score__isnull=False) | Q(final_grade__isnull=False)).exists()):
            blockers.append('Grades, a verdict, or correction history have been recorded.')
            break
    if schedule.status in (DefenseSchedule.STATUS_DONE, DefenseSchedule.STATUS_ARCHIVED):
        blockers.append('Completed and archived schedules must be preserved.')
    return blockers


@transaction.atomic
def delete_schedule(schedule, *, actor=None, request=None, reason='Empty schedule removal'):
    """Single source of truth for deleting a defense schedule securely."""
    schedule = DefenseSchedule.objects.select_for_update().get(pk=schedule.pk)
    blockers = deletion_blockers(schedule)
    if blockers:
        raise ScheduleDeletionBlocked(detail={'detail': ' '.join(blockers), 'code': 'has_grade_data', 'blockers': blockers})

    schedule_pk = schedule.pk
    audit_values = schedule_audit_values(schedule, status=schedule.status)
    schedule.delete()

    log_high_impact_action(
        category=SystemAuditLog.CATEGORY_SCHEDULING,
        action='schedule.delete',
        target=schedule,
        target_type='DefenseSchedule',
        target_id=schedule_pk,
        old_values=audit_values,
        new_values={'deleted': True},
        actor=actor,
        request=request,
        reason=reason,
        strict=True,
    )
