"""Shared booking locks and per-appointment verification without grade writes."""
import hashlib
import json
import uuid
from datetime import datetime, timedelta

from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .models import ReDemoAppointment


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def outstanding(source):
    satisfied = {row['requirement_id'] for session in source.re_demos.all() if session.status == 'done'
                 for row in session.results if row['status'] == 'satisfied'}
    return [item for item in source.demo_requirements if item['id'] not in satisfied]


def team_progress(source):
    """Project a team's follow-up state without changing its academic verdict."""
    remaining = outstanding(source)
    active = next((row for row in source.re_demos.all() if row.status == 'scheduled'), None)
    current = True
    try:
        _current(source)
    except ValidationError:
        current = False
    return {
        'state': 'scheduled' if active else 'required' if remaining else 'verified',
        'source_schedule_id': source.schedule_id, 'source_outcome_id': source.pk,
        'source_revision': source.revision, 'outstanding_count': len(remaining),
        'requirement_count': len(source.demo_requirements),
        'can_schedule': bool(current and remaining and not active),
        'appointment_id': active.pk if active else None,
        'scheduled_date': active.scheduled_date.isoformat() if active else None,
        'start_time': active.start_time.isoformat() if active else None,
        'room': active.room if active else None,
        'operation_state': active.operation_state if active else None,
    }


def reservations(dates, *, exclude=None):
    rows = ReDemoAppointment.objects.filter(scheduled_date__in=dates, status__in=['scheduled', 'done']).select_related(
        'source__schedule__team').prefetch_related('panelists')
    if exclude is not None:
        rows = rows.exclude(pk=exclude)
    result = []
    for row in rows:
        start = datetime.combine(row.scheduled_date, row.start_time)
        result.append({'start': start, 'end': start + timedelta(minutes=row.slot_duration),
            'room': row.room.strip().casefold(), 'people': {person.pk for person in row.panelists.all()}
                | set(row.source.assessment_snapshot.get('student_ids', []))
                | ({row.source.schedule.team.adviser_id} if row.source.schedule.team.adviser_id else set()),
            'externals': set(row.external_ids)})
    return result


def token(appointment):
    return digest([appointment.pk, appointment.revision, appointment.source.revision,
        appointment.source_revision, appointment.requirements, appointment.status,
        appointment.operation_state, appointment.chair_id,
        sorted(person.pk for person in appointment.panelists.all())])


def visible(actor):
    from authentication_access_control.scopes import visible_schedules_for
    base = ReDemoAppointment.objects.select_related('source__schedule__team', 'source__schedule__defense_stage',
        'source__schedule__semester', 'source__grade__team', 'source__grade__semester',
        'source__confirmed_by', 'chair', 'verified_by').prefetch_related('panelists')
    if not actor or not actor.is_authenticated:
        return base.none()
    if getattr(actor, 'is_guest_panelist', False):
        from user_management.models import GuestPanelistCode
        invitation = GuestPanelistCode.objects.filter(pk=actor.guest_code_id, is_active=True).first()
        return base.filter(source__schedule_id__in=actor.schedule_ids,
            external_ids__contains=[invitation.evaluator_id]) if invitation and invitation.evaluator_id else base.none()
    if getattr(actor, 'role', None) == 'student':
        from grading.grades.dissemination_models import OutcomeRelease
        allowed = Q(pk__in=[])
        for release in OutcomeRelease.objects.filter(recipient_ids__contains=[actor.pk]).order_by('-pk'):
            decision = release.snapshot.get('panel_decision') or {}
            if decision.get('id') and decision.get('revision'):
                allowed |= Q(source_id=decision['id'], source_revision=decision['revision'])
        return base.filter(allowed)
    return base.filter(Q(source__schedule_id__in=visible_schedules_for(actor).values('pk')) |
                       Q(panelists=actor)).distinct()


def serialize(appointment, actor):
    source = appointment.source
    schedule = source.schedule
    student = getattr(actor, 'role', None) == 'student'
    from grading.grades.deliberation import version_payload
    current = True
    try:
        _current(source)
    except ValidationError:
        current = False
    result = {'id': appointment.pk, 'activity_id': f'redemo:{appointment.pk}', 'activity_type': 're_demo',
        'source_schedule_id': source.schedule_id, 'source_outcome_id': source.pk,
        'team_id': schedule.team_id, 'team_name': schedule.team.name,
        'stage_label': schedule.stage_label, 'semester_id': schedule.semester_id,
        'project_version': source.project_version, 'scheduled_date': appointment.scheduled_date.isoformat(),
        'start_time': appointment.start_time.isoformat(), 'slot_duration': appointment.slot_duration,
        'room': appointment.room, 'chair_id': appointment.chair_id,
        'chair_name': appointment.chair.get_full_name() or appointment.chair.username,
        'panelists': [{'id': person.pk, 'name': person.get_full_name() or person.username}
                      for person in appointment.panelists.all()],
        'status': appointment.status, 'operation_state': appointment.operation_state,
        'revision': appointment.revision, 'review_token': token(appointment) if not student else None,
        'requirements': appointment.requirements, 'results': appointment.results,
        'remarks': appointment.remarks, 'verified_at': appointment.verified_at,
        'verification_result': ('verified' if appointment.results and all(row['status'] == 'satisfied'
            for row in appointment.results) else 'needs_work') if appointment.status == 'done' else 'pending',
        'can_verify': bool(current and not student and actor.pk == appointment.chair_id and appointment.status == 'scheduled'
            and appointment.operation_state == 'normal' and appointment.scheduled_date <= timezone.localdate()
            and appointment.source_revision == source.revision),
        'outcome': version_payload(source, appointment.source_revision, public=student)}
    if student:
        from grading.grades.dissemination_models import OutcomeRelease
        release = OutcomeRelease.objects.filter(control__schedule_id=source.schedule_id,
            recipient_ids__contains=[actor.pk], snapshot__panel_decision__revision=appointment.source_revision).order_by('-pk').first()
        result['outcome'] = release.snapshot['panel_decision'] if release else None
    if not student and not getattr(actor, 'is_guest_panelist', False):
        from authentication_access_control.scopes import grade_records_for
        if grade_records_for(actor).filter(pk=source.grade_id).exists():
            result['original_assessment'] = source.assessment_snapshot
    return result


def _identity(value):
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError, AttributeError) as exc:
        raise ValidationError('Provide a valid request identity.') from exc


def _current(source):
    from grading.grades.defense_workflow import require_current
    require_current(source.grade)
    if (source.grade.closed_as_failed or source.grade.semester_id != source.schedule.team.semester_id
            or not source.schedule.semester.is_active or source.schedule.status in ('cancelled', 'archived')):
        raise ValidationError('This participation or hearing is historical, closed, or cancelled.')
    from defense.stages.models import StageGradingConfig
    if StageGradingConfig.objects.filter(semester_id=source.schedule.semester_id,
            defense_stage_id=source.schedule.defense_stage_id, is_officially_complete=True).exists():
        raise ValidationError('The source stage is officially complete.')
    if source.grade.schedule_id != source.schedule_id or source.grade.verdict != source.verdict:
        raise ValidationError('The source outcome changed. Review the current defense record.')
    if source.verdict != 'approved_with_revisions' or not source.demo_requirements:
        raise ValidationError('This outcome does not require an unscored re-demo.')


def _booking(attrs, *, exclude=None):
    from rest_framework import serializers
    from django.contrib.auth import get_user_model
    User = get_user_model()
    from defense.scheduler.services import adviser_panel_conflict
    source = attrs['source']
    date = serializers.DateField().run_validation(attrs.get('scheduled_date'))
    from academic_period_management.calendar import validate_defense_date
    validate_defense_date(source.schedule.semester, date, lock=True)
    time = serializers.TimeField().run_validation(attrs.get('start_time'))
    duration = serializers.IntegerField(min_value=10, max_value=240).run_validation(attrs.get('slot_duration', 30))
    room = serializers.CharField(max_length=120, allow_blank=False).run_validation(attrs.get('room'))
    raw = attrs.get('panelist_ids', list(source.schedule.panel_assignments.values_list('panelist_id', flat=True)))
    if not isinstance(raw, list) or not raw:
        raise ValidationError('Assign a re-demo panel.')
    ids = [serializers.IntegerField(min_value=1).run_validation(value) for value in raw]
    if len(ids) != len(set(ids)):
        raise ValidationError('Assign each panel member once.')
    people = list(User.objects.filter(pk__in=ids, is_active=True, is_panelist=True, role__in=['faculty', 'admin']))
    if len(people) != len(ids):
        raise ValidationError('Choose active, eligible panelists.')
    chair_id = serializers.IntegerField(min_value=1).run_validation(attrs.get('chair_id', source.confirmed_by_id))
    if chair_id not in ids:
        raise ValidationError('The assigned re-demo chair must belong to its panel.')
    reason = adviser_panel_conflict(source.schedule.team, ids)
    if reason:
        raise ValidationError(reason)
    from user_management.models import ExternalEvaluator
    entry = {'scheduled_date': date, 'start_time': time, 'slot_duration': duration, 'room': room,
             'panelists': people, 'external_evaluators': list(ExternalEvaluator.objects.filter(
                 pk__in=attrs.get('external_ids', []))), 'team': source.schedule.team}
    # Both services hold the same period locks before checking reservations.
    from defense.scheduler.sessions import validate_plan_conflicts
    validate_plan_conflicts([entry], exclude_redemo_id=exclude)
    return entry, chair_id


def _audit(appointment, actor, action, **values):
    from authentication_access_control.audit import log_high_impact_action
    from authentication_access_control.models import SystemAuditLog
    log_high_impact_action(category=SystemAuditLog.CATEGORY_SCHEDULING, action=action,
        target=appointment, actor=actor, new_values={'activity_type': 're_demo',
        'source_schedule_id': appointment.source.schedule_id, 'source_outcome_id': appointment.source_id,
        'revision': appointment.revision, **values}, strict=True)
    from .notifications import changed
    transaction.on_commit(lambda: changed(appointment.pk, actor.pk, action.split('.')[-1]), robust=True)


@transaction.atomic
def book(source, *, actor, data):
    from academic_period_management.models import Semester
    from student_teams.models import StudentTeam
    from grading.grades.outcome_models import DefenseOutcome
    list(Semester.objects.select_for_update().order_by('pk'))
    StudentTeam.objects.select_for_update().get(pk=source.schedule.team_id)
    source = DefenseOutcome.objects.select_for_update(of=('self',)).select_related('schedule__team', 'grade').get(pk=source.pk)
    if set(data) - {'request_id', 'outcome_id', 'source_revision', 'scheduled_date', 'start_time', 'slot_duration',
                    'room', 'chair_id', 'panelist_ids'}:
        raise ValidationError('Unsupported re-demo booking fields.')
    request_id = _identity(data.get('request_id'))
    fingerprint = digest([source.pk, actor.pk, data])
    previous = ReDemoAppointment.objects.filter(request_id=request_id).first()
    if previous:
        if previous.request_digest != fingerprint:
            raise ValidationError('This request identity belongs to another booking.')
        return previous
    _current(source)
    if data.get('source_revision') != source.revision:
        raise ValidationError('The source outcome changed. Refresh before scheduling.')
    required = outstanding(source)
    if not required:
        raise ValidationError('All required demonstrations have already been verified.')
    if source.re_demos.filter(status='scheduled').exists():
        raise ValidationError('This outcome already has an active re-demo appointment.')
    entry, chair_id = _booking({**data, 'source': source})
    from user_management.models import GuestPanelistCode
    invitation_ids = list(GuestPanelistCode.objects.filter(Q(schedules=source.schedule) | Q(defense_schedule=source.schedule),
        is_active=True).exclude(evaluator_id=None).values_list('evaluator_id', flat=True).distinct())
    # Include the source's active external roster in resource conflicts.
    from user_management.models import ExternalEvaluator
    from defense.scheduler.sessions import validate_plan_conflicts
    entry['external_evaluators'] = list(ExternalEvaluator.objects.filter(pk__in=invitation_ids))
    validate_plan_conflicts([entry])
    appointment = ReDemoAppointment.objects.create(source=source, source_revision=source.revision,
        requirements=required, scheduled_date=entry['scheduled_date'], start_time=entry['start_time'],
        slot_duration=entry['slot_duration'], room=entry['room'], chair_id=chair_id,
        external_ids=invitation_ids, created_by=actor, request_id=request_id, request_digest=fingerprint)
    appointment.panelists.set(entry['panelists'])
    _audit(appointment, actor, 'redemo.scheduled', date=str(appointment.scheduled_date), room=appointment.room,
           chair_id=chair_id, panelist_ids=[person.pk for person in entry['panelists']], external_ids=invitation_ids,
           source_revision=source.revision, requirement_ids=[row['id'] for row in required])
    return appointment


@transaction.atomic
def operate(appointment, *, actor, data):
    from academic_period_management.models import Semester
    from student_teams.models import StudentTeam
    list(Semester.objects.select_for_update().order_by('pk'))
    StudentTeam.objects.select_for_update().get(pk=appointment.source.schedule.team_id)
    appointment = ReDemoAppointment.objects.select_for_update(of=('self',)).select_related(
        'source__schedule__team', 'source__grade').prefetch_related('panelists').get(pk=appointment.pk)
    if set(data) - {'revision', 'action', 'reason', 'scheduled_date', 'start_time', 'slot_duration',
                    'room', 'chair_id', 'panelist_ids'}:
        raise ValidationError('Unsupported re-demo operation fields.')
    if data.get('revision') != appointment.revision:
        raise ValidationError('This appointment changed. Refresh before applying the operation.')
    if appointment.status != 'scheduled':
        raise ValidationError('Completed and cancelled appointments retain their recorded history.')
    before = {name: str(getattr(appointment, name)) for name in
              ('scheduled_date', 'start_time', 'slot_duration', 'room', 'chair_id', 'operation_state', 'status')}
    before['panelist_ids'] = [person.pk for person in appointment.panelists.all()]
    reason = data.get('reason')
    if not isinstance(reason, str) or not 1 <= len(reason.strip()) <= 2000:
        raise ValidationError('Record a reason of up to 2000 characters.')
    action = data.get('action')
    if action == 'cancel':
        appointment.status = 'cancelled'
    elif action in ('pause', 'postpone', 'no_show', 'resume'):
        if action == 'resume':
            _current(appointment.source)
            if appointment.source_revision != appointment.source.revision:
                raise ValidationError('The source requirements changed. Cancel and rebook this appointment.')
        appointment.operation_state = {'pause': 'paused', 'postpone': 'postponed',
            'no_show': 'no_show', 'resume': 'normal'}[action]
    elif action == 'reschedule':
        _current(appointment.source)
        if appointment.source_revision != appointment.source.revision:
            raise ValidationError('The source requirements changed. Review and rebook this appointment.')
        entry, chair_id = _booking({**data, 'source': appointment.source,
            'external_ids': appointment.external_ids,
            'panelist_ids': data.get('panelist_ids', [person.pk for person in appointment.panelists.all()]),
            'chair_id': data.get('chair_id', appointment.chair_id)}, exclude=appointment.pk)
        for name in ('scheduled_date', 'start_time', 'slot_duration', 'room'):
            setattr(appointment, name, entry[name])
        appointment.chair_id = chair_id
        appointment.panelists.set(entry['panelists'])
        appointment.operation_state = 'normal'
    else:
        raise ValidationError('Choose cancel, pause, postpone, no-show, resume, or reschedule.')
    appointment.operation_reason = reason.strip()
    appointment.revision += 1
    appointment.save()
    _audit(appointment, actor, f'redemo.{action}', reason=reason.strip(), before=before,
        after={**{name: str(getattr(appointment, name)) for name in
            ('scheduled_date', 'start_time', 'slot_duration', 'room', 'chair_id', 'operation_state', 'status')},
            'panelist_ids': [person.pk for person in appointment.panelists.all()]})
    return appointment


@transaction.atomic
def verify(appointment, *, actor, data):
    from student_teams.models import StudentTeam
    from grading.grades.outcome_models import DefenseOutcome
    StudentTeam.objects.select_for_update().get(pk=appointment.source.schedule.team_id)
    DefenseOutcome.objects.select_for_update().get(pk=appointment.source_id)
    appointment = ReDemoAppointment.objects.select_for_update(of=('self',)).select_related('source__grade',
        'source__schedule__team', 'chair').prefetch_related('panelists').get(pk=appointment.pk)
    if (actor.pk != appointment.chair_id or getattr(actor, 'is_guest_panelist', False)
            or not actor.is_active or not getattr(actor, 'is_panelist', False)):
        raise PermissionError('Only the assigned re-demo chair can confirm verification.')
    if set(data) - {'request_id', 'review_token', 'results', 'remarks'}:
        raise ValidationError('Re-demo verification accepts requirement results and remarks, not scores or verdicts.')
    request_id = _identity(data.get('request_id'))
    fingerprint = digest(data)
    if appointment.verification_request_id == request_id and appointment.verification_digest == fingerprint:
        return appointment
    if ReDemoAppointment.objects.filter(verification_request_id=request_id).exclude(pk=appointment.pk).exists():
        raise ValidationError('This verification request identity belongs to another appointment.')
    _current(appointment.source)
    if (appointment.status != 'scheduled' or appointment.operation_state != 'normal'
            or appointment.scheduled_date > timezone.localdate()):
        raise ValidationError('Verification is unavailable for this appointment in its current state.')
    if appointment.source_revision != appointment.source.revision or data.get('review_token') != token(appointment):
        raise ValidationError('The appointment or source requirements changed. Refresh before verifying.')
    results = data.get('results')
    keys = {item['id'] for item in appointment.requirements}
    if not isinstance(results, list) or len(results) != len(keys):
        raise ValidationError('Record one verification result for every requested demonstration.')
    seen, normalized = set(), []
    for row in results:
        if not isinstance(row, dict) or set(row) != {'requirement_id', 'status'}:
            raise ValidationError('Use a requirement identity and Satisfied or Needs work.')
        key = row['requirement_id']
        if not isinstance(key, str) or key not in keys or key in seen or row['status'] not in ('satisfied', 'needs_work'):
            raise ValidationError('Every requested demonstration needs one valid result.')
        seen.add(key)
        normalized.append({'requirement_id': key, 'status': row['status']})
    remarks = data.get('remarks', '')
    if not isinstance(remarks, str) or len(remarks) > 5000:
        raise ValidationError('Verification remarks must be text of up to 5000 characters.')
    if any(row['status'] == 'needs_work' for row in normalized) and not remarks.strip():
        raise ValidationError('Describe the remaining corrections before confirming.')
    appointment.results, appointment.remarks = normalized, remarks.strip()
    appointment.status, appointment.verified_by = 'done', actor
    appointment.verified_at = timezone.now()
    appointment.verification_request_id, appointment.verification_digest = request_id, fingerprint
    appointment.revision += 1
    appointment.save()
    _audit(appointment, actor, 'redemo.verified', results=normalized, remarks=appointment.remarks)
    return appointment
