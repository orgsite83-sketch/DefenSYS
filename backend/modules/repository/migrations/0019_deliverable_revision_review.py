from django.db import migrations, models


def restore_requested_reviews(apps, schema_editor):
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    AuditLog = apps.get_model('authentication_access_control', 'SystemAuditLog')
    database = schema_editor.connection.alias
    for submission in Submission.objects.using(database).filter(
        deliverable_type='pre', status__in=['rejected', 'pending'],
    ).iterator():
        request = AuditLog.objects.using(database).filter(
            action='repository.request_resubmission', target_type='DeliverableSubmission',
            target_id=str(submission.pk),
        ).order_by('-created_at', '-pk').first()
        if request and (request.new_values or {}).get('status') in {'Needs Revision', 'rejected'}:
            submission.revision_review_unlocked = True
            submission.save(using=database, update_fields=['revision_review_unlocked'])


class Migration(migrations.Migration):
    dependencies = [('repository', '0018_deliverable_file_replacement')]
    operations = [
        migrations.AddField(
            model_name='deliverablesubmission', name='revision_review_unlocked',
            field=models.BooleanField(default=False, help_text='Allow the requested pre-defense revision to be reviewed despite the stage lock.'),
        ),
        migrations.RunPython(restore_requested_reviews, migrations.RunPython.noop),
    ]
