"""
Centralized Notification service helpers for DefenSYS.
Handles creation of in-app system notifications across modules.
"""

import logging
from urllib.parse import urlencode

from .models import Notification, NotificationCategory, NotificationPriority

logger = logging.getLogger(__name__)


def notify_team_students(team, *, title, message, category=NotificationCategory.GENERAL,
                         sender=None, stage_label=None, deliverables=False,
                         action_payload=None, event_key=None, priority=NotificationPriority.NORMAL):
    """Persist student alerts with the domain write so failures roll back together.

    The caller owns the transaction/team lock. Stable event keys prevent panel
    resubmissions and scheduling retries from creating duplicate unread alerts.
    """
    from django.contrib.auth import get_user_model

    student_ids = set(team.memberships.values_list('student_id', flat=True))
    if team.leader_id:
        student_ids.add(team.leader_id)
    query = {'stage': stage_label} if stage_label else {}
    if deliverables:
        query['subtab'] = 'deliverables'
    route = '/student' + ('?' + urlencode(query) if query else '')
    payload = {'team_id': team.pk, **(action_payload or {})}
    if event_key:
        payload['notification_event'] = event_key
    for student in get_user_model().objects.filter(pk__in=student_ids, role='student', is_active=True):
        if event_key and Notification.objects.filter(
            recipient=student, workspace='student',
            action_payload__notification_event=event_key,
        ).exists():
            continue
        Notification.objects.create(
            recipient=student, sender=sender, workspace='student', title=title,
            message=message, category=category, priority=priority,
            action_route=route, action_payload=payload,
        )


def notify_student_defense_schedule(schedule):
    notify_team_students(
        schedule.team, title='Defense scheduled', category=NotificationCategory.DEFENSE,
        message=(f'{schedule.team.name}: {schedule.stage_label} is scheduled for '
                 f'{schedule.scheduled_date:%B %d, %Y} at {schedule.start_time:%I:%M %p} '
                 f'in {schedule.room}.'),
        sender=schedule.created_by, stage_label=schedule.stage_label,
        action_payload={'schedule_id': schedule.pk}, event_key=f'defense.scheduled:{schedule.pk}',
    )


def notify_student_peer_open(grade):
    notify_team_students(
        grade.team, title='Peer evaluation is open', category=NotificationCategory.PEER_EVAL,
        message=f'Peer evaluation for {grade.team.name} ({grade.stage_label}) is now available.',
        stage_label=grade.stage_label, action_payload={'schedule_id': grade.schedule_id},
        event_key=f'peer.open:{grade.pk}:{grade.schedule_id}',
    )


def notify_student_deliverable_review(submission, *, reviewer, status, feedback):
    notify_team_students(
        submission.team,
        title='Deliverable accepted' if status == 'accepted' else 'Deliverable needs revision',
        message=(f'{submission.label or submission.deliverable_id} ({submission.stage_label}) '
                 f'was {status}.' + (f'\n{feedback.strip()}' if feedback.strip() else '')),
        sender=reviewer, stage_label=submission.stage_label, deliverables=True,
        action_payload={'stage_label': submission.stage_label, 'action_kind': 'deliverables',
                        'deliverable_id': submission.deliverable_id, 'deliverable_task': 'requirement_upload'},
        priority=NotificationPriority.HIGH if status == 'rejected' else NotificationPriority.NORMAL,
    )


def create_notification(
    recipient,
    title: str,
    message: str,
    category: str = NotificationCategory.GENERAL,
    priority: str = NotificationPriority.NORMAL,
    sender=None,
    action_route: str = None,
    action_payload: dict = None,
    workspace: str = None,
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
            workspace=workspace or '',
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
