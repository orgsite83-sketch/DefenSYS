from django.db import migrations, models


def initialize_versions(apps, schema_editor):
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    File = apps.get_model('repository', 'DeliverableSubmissionFile')
    alias = schema_editor.connection.alias
    for submission in Submission.objects.using(alias).iterator():
        files = list(File.objects.using(alias).filter(submission_id=submission.pk).order_by('uploaded_at', 'pk'))
        for index, row in enumerate(files, 1):
            row.revision = index
            row.is_current = index == len(files)
            row.status = submission.status
            row.feedback = submission.feedback
            row.reviewed_at = submission.reviewed_at
            row.reviewed_by_id = submission.reviewed_by_id
            row.save(using=alias, update_fields=['revision', 'is_current', 'status', 'feedback', 'reviewed_at', 'reviewed_by'])


class Migration(migrations.Migration):
    dependencies = [('repository', '0022_deliverablesubmissionfile_feedback_and_more')]
    operations = [
        migrations.RunPython(initialize_versions, migrations.RunPython.noop),
        # Updating reviewed_by queues PostgreSQL's deferred FK triggers. Finish
        # those checks before CREATE INDEX in the same migration transaction.
        migrations.RunSQL('SET CONSTRAINTS ALL IMMEDIATE', reverse_sql=migrations.RunSQL.noop),
        migrations.AddConstraint(model_name='deliverablesubmissionfile',
            constraint=models.UniqueConstraint(fields=('submission', 'slot_key'),
                condition=models.Q(is_current=True), name='unique_current_document_slot')),
    ]
