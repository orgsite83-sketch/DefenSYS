from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


def recover_single_file_uploaders(apps, schema_editor):
    File = apps.get_model('repository', 'DeliverableSubmissionFile')
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    alias = schema_editor.connection.alias
    # Only a container with exactly one revision has unambiguous attribution.
    # A multi-file container records its latest actor, not every file's actor.
    singles = (File.objects.using(alias).values('submission_id')
               .annotate(total=models.Count('id')).filter(total=1)
               .values('submission_id'))
    for submission in (Submission.objects.using(alias).filter(pk__in=singles)
                       .exclude(uploaded_by_id=None).iterator()):
        File.objects.using(alias).filter(submission_id=submission.pk).update(
            uploaded_by_id=submission.uploaded_by_id)


class Migration(migrations.Migration):
    dependencies = [
        ('repository', '0034_sharedmoduleredefensedecision'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]
    operations = [
        migrations.AddField(
            model_name='deliverablesubmissionfile', name='uploaded_by',
            field=models.ForeignKey(
                to=settings.AUTH_USER_MODEL, null=True, blank=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='uploaded_deliverable_files')),
        migrations.RunPython(recover_single_file_uploaders, migrations.RunPython.noop),
    ]
