"""Shared approval policy for manual schedules, imports and nominations."""

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from authentication_access_control.scopes import is_admin_user
from .models import PanelistEligibilityRequest


def require_panelist_eligibility(panelists, actor):
    if is_admin_user(actor):
        return
    missing = [p.get_full_name() or p.username for p in panelists if not p.is_panelist]
    if missing:
        raise ValidationError({
            'panelist_ids': (
                f'Panelist approval is required for {", ".join(missing)}. '
                'Request admin approval before assigning them.'
            ),
        })


def request_payload(item):
    return {
        'id': item.pk,
        'faculty_id': item.faculty_id,
        'faculty_name': item.faculty.get_full_name() or item.faculty.username,
        'requested_by_id': item.requested_by_id,
        'requested_by_name': item.requested_by.get_full_name() or item.requested_by.username,
        'pit_year': item.pit_year,
        'reason': item.reason,
        'status': item.status,
        'review_note': item.review_note,
        'created_at': item.created_at.isoformat(),
        'reviewed_at': item.reviewed_at.isoformat() if item.reviewed_at else None,
        'reviewed_by_name': (item.reviewed_by.get_full_name() or item.reviewed_by.username) if item.reviewed_by else None,
    }


def visible_requests(actor, *, include_reviewed=False):
    items = PanelistEligibilityRequest.objects.select_related('faculty', 'requested_by', 'reviewed_by')
    if is_admin_user(actor):
        return items if include_reviewed else items.filter(status=PanelistEligibilityRequest.PENDING)
    return items.filter(requested_by=actor)


def _notify(recipient, actor, item, title, message):
    from notifications.models import Notification, NotificationCategory

    Notification.objects.create(
        recipient=recipient,
        sender=actor,
        title=title,
        message=message,
        category=NotificationCategory.DEFENSE,
        workspace='admin' if is_admin_user(recipient) else 'pit_lead',
        action_route=(
            f'/admin/users?tab=faculty&view=panelists&section=requests&request={item.pk}'
            if is_admin_user(recipient) else f'/faculty/defense-board?panelistRequest={item.pk}'
        ),
        action_payload={'panelist_eligibility': True, 'action_kind': 'panelist_request', 'request_id': item.pk},
    )


@transaction.atomic
def resolve_approved_requests(faculty, actor):
    """Role approval from any admin entry point also resolves outstanding requests."""
    if not faculty.is_panelist or not is_admin_user(actor):
        return
    pending = list(
        PanelistEligibilityRequest.objects.select_for_update(of=('self',))
        .filter(faculty=faculty, status=PanelistEligibilityRequest.PENDING)
        .select_related('requested_by')
    )
    if not pending:
        return
    PanelistEligibilityRequest.objects.filter(
        pk__in=[r.pk for r in pending], status=PanelistEligibilityRequest.PENDING,
    ).update(
        status=PanelistEligibilityRequest.APPROVED,
        reviewed_by=actor,
        reviewed_at=timezone.now(),
    )
    name = faculty.get_full_name() or faculty.username
    for item in pending:
        _notify(
            item.requested_by, actor, item, 'Panelist eligibility approved',
            f'{name} is now in the approved panelist pool. '
            'You can assign them to future defenses without requesting approval again.',
        )


@transaction.atomic
def ensure_panelist_eligibility(panelists, actor):
    # Lock in a stable order and recheck on commit, including a revocation after preview.
    locked = list(
        get_user_model().objects.select_for_update()
        .filter(pk__in=[p.pk for p in panelists]).order_by('pk')
    )
    if len(locked) != len(panelists) or any(
        not p.is_active or p.role not in ('faculty', 'admin') for p in locked
    ):
        raise ValidationError({'panelist_ids': 'All panelists must be active faculty members.'})
    require_panelist_eligibility(locked, actor)
    from .role_assignments import record_role_changes, snapshot_role_flags

    for faculty in locked:
        if not faculty.is_panelist:
            before = snapshot_role_flags(faculty)
            faculty.is_panelist = True
            faculty.save(update_fields=['is_panelist'])
            record_role_changes(faculty, before, changed_by=actor)
        else:
            resolve_approved_requests(faculty, actor)


@transaction.atomic
def nominate_panelist(actor, faculty_id, reason):
    if is_admin_user(actor) or not actor.is_pit_lead or not actor.pit_lead_year:
        raise PermissionDenied('Only PIT leads with an assigned year can nominate panelists.')
    faculty = (
        get_user_model().objects.select_for_update()
        .filter(pk=faculty_id, role__in=['faculty', 'admin'], is_active=True).first()
    )
    if faculty is None:
        raise ValidationError({'faculty_id': 'Choose an active faculty member.'})
    if faculty.is_panelist:
        return None, False
    item, created = PanelistEligibilityRequest.objects.get_or_create(
        faculty=faculty,
        requested_by=actor,
        status=PanelistEligibilityRequest.PENDING,
        defaults={'pit_year': actor.pit_lead_year, 'reason': reason},
    )
    if created:
        admins = get_user_model().objects.filter(is_active=True).filter(
            Q(role='admin') | Q(is_superuser=True)
        )
        for admin in admins:
            _notify(
                admin, actor, item, 'Panelist eligibility request',
                f'{actor.get_full_name() or actor.username} ({actor.pit_lead_year}) '
                f'nominated {faculty.get_full_name() or faculty.username}. '
                'Review the request in the panelist pool.',
            )
    return item, created


@transaction.atomic
def review_nomination(actor, item, decision, note):
    if not is_admin_user(actor):
        raise PermissionDenied('Only admins can review panelist eligibility.')
    faculty = get_user_model().objects.select_for_update().get(pk=item.faculty_id)
    item = PanelistEligibilityRequest.objects.select_for_update().get(pk=item.pk)
    if item.status != PanelistEligibilityRequest.PENDING:
        raise ValidationError({
            'detail': 'This request has already been reviewed. Refresh the panelist pool.',
        })
    if decision == PanelistEligibilityRequest.APPROVED:
        ensure_panelist_eligibility([faculty], actor)
        item.refresh_from_db()
        if note:
            item.review_note = note
            item.save(update_fields=['review_note'])
    else:
        item.status = PanelistEligibilityRequest.DECLINED
        item.reviewed_by = actor
        item.reviewed_at = timezone.now()
        item.review_note = note
        item.save(update_fields=['status', 'reviewed_by', 'reviewed_at', 'review_note'])
        _notify(
            item.requested_by, actor, item, 'Panelist eligibility request declined',
            f'{faculty.get_full_name() or faculty.username} was not approved. {note}'.strip(),
        )
    return item
