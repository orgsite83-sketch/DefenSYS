"""Assign rubric templates to existing PIT events through the event policy."""
from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from rest_framework import serializers

from authentication_access_control.scopes import is_admin_user, is_pit_lead_only
from defense.scheduler.event_scope import pit_events_for_user, require_event_management
from defense.scheduler.models import PitEventGradingConfig
from defense.scheduler.pit_config import check_pit_event_locked, upsert_pit_event_config

from .models import Rubric


def managed_pit_events(user):
    if not user or not user.is_authenticated:
        return PitEventGradingConfig.objects.none()
    if not (is_admin_user(user) or is_pit_lead_only(user)):
        return PitEventGradingConfig.objects.none()
    return pit_events_for_user(user)


def pit_event_options(user):
    options = []
    for config in managed_pit_events(user).select_related('semester').order_by('event_name', 'pk'):
        locked, reason = check_pit_event_locked(config)
        options.append({
            'id': config.pk,
            'event_name': config.event_name,
            'semester_id': config.semester_id,
            'year_level': config.year_level,
            'panel_rubric_id': config.panel_rubric_id,
            'peer_rubric_id': config.peer_rubric_id,
            'is_locked': locked,
            'lock_reason': reason,
        })
    return options


@transaction.atomic
def sync_pit_event_assignment(rubric, event_id, *, request):
    """Keep one event per template; omission preserves legacy clients' links.

    Lock both ends before moving a template. The existing event writer enforces
    cohort ownership, semester, exclusivity and operational locks, and audits
    each change. Any failure rolls back the entire rubric save.
    """
    related = Q(panel_rubric=rubric) | Q(peer_rubric=rubric)
    rows = list(PitEventGradingConfig.objects.select_for_update(of=('self',)).filter(
        related | Q(pk=event_id if event_id is not serializers.empty else None)
    ).select_related('semester', 'panel_rubric', 'peer_rubric').order_by('pk'))
    current = [row for row in rows if rubric.pk in (row.panel_rubric_id, row.peer_rubric_id)]
    if event_id is serializers.empty:
        # Existing clients do not send an event ID. Never silently detach their
        # template or leave a changed semester/type in an incompatible slot.
        for config in current:
            require_event_management(request.user, config)
            field = 'peer_rubric_id' if rubric.evaluation_type == Rubric.EVAL_PEER else 'panel_rubric_id'
            if (rubric.scope != Rubric.SCOPE_PIT or config.semester_id != rubric.semester_id
                    or getattr(config, field) != rubric.pk):
                raise serializers.ValidationError({
                    'pit_event_id': 'Choose an event for the new semester and evaluation type, or remove the assignment first.',
                })
        return

    target = next((row for row in rows if row.pk == event_id), None)
    if event_id is not None:
        if rubric.scope != Rubric.SCOPE_PIT:
            raise serializers.ValidationError({'pit_event_id': 'Only PIT rubrics can be assigned to PIT events.'})
        if target is None or not managed_pit_events(request.user).filter(pk=event_id).exists():
            raise serializers.ValidationError({'pit_event_id': 'Choose an existing PIT event in your assigned year level.'})
        if target.semester_id != rubric.semester_id:
            raise serializers.ValidationError({'pit_event_id': 'The event must belong to the selected semester.'})

    # Clear the old slot first so the event writer can retain its exclusivity
    # rule. All rows are already locked and this transaction is atomic.
    ordered = [row for row in current if row != target]
    if target is not None:
        ordered.append(target)
    for config in ordered:
        require_event_management(request.user, config)
        panel = config.panel_rubric
        peer = config.peer_rubric
        if panel and panel.pk == rubric.pk:
            panel = None
        if peer and peer.pk == rubric.pk:
            peer = None
        if config == target:
            if rubric.evaluation_type == Rubric.EVAL_PEER:
                peer = rubric
            else:
                panel = rubric
        if ((panel.pk if panel else None) == config.panel_rubric_id
                and (peer.pk if peer else None) == config.peer_rubric_id):
            continue
        try:
            upsert_pit_event_config(
                semester=config.semester, event_name=config.event_name,
                year_level=config.year_level, panel_rubric=panel, peer_rubric=peer,
                panel_weight=config.panel_weight, peer_weight=config.peer_weight,
                peer_grading_enabled=config.peer_grading_enabled,
                user=request.user, request=request,
            )
        except ValidationError as exc:
            raise serializers.ValidationError({'pit_event_id': exc.messages}) from exc
