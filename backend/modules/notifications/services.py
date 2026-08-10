"""
Centralized Notification service helpers for DefenSYS.
Handles creation of in-app system notifications across modules.
"""

import logging

from .models import Notification, NotificationCategory, NotificationPriority

logger = logging.getLogger(__name__)


def create_notification(
    recipient,
    title: str,
    message: str,
    category: str = NotificationCategory.GENERAL,
    priority: str = NotificationPriority.NORMAL,
    sender=None,
    action_route: str = None,
    action_payload: dict = None,
) -> Notification:
    """
    Creates an in-system Notification for a recipient user.
    Returns the created Notification instance or None on failure.
    """
    if not recipient or not getattr(recipient, 'pk', None):
        logger.warning('create_notification: skipped — invalid recipient.')
        return None

    try:
        notification = Notification.objects.create(
            recipient=recipient,
            sender=sender,
            title=title,
            message=message,
            category=category,
            priority=priority,
            action_route=action_route,
            action_payload=action_payload or {},
        )
        logger.info(
            'create_notification: created notification id=%s for recipient_id=%s title="%s"',
            notification.pk,
            recipient.pk,
            title,
        )
        return notification
    except Exception as e:
        logger.exception(
            'create_notification: failed to create notification for recipient_id=%s: %s',
            recipient.pk,
            e,
        )
        return None
