from datetime import timedelta
from django.db import migrations


def backfill_action_targets(apps, schema_editor):
    """Attach legacy alerts only when their author, text and event time agree.

    Ambiguous matches keep their old link, rather than opening another request.
    Workflow decisions and read state are never modified by this migration.
    """
    Notification = apps.get_model('notifications', 'Notification')
    Request = apps.get_model('user_management', 'PanelistEligibilityRequest')
    Evaluator = apps.get_model('user_management', 'ExternalEvaluator')
    alias = schema_editor.connection.alias
    items = Notification.objects.using(alias).filter(category='DEFENSE')
    for notification in items.iterator(chunk_size=500):
        payload = notification.action_payload or {}
        if payload.get('action_kind'):
            continue
        title = notification.title.lower()
        start = notification.created_at - timedelta(minutes=2)
        end = notification.created_at + timedelta(seconds=1)
        matched = []
        if 'panelist eligibility' in title:
            is_request = title == 'panelist eligibility request'
            candidates = Request.objects.using(alias).select_related('faculty').filter(**(
                {'requested_by_id': notification.sender_id, 'created_at__range': (start, end)} if is_request else
                {'requested_by_id': notification.recipient_id, 'reviewed_by_id': notification.sender_id,
                 'reviewed_at__range': (start, end)}))
            for item in candidates:
                name = f'{item.faculty.first_name} {item.faculty.last_name}'.strip() or item.faculty.username
                text = f'nominated {name}. ' if is_request else f'{name} is now' if 'approved' in title else f'{name} was not approved.'
                if text in notification.message:
                    matched.append(item)
            kind, key, route_kind = 'panelist_request', 'request_id', 'panelist'
        elif 'external evaluator' in title:
            is_request = title == 'external evaluator approval requested'
            candidates = Evaluator.objects.using(alias).filter(**(
                {'created_by_id': notification.sender_id, 'created_at__range': (start, end)} if is_request else
                {'created_by_id': notification.recipient_id, 'reviewed_by_id': notification.sender_id,
                 'reviewed_at__range': (start, end)}))
            matched = [item for item in candidates if notification.message.startswith(f'{item.name}:')]
            kind, key, route_kind = 'external_evaluator', 'evaluator_id', 'external'
        else:
            continue
        if len(matched) == 1:
            notification.action_payload = {**payload, 'action_kind': kind, key: matched[0].pk}
            base = 'admin' if notification.workspace == 'admin' else 'faculty'
            notification.action_route = f'/{base}/defense-board/requests/{route_kind}/{matched[0].pk}'
            notification.save(using=alias, update_fields=['action_payload', 'action_route'])


class Migration(migrations.Migration):
    dependencies = [('notifications', '0004_notification_workspace'),
                    ('user_management', '0009_guest_invitation_anchor')]
    operations = [migrations.RunPython(backfill_action_targets, migrations.RunPython.noop)]
