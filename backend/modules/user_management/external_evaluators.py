"""Reusable evaluator approvals and defense-scoped, expiring invitations."""
from datetime import datetime, time, timedelta
from django.contrib.auth import get_user_model
from django.db import transaction, IntegrityError
from django.db.models import Q, F
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from authentication_access_control.scopes import is_admin_user, visible_schedules_for
from defense.scheduler.models import DefenseSchedule
from .models import ExternalEvaluator, GuestPanelistCode


def evaluator_payload(item):
    return {
        'id': item.pk, 'name': item.name, 'email': item.email,
        'institution': item.institution, 'status': item.status,
        'is_active': item.is_active, 'pit_year': item.pit_year,
        'requested_by_name': (item.created_by.get_full_name() or item.created_by.username) if item.created_by else '',
        'review_note': item.review_note,
    }


def visible_evaluators(actor):
    items = ExternalEvaluator.objects.select_related('created_by')
    return items if is_admin_user(actor) else items.filter(Q(status=ExternalEvaluator.APPROVED, is_active=True) | Q(created_by=actor))


def invitation_schedule_ids(invitation):
    ids = list(invitation.schedules.values_list('pk', flat=True))
    return ids or ([invitation.defense_schedule_id] if invitation.defense_schedule_id else [])


def invitation_schedules(invitation):
    schedules = list(invitation.schedules.all())
    return schedules or ([invitation.defense_schedule] if invitation.defense_schedule_id else [])


def primary_guest_schedule(invitation):
    return invitation.defense_schedule if invitation.defense_schedule_id else invitation.schedules.select_related('team', 'defense_stage').order_by('scheduled_date', 'start_time', 'pk').first()


def invitation_is_available(invitation):
    return bool(invitation.is_active and invitation_schedule_ids(invitation) and (not invitation.expires_at or invitation.expires_at > timezone.now())
                and (not invitation.evaluator_id or (invitation.evaluator.is_active and invitation.evaluator.status == ExternalEvaluator.APPROVED)))


def visible_invitations(actor):
    items = GuestPanelistCode.objects.select_related('evaluator', 'created_by', 'defense_schedule__team').prefetch_related('schedules__team', 'schedules__defense_stage')
    if is_admin_user(actor):
        return items
    allowed = set(visible_schedules_for(actor).values_list('pk', flat=True))
    return [item for item in items if (ids := set(invitation_schedule_ids(item))) and ids.issubset(allowed)]


def invitation_payload(item):
    from grading.grades.models import PanelistGradeSubmission
    schedules = invitation_schedules(item)
    ids = [s.pk for s in schedules]
    submitted = set(PanelistGradeSubmission.objects.filter(guest_code_id=str(item.pk), schedule_id__in=ids).values_list('schedule_id', flat=True))
    status = 'Active' if invitation_is_available(item) else 'Expired' if item.is_active and item.expires_at and item.expires_at <= timezone.now() else 'Revoked'
    return {
        'id': item.pk, 'code': item.code, 'evaluator_id': item.evaluator_id,
        'guest_name': item.guest_name, 'email': item.email, 'status': status,
        'is_active': item.is_active, 'expires_at': item.expires_at.isoformat() if item.expires_at else None,
        'last_access_at': item.last_access_at.isoformat() if item.last_access_at else None,
        'used_at': item.used_at.isoformat() if item.used_at else None,
        'created_at': item.created_at.isoformat(), 'submitted_count': len(submitted),
        'schedule_ids': ids, 'schedules': [{
            'id': s.pk, 'team_name': s.team.name, 'scope': s.scope,
            'stage_label': s.stage_label, 'date': s.scheduled_date.isoformat(),
            'room': s.room, 'submitted': s.pk in submitted,
        } for s in schedules],
    }


def management_payload(actor):
    from academic_period_management.services import active_semester
    active = active_semester()
    return {
        'evaluators': [evaluator_payload(e) for e in visible_evaluators(actor)],
        'invitations': [invitation_payload(i) for i in visible_invitations(actor)],
        'schedules': [{
            'id': s.pk, 'team_name': s.team.name, 'scope': s.scope,
            'stage_label': s.stage_label, 'date': s.scheduled_date.isoformat(), 'room': s.room,
            'year_level': s.team.year_level, 'semester_id': s.semester_id, 'display_semester': s.semester.display_name,
            'defense_stage_id': s.defense_stage_id, 'event_name': s.event_name,
            'start_time': s.start_time.isoformat(), 'slot_duration': s.slot_duration,
        } for s in visible_schedules_for(actor).filter(status=DefenseSchedule.STATUS_SCHEDULED)],
        'can_approve': is_admin_user(actor),
        'active_semester_id': active.pk if active else None,
    }


def _notify(recipient, actor, evaluator, title):
    from notifications.models import Notification, NotificationCategory
    Notification.objects.create(recipient=recipient, sender=actor, title=title,
        message=f'{evaluator.name}: review external evaluator access in Defense Operations.',
        category=NotificationCategory.DEFENSE,
        action_route='/admin/defense-board' if is_admin_user(recipient) else '/faculty/defense_board')


@transaction.atomic
def register_evaluator(actor, data):
    email = data.get('email', '').strip().lower()
    if email and get_user_model().objects.filter(email__iexact=email).exists():
        raise ValidationError({'email': 'This email belongs to an institutional account. Use the faculty panelist pool.'})
    existing = ExternalEvaluator.objects.filter(email__iexact=email).first() if email else ExternalEvaluator.objects.filter(name__iexact=data['name'], institution__iexact=data.get('institution', ''), email='').first()
    if existing:
        if not existing.is_active:
            raise ValidationError({'name': 'This evaluator is inactive. Ask an admin to reactivate their directory record.'})
        if is_admin_user(actor) and existing.status != ExternalEvaluator.APPROVED:
            raise ValidationError({'name': 'This evaluator already exists. Review their approval in the directory.'})
        if not is_admin_user(actor) and existing.status != ExternalEvaluator.APPROVED and existing.created_by_id != actor.pk:
            raise ValidationError({'name': 'This evaluator already has a pending admin review.'})
        return existing, False
    approved = is_admin_user(actor)
    try:
        with transaction.atomic():
            item = ExternalEvaluator.objects.create(name=data['name'].strip(), email=email,
                institution=data.get('institution', '').strip(), created_by=actor,
                pit_year=getattr(actor, 'pit_lead_year', '') or '',
                status=ExternalEvaluator.APPROVED if approved else ExternalEvaluator.PENDING,
                reviewed_by=actor if approved else None, reviewed_at=timezone.now() if approved else None)
    except IntegrityError:
        raise ValidationError({'email': 'This evaluator was just registered. Refresh the directory before adding them again.'})
    if not approved:
        for admin in get_user_model().objects.filter(is_active=True).filter(Q(role='admin') | Q(is_superuser=True)):
            _notify(admin, actor, item, 'External evaluator approval requested')
    return item, True


@transaction.atomic
def update_evaluator(actor, item, data):
    if not is_admin_user(actor):
        raise PermissionDenied('Only admins can approve or update external evaluators.')
    item = ExternalEvaluator.objects.select_for_update().get(pk=item.pk)
    before = item.status
    if 'email' in data:
        data['email'] = data['email'].strip().lower()
        if data['email'] and (get_user_model().objects.filter(email__iexact=data['email']).exists() or ExternalEvaluator.objects.filter(email__iexact=data['email']).exclude(pk=item.pk).exists()):
            raise ValidationError({'email': 'This email is already registered. Use a different external evaluator email.'})
    for field in ('name', 'email', 'institution', 'status', 'is_active', 'review_note'):
        if field in data:
            setattr(item, field, data[field])
    if item.status != before:
        item.reviewed_by = actor
        item.reviewed_at = timezone.now()
    item.save()
    if not item.is_active or item.status != ExternalEvaluator.APPROVED:
        item.invitations.filter(is_active=True).update(is_active=False, access_version=F('access_version') + 1)
    if item.status != before and item.created_by and not is_admin_user(item.created_by):
        _notify(item.created_by, actor, item, f'External evaluator {item.status}')
    return item


def resolve_evaluators(ids, actor):
    unique = list(dict.fromkeys(ids))
    items = list(ExternalEvaluator.objects.filter(pk__in=unique, is_active=True, status=ExternalEvaluator.APPROVED))
    if len(items) != len(unique):
        raise ValidationError({'external_evaluator_ids': 'Select approved, active external evaluators.'})
    return items


def _validate_lead_term(actor, schedules):
    if is_admin_user(actor):
        return
    from academic_period_management.services import active_semester
    from student_teams.term_scope import PIT_MODE_AUDIT, pit_lead_operating_mode
    active = active_semester()
    if active is None or any(s.semester_id != active.pk for s in schedules) or pit_lead_operating_mode(actor, active=active) == PIT_MODE_AUDIT:
        raise PermissionDenied('PIT invitations can only be created or renewed for your active term.')


def _validate_expiry(expires_at, schedules):
    if not schedules:
        raise ValidationError({'schedule_ids': 'This invitation no longer has assigned defenses. Create an invitation for a confirmed defense.'})
    if expires_at <= timezone.now():
        raise ValidationError({'expires_at': 'Choose an access expiry in the future.'})
    end = max(timezone.make_aware(datetime.combine(s.scheduled_date, s.start_time)) + timedelta(minutes=s.slot_duration) for s in schedules)
    if expires_at < end:
        raise ValidationError({'expires_at': 'Access must remain available until the last assigned defense ends.'})


@transaction.atomic
def create_invitations(evaluators, schedules, actor, expires_at=None):
    """Assign a selection atomically, preserving a guest identity per session."""
    if not evaluators:
        return []
    schedules = list({s.pk: s for s in schedules}.values())
    ids = {s.pk for s in schedules}
    if not ids or not ids.issubset(set(visible_schedules_for(actor).values_list('pk', flat=True))):
        raise PermissionDenied('Invitations must be limited to defenses you manage.')
    if any(s.status != DefenseSchedule.STATUS_SCHEDULED for s in schedules):
        raise ValidationError({'schedule_ids': 'Select confirmed, scheduled defenses.'})
    _validate_lead_term(actor, schedules)

    ordered = sorted(schedules, key=lambda s: (s.scheduled_date, s.start_time, s.pk))
    for previous, current in zip(ordered, ordered[1:]):
        end = datetime.combine(previous.scheduled_date, previous.start_time) + timedelta(minutes=previous.slot_duration)
        if datetime.combine(current.scheduled_date, current.start_time) < end:
            raise ValidationError({'schedule_ids': 'Selected defenses overlap. Choose non-overlapping times for each evaluator.'})

    groups = {}
    for schedule in ordered:
        session = schedule.defense_stage_id if schedule.scope == 'capstone' else schedule.event_name
        key = (schedule.semester_id, schedule.scope, schedule.team.year_level, session)
        groups.setdefault(key, []).append(schedule)
    invitations = []
    for group in groups.values():
        invitations.extend(_create_session_invitations(evaluators, group, actor, expires_at))
    return invitations


def _create_session_invitations(evaluators, schedules, actor, expires_at=None):
    if not evaluators:
        return []
    ids = {s.pk for s in schedules}
    if not ids or not ids.issubset(set(visible_schedules_for(actor).values_list('pk', flat=True))):
        raise PermissionDenied('Invitations must be limited to defenses you manage.')
    if any(s.status != DefenseSchedule.STATUS_SCHEDULED for s in schedules):
        raise ValidationError({'schedule_ids': 'Select confirmed, scheduled defenses.'})
    _validate_lead_term(actor, schedules)
    if expires_at is None:
        last_end = max(datetime.combine(s.scheduled_date, s.start_time) + timedelta(minutes=s.slot_duration) for s in schedules)
        end_of_day = timezone.make_aware(datetime.combine(last_end.date(), time(23, 59, 59)))
        expires_at = max(end_of_day, timezone.now() + timedelta(hours=8))
    _validate_expiry(expires_at, schedules)
    locked = list(ExternalEvaluator.objects.select_for_update().filter(pk__in=[e.pk for e in evaluators]).order_by('pk'))
    if len(locked) != len(evaluators) or any(not e.is_active or e.status != ExternalEvaluator.APPROVED for e in locked):
        raise ValidationError({'external_evaluator_ids': 'An evaluator is no longer approved. Refresh the evaluator pool.'})
    invitations = []
    for evaluator in locked:
        overlaps = list(GuestPanelistCode.objects.filter(evaluator=evaluator, schedules__pk__in=ids).distinct())
        if overlaps:
            if len(overlaps) == 1 and set(invitation_schedule_ids(overlaps[0])) == ids:
                invitations.append(overlaps[0])
                continue
            raise ValidationError({'schedule_ids': f'{evaluator.name} already has an invitation for one of these defenses. Manage that invitation instead.'})
        reserved = DefenseSchedule.objects.filter(guest_invitations__evaluator=evaluator,
            guest_invitations__is_active=True, status=DefenseSchedule.STATUS_SCHEDULED).exclude(pk__in=ids).distinct()
        for schedule in schedules:
            start = schedule.start_time.hour * 60 + schedule.start_time.minute
            end = start + schedule.slot_duration
            for other in reserved.filter(scheduled_date=schedule.scheduled_date):
                other_start = other.start_time.hour * 60 + other.start_time.minute
                if start < other_start + other.slot_duration and other_start < end:
                    raise ValidationError({'external_evaluator_ids': f'{evaluator.name} already has a defense during that time.'})
        item = GuestPanelistCode.objects.create(evaluator=evaluator, guest_name=evaluator.name,
            email=evaluator.email, defense_schedule=schedules[0], created_by=actor, expires_at=expires_at)
        item.schedules.set(schedules)
        from authentication_access_control.audit import log_high_impact_action
        from authentication_access_control.models import SystemAuditLog
        log_high_impact_action(category=SystemAuditLog.CATEGORY_GUEST_ACCESS, action='external_invitation.create',
            target=item, actor=actor, reason='Assigned approved external evaluator to confirmed defenses',
            new_values={'evaluator_id': evaluator.pk, 'schedule_ids': sorted(ids), 'scope': schedules[0].scope,
                'year_level': schedules[0].team.year_level, 'semester_id': schedules[0].semester_id,
                'stage_label': schedules[0].stage_label})
        invitations.append(item)
    return invitations


@transaction.atomic
def update_invitation(actor, item, data):
    item = GuestPanelistCode.objects.select_for_update().get(pk=item.pk)
    ids = set(invitation_schedule_ids(item))
    if not is_admin_user(actor) and (not ids or not ids.issubset(set(visible_schedules_for(actor).values_list('pk', flat=True)))):
        raise PermissionDenied('You cannot manage this invitation.')
    if data.get('is_active') is True:
        expiry = data.get('expires_at')
        if expiry is None or expiry <= timezone.now():
            raise ValidationError({'expires_at': 'Renewal requires a future access expiry.'})
        if item.evaluator_id and (not item.evaluator.is_active or item.evaluator.status != ExternalEvaluator.APPROVED):
            raise ValidationError({'detail': 'Approve the evaluator before renewing access.'})
        schedules = invitation_schedules(item)
        _validate_lead_term(actor, schedules)
        _validate_expiry(expiry, schedules)
        item.code = GuestPanelistCode.generate_unique_code()
        item.expires_at = expiry
        item.is_active = True
    elif data.get('is_active') is False:
        item.is_active = False
    else:
        raise ValidationError({'is_active': 'Choose revoke or renew access.'})
    item.access_version += 1
    item.save()
    return item
