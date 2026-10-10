from django.db import migrations, models


WORKSPACES = [
    ('admin', 'Administrator'), ('faculty', 'Faculty'), ('student', 'Student'),
    ('adviser', 'Project Adviser'), ('pit_lead', 'PIT Lead'),
    ('pit_instructor', 'PIT Instructor'), ('panelist', 'Panelist'),
    ('documenter', 'Minutes Documenter'), ('uploader', 'Uploader'),
    ('account', 'Account & Security'),
]


def backfill_workspaces(apps, schema_editor):
    Notification = apps.get_model('notifications', 'Notification')
    alias = schema_editor.connection.alias
    pending = []
    for notification in Notification.objects.using(alias).filter(workspace='').select_related('recipient').iterator(chunk_size=500):
        role = notification.recipient.role
        title = notification.title.lower()
        route = (notification.action_route or '').replace('_', '-')
        if notification.category in ('SECURITY', 'ANNOUNCEMENT'):
            workspace = 'account'
        elif role == 'admin' or route.startswith('/admin/'):
            workspace = 'admin'
        elif role == 'student':
            workspace = 'student'
        elif title in ('documenter assignment', 'minutes finalized') or route.startswith('/documenter'):
            workspace = 'documenter'
        elif title == 'minutes ready for review' or title.startswith('cc reminder:'):
            workspace = 'adviser' if notification.recipient.is_adviser else 'pit_instructor'
        elif 'panelist eligibility' in title or 'external evaluator' in title:
            workspace = 'pit_lead'
        elif route.startswith('/panelist'):
            workspace = 'panelist'
        else:
            workspace = role
        notification.workspace = workspace
        pending.append(notification)
        if len(pending) == 500:
            Notification.objects.using(alias).bulk_update(pending, ['workspace'])
            pending.clear()
    if pending:
        Notification.objects.using(alias).bulk_update(pending, ['workspace'])


class Migration(migrations.Migration):
    dependencies = [('notifications', '0003_alter_notification_category')]

    operations = [
        migrations.AddField(
            model_name='notification', name='workspace',
            field=models.CharField(blank=True, choices=WORKSPACES, default='', max_length=24,
                help_text='Inbox that owns this notification and its read state.'),
        ),
        migrations.RunPython(backfill_workspaces, migrations.RunPython.noop),
        migrations.AddIndex(
            model_name='notification',
            index=models.Index(fields=['recipient', 'workspace', 'is_read'], name='notif_recipient_workspace_read'),
        ),
    ]
