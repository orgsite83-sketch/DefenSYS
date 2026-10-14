from django.db import migrations, models
import django.db.models.deletion


def snapshot_existing_submissions(apps, schema_editor):
    Submission = apps.get_model('repository', 'DeliverableSubmission')
    database = schema_editor.connection.alias
    for submission in Submission.objects.using(database).select_related('team').iterator():
        team = submission.team
        submission.archive_semester_id = team.semester_id
        submission.archive_team_name = team.name
        submission.archive_project_title = team.project_title
        submission.archive_year_level = team.year_level
        submission.archive_team_level = team.level
        submission.save(using=database, update_fields=[
            'archive_semester', 'archive_team_name', 'archive_project_title',
            'archive_year_level', 'archive_team_level',
        ])


class Migration(migrations.Migration):
    dependencies = [
        ('repository', '0019_deliverable_revision_review'),
        ('academic_period_management', '0005_semestertransitionlog'),
        ('defense', '0034_deliverable_submission_timing'),
    ]

    operations = [
        migrations.AddField(
            model_name='deliverablesubmission', name='archive_semester',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT,
                                    related_name='archive_deliverable_submissions',
                                    to='academic_period_management.semester'),
        ),
        migrations.AddField(
            model_name='deliverablesubmission', name='archive_team_name',
            field=models.CharField(blank=True, default='', max_length=120),
        ),
        migrations.AddField(
            model_name='deliverablesubmission', name='archive_project_title',
            field=models.CharField(blank=True, default='', max_length=255),
        ),
        migrations.AddField(
            model_name='deliverablesubmission', name='archive_year_level',
            field=models.CharField(blank=True, default='', max_length=20),
        ),
        migrations.AddField(
            model_name='deliverablesubmission', name='archive_team_level',
            field=models.CharField(blank=True, default='', max_length=30),
        ),
        migrations.AddField(
            model_name='deliverablesubmission', name='pit_event_config',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL,
                                    related_name='archive_deliverable_submissions',
                                    to='defense.piteventgradingconfig'),
        ),
        migrations.RunPython(snapshot_existing_submissions, migrations.RunPython.noop),
    ]
