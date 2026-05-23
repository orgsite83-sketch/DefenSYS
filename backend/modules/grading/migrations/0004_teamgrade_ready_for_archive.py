from django.db import migrations, models


def backfill_pit_published_without_vault(apps, schema_editor):
    TeamGrade = apps.get_model('grading', 'TeamGrade')
    VaultEntry = apps.get_model('repository', 'VaultEntry')

    uploaded_team_ids = set(
        VaultEntry.objects.filter(
            entry_type='pit',
            team_id__isnull=False,
        ).values_list('team_id', flat=True)
    )

    grades = TeamGrade.objects.filter(
        scope='pit',
        status='published',
    ).select_related('team')

    for grade in grades:
        team_id = grade.team_id
        if team_id and team_id in uploaded_team_ids:
            continue
        grade.status = 'ready_for_archive'
        grade.save(update_fields=['status', 'updated_at'])


class Migration(migrations.Migration):

    dependencies = [
        ('grading', '0003_peerevaluationsubmission'),
        ('repository', '0003_repositoryauditlog'),
    ]

    operations = [
        migrations.AlterField(
            model_name='teamgrade',
            name='status',
            field=models.CharField(
                choices=[
                    ('pending', 'Pending'),
                    ('awaiting_peers', 'Awaiting Peers'),
                    ('ready_for_archive', 'Ready for Archive'),
                    ('published', 'Published'),
                ],
                default='pending',
                max_length=20,
            ),
        ),
        migrations.RunPython(
            backfill_pit_published_without_vault,
            migrations.RunPython.noop,
        ),
    ]
