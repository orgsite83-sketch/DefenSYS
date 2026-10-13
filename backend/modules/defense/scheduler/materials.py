"""Audited grace deadlines and idempotent in-app material reminders."""
import hashlib
import json
from datetime import datetime, timedelta

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import F, Q
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied, ValidationError

from authentication_access_control.audit import audit_scope_metadata, log_high_impact_action
from authentication_access_control.models import SystemAuditLog
from authentication_access_control.scopes import manageable_schedules_for, visible_schedules_for
from repository.deliverables.timing import defense_starts_at, materials_readiness, due_before_defense, deadline_for
from student_teams.models import StudentTeam
from .models import DefenseSchedule
from .operations import StaleOperation


class MaterialDeadlineSerializer(serializers.Serializer):
    deadline = serializers.DateTimeField()
    reason = serializers.CharField(min_length=5, max_length=2000, allow_blank=False)
    revision = serializers.IntegerField(min_value=1)


def student_ids(team):
    return set(team.memberships.values_list('student_id', flat=True)) | ({team.leader_id} if team.leader_id else set())


def deadline_summary(schedule):
    readiness = materials_readiness(schedule)
    if not readiness['required_total']:
        return ''
    return ', '.join(f"{item['label']}: {timezone.localtime(datetime.fromisoformat(item['due_at'])).strftime('%b %d, %Y %I:%M %p')}"
                    for item in readiness['items'])


def notify_deadline(schedule, actor=None, *, extended=False):
    from notifications.models import Notification

    deadlines = deadline_summary(schedule)
    if not deadlines:
        return
    title = 'Defense material deadline extended' if extended else 'Defense materials due'
    reason = f' Reason: {schedule.materials_deadline_reason}' if extended else ''
    Notification.objects.bulk_create([
        Notification(recipient_id=pk, sender=actor, workspace='student', category='DEFENSE',
                     title=title, message=f'{schedule.team.name}: {schedule.stage_label}, {schedule.scheduled_date} '
                     f'{schedule.start_time}, {schedule.room}. Upload deadlines: {deadlines}.{reason}',
                     action_payload={'team_id': schedule.team_id, 'stage_label': schedule.stage_label,
                                     'schedule_id': schedule.pk, 'deliverable_task': 'materials'})
        for pk in student_ids(schedule.team)
    ])


@transaction.atomic
def extend_material_deadline(actor, schedule_id, data, *, request=None):
    scoped = manageable_schedules_for(actor).filter(pk=schedule_id).first()
    if scoped is None:
        raise PermissionDenied('This defense is outside your management scope.')
    StudentTeam.objects.select_for_update().get(pk=scoped.team_id)
    schedule = manageable_schedules_for(actor).select_for_update(of=('self',)).filter(pk=schedule_id).first()
    if schedule is None:
        raise StaleOperation()
    if schedule.revision != data['revision']:
        raise StaleOperation()
    now = timezone.now()
    if (schedule.status != 'scheduled' or schedule.project_version != schedule.team.project_version or
            schedule.semester_id != schedule.team.semester_id or now >= defense_starts_at(schedule)):
        raise ValidationError('Only an upcoming current-project defense can receive a grace deadline.')
    if schedule.panelist_grade_submissions.filter(is_void=False).exists():
        raise ValidationError('Presentation materials are locked after evaluation begins.')
    from grading.grades.models import TeamGrade
    if TeamGrade.objects.filter(schedule=schedule, status__in=TeamGrade.LOCKED_STATUSES).exists():
        raise ValidationError('Presentation materials for finalized grades are locked.')
    readiness = materials_readiness(schedule)
    if not readiness['required_total']:
        raise ValidationError('This defense has no required materials with defense deadlines.')
    deadline = data['deadline']
    earliest = min(datetime.fromisoformat(item['due_at']) for item in readiness['items'])
    if deadline <= now or deadline <= earliest or deadline > defense_starts_at(schedule):
        raise ValidationError({'deadline': 'Choose a later deadline in the future, at or before the defense starts.'})
    context = {**audit_scope_metadata(scope=schedule.scope, team=schedule.team),
               'stage_label': schedule.stage_label, 'semester_id': schedule.semester_id, 'project_version': schedule.project_version}
    before_summary = deadline_summary(schedule)
    old = {**context, 'deadline': schedule.materials_deadline_override.isoformat() if schedule.materials_deadline_override else None,
           'reason': schedule.materials_deadline_reason, 'revision': schedule.revision}
    schedule.materials_deadline_override = deadline
    schedule.materials_deadline_reason = data['reason']
    schedule.materials_notice_key = ''
    schedule.revision += 1
    schedule.save(update_fields=['materials_deadline_override', 'materials_deadline_reason',
                                'materials_notice_key', 'revision', 'updated_at'])
    log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING, action='schedule.material_deadline_extended',
        target=schedule, old_values=old, new_values={**context, 'deadline': deadline.isoformat(), 'revision': schedule.revision,
            'change_details': [{'field': 'materials_deadline', 'label': 'Material submission deadline',
                                'before': before_summary, 'after': deadline_summary(schedule)}]},
        reason=data['reason'], actor=actor, request=request, strict=True)
    notify_deadline(schedule, actor, extended=True)
    return schedule


@transaction.atomic
def notify_overdue(schedule_id):
    from notifications.models import Notification

    schedule = DefenseSchedule.objects.select_related('team', 'defense_stage', 'semester').select_for_update(
        of=('self',)).filter(pk=schedule_id).first()
    if schedule is None:
        return False
    if (schedule.status != 'scheduled' or schedule.project_version != schedule.team.project_version or
            schedule.semester_id != schedule.team.semester_id):
        return False
    readiness = materials_readiness(schedule)
    if not readiness['overdue']:
        return False
    key = hashlib.sha256(json.dumps([(item['id'], item['due_at']) for item in readiness['items']]).encode()).hexdigest()
    if schedule.materials_notice_key == key:
        return False
    targets = {(pk, 'student') for pk in student_ids(schedule.team)}
    managers = get_user_model().objects.filter(is_active=True).filter(Q(role='admin') | Q(is_superuser=True))
    targets |= {(pk, 'admin') for pk in managers.values_list('pk', flat=True)}
    if schedule.scope == 'pit':
        from authentication_access_control.scopes import _pit_year
        targets |= {(person.pk, 'pit_lead') for person in get_user_model().objects.filter(is_active=True, is_pit_lead=True)
                    if _pit_year(person) and _pit_year(person) == schedule.team.year_level}
    labels = ', '.join(item['label'] for item in readiness['overdue'])
    Notification.objects.bulk_create([
        Notification(recipient_id=pk, workspace=workspace, category='DEFENSE', priority='HIGH',
                     title='Defense materials overdue', message=f'{schedule.team.name}: {labels} missed the '
                     f'upload deadline for {schedule.stage_label}. An administrator can extend the deadline or reschedule.',
                     action_payload={'team_id': schedule.team_id, 'stage_label': schedule.stage_label,
                                     'schedule_id': schedule.pk, 'deliverable_task': 'materials'})
        for pk, workspace in sorted(targets)
    ])
    # Updating this marker must not change academic progress or schedule revision.
    DefenseSchedule.objects.filter(pk=schedule.pk).update(materials_notice_key=key)
    return True


def sync_overdue_notifications(actor=None):
    """Called by the inbox and by the scheduled management command."""
    base = visible_schedules_for(actor) if actor else DefenseSchedule.objects.all()
    schedules = base.filter(status='scheduled', project_version=F('team__project_version'),
                            semester_id=F('team__semester_id'))
    # A 720-hour offset is the largest permitted configuration.
    from .models import PitEventGradingConfig
    timed_events = PitEventGradingConfig.objects.filter(deliverables__requirement_timing='defense',
        deliverables__required=True).values('event_name')
    schedules = schedules.filter(materials_notice_key='', scheduled_date__lte=timezone.localdate() + timedelta(days=30)).filter(
        Q(scope='capstone', defense_stage__deliverables__requirement_timing='defense', defense_stage__deliverables__required=True) |
        Q(scope='pit', event_name__in=timed_events))
    from repository.deliverables.services import get_deliverable_definitions_for_team
    definitions = {}
    count = 0
    now = timezone.now()
    for schedule in schedules.select_related('team', 'defense_stage').distinct():
        key = (schedule.scope, schedule.semester_id if schedule.scope == 'pit' else None, schedule.stage_label)
        if key not in definitions:
            definitions[key] = [item for item in get_deliverable_definitions_for_team(schedule.team, schedule.stage_label)
                                if item.get('required') and due_before_defense(item)]
        # Future cutoffs need no per-team submission or recipient queries.
        if any(now >= deadline_for(item, schedule) for item in definitions[key]):
            count += notify_overdue(schedule.pk)
    return count
