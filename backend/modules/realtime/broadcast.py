"""Push grading-flag changes to WebSocket channel groups."""

from __future__ import annotations

import logging
from typing import Any

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .groups import broadcast_groups_for_capstone_semester, broadcast_groups_for_pit_event

logger = logging.getLogger(__name__)


def _base_payload(
    *,
    scope: str,
    semester_id: int,
    peer_eval_enabled: bool | None = None,
    adviser_grading_enabled: bool | None = None,
    stage_label: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        'event': 'grading.flags_changed',
        'version': 1,
        'scope': scope,
        'semester_id': semester_id,
    }
    if peer_eval_enabled is not None:
        payload['peer_eval_enabled'] = peer_eval_enabled
    if adviser_grading_enabled is not None:
        payload['adviser_grading_enabled'] = adviser_grading_enabled
    if stage_label:
        payload['stage_label'] = stage_label
    return payload


def _send_to_groups(groups: list[str], payload: dict[str, Any]) -> None:
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    message = {
        'type': 'grading.flags_changed',
        'payload': payload,
    }
    for group in groups:
        try:
            async_to_sync(channel_layer.group_send)(group, message)
        except Exception as e:
            logger.warning(
                f"Failed to broadcast real-time sync notification to group {group}: {e}",
                exc_info=True,
            )


def notify_capstone_evaluation_flags(
    semester,
    *,
    peer_eval_enabled: bool | None = None,
    adviser_grading_enabled: bool | None = None,
) -> None:
    payload = _base_payload(
        scope='capstone',
        semester_id=semester.id,
        peer_eval_enabled=peer_eval_enabled,
        adviser_grading_enabled=adviser_grading_enabled,
    )
    _send_to_groups(broadcast_groups_for_capstone_semester(semester.id), payload)


def notify_pit_peer_grading(
    semester,
    event_label: str,
    *,
    peer_eval_enabled: bool,
) -> None:
    payload = _base_payload(
        scope='pit',
        semester_id=semester.id,
        stage_label=event_label,
        peer_eval_enabled=peer_eval_enabled,
    )
    _send_to_groups(
        broadcast_groups_for_pit_event(semester.id, event_label),
        payload,
    )
