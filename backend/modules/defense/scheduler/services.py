from rest_framework import status
from rest_framework.exceptions import ValidationError, APIException
from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from .models import DefenseSchedule

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

def transition_schedule_status(schedule, new_status, *, actor=None, reason='', request=None):
    """Single source of truth for schedule status transitions."""
    old_status = schedule.status
    if new_status == old_status:
        return schedule

    allowed = VALID_TRANSITIONS.get(old_status, [])
    if new_status not in allowed:
        raise ValidationError({'status': f'Cannot change status from "{old_status}" to "{new_status}".'})

    schedule.status = new_status
    schedule.save(update_fields=['status', 'updated_at'])

    # Log transition
    log_high_impact_action(
        category=SystemAuditLog.CATEGORY_SCHEDULING,
        action='schedule.status_change',
        target=schedule,
        actor=actor,
        old_values=schedule_audit_values(schedule, status=old_status),
        new_values=schedule_audit_values(schedule, status=new_status, reason=reason),
        request=request,
    )
    return schedule


def delete_schedule(schedule, *, actor=None, request=None):
    """Single source of truth for deleting a defense schedule securely."""
    if schedule.panelist_grade_submissions.exists():
        raise ScheduleDeletionBlocked()

    if schedule.status in (DefenseSchedule.STATUS_DONE, DefenseSchedule.STATUS_ARCHIVED):
        raise ScheduleDeletionBlocked(
            detail={'warning': 'Cannot delete a completed or archived schedule.'},
        )

    if schedule.status == DefenseSchedule.STATUS_SCHEDULED:
        from django.utils import timezone
        from datetime import datetime
        now = timezone.localtime()
        scheduled_start = timezone.make_aware(
            datetime.combine(schedule.scheduled_date, schedule.start_time),
            timezone.get_current_timezone(),
        )
        if now >= scheduled_start:
            raise ScheduleDeletionBlocked(
                detail={'warning': 'Cannot delete an ongoing defense schedule.'},
            )

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
    )

