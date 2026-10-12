from django.db import migrations, models


def restore_legacy_requests(apps, schema_editor):
    """Restore permissions requested by the old remarks-only Choice B implementation."""
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    AuditLog = apps.get_model('authentication_access_control', 'SystemAuditLog')
    database = schema_editor.connection.alias
    legacy = Submission.objects.using(database).filter(
        deliverable_type='pre', status='accepted',
        feedback__icontains='Unlocked for file replacement by Admin',
    )
    for submission in legacy.iterator():
        submission.file_replacement_unlocked = True
        submission.file_replacement_reason = submission.feedback
        submission.save(using=database, update_fields=['file_replacement_unlocked', 'file_replacement_reason'])

    # Earlier requests were recorded without track tags and disappeared under the
    # Capstone/PIT audit filter. Add only scope information supported by the target.
    logs = AuditLog.objects.using(database).filter(
        action='repository.request_resubmission', target_type='DeliverableSubmission',
    )
    for log in logs.iterator():
        if not str(log.target_id).isdigit():
            continue
        submission = Submission.objects.using(database).select_related('team').filter(pk=int(log.target_id)).first()
        if not submission:
            continue
        team = submission.team
        track = 'pit' if 'pit' in (team.level or '').lower() else 'capstone'
        tags = {'scope': track, 'track': track, 'entry_type': track,
                'team_id': team.pk, 'team_name': team.name,
                'year_level': team.year_level, 'team_year_level': team.year_level}
        if track == 'pit':
            tags['pit_year_level'] = team.year_level
        for field in ('old_values', 'new_values'):
            values = dict(getattr(log, field) or {})
            for key, value in tags.items():
                values.setdefault(key, value)
            setattr(log, field, values)
        log.save(using=database, update_fields=['old_values', 'new_values'])


class Migration(migrations.Migration):
    dependencies = [
        ('repository', '0017_library_history'),
        ('authentication_access_control', '0019_audit_reference_labels'),
    ]

    operations = [
        migrations.AddField(
            model_name='deliverablesubmission', name='file_replacement_unlocked',
            field=models.BooleanField(default=False, help_text='Allow one replacement of an approved pre-defense file without changing its approval.'),
        ),
        migrations.AddField(
            model_name='deliverablesubmission', name='file_replacement_reason',
            field=models.TextField(blank=True, default=''),
        ),
        migrations.RunPython(restore_legacy_requests, migrations.RunPython.noop),
    ]
