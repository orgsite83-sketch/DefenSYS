from django.db import migrations, models
import django.db.models.deletion


def seed_grading_configs_from_rubrics(apps, schema_editor):
    StageGradingConfig = apps.get_model('defense', 'StageGradingConfig')
    Rubric = apps.get_model('grading', 'Rubric')

    seen = {}
    rubrics = (
        Rubric.objects.filter(scope='capstone', defense_stage_id__isnull=False)
        .order_by('-status', 'evaluation_type', '-updated_at')
    )
    for rubric in rubrics:
        key = (rubric.defense_stage_id, rubric.semester_id)
        if key in seen:
            continue
        if rubric.evaluation_type == 'panel' or rubric.status == 'published':
            seen[key] = {
                'panel_weight': rubric.panel_weight,
                'adviser_weight': rubric.adviser_weight,
                'peer_weight': rubric.peer_weight,
            }
        elif key not in seen:
            seen[key] = {
                'panel_weight': rubric.panel_weight,
                'adviser_weight': rubric.adviser_weight,
                'peer_weight': rubric.peer_weight,
            }

    for (stage_id, semester_id), weights in seen.items():
        StageGradingConfig.objects.get_or_create(
            defense_stage_id=stage_id,
            semester_id=semester_id,
            defaults=weights,
        )


class Migration(migrations.Migration):

    dependencies = [
        ('academic_period_management', '0001_initial'),
        ('defense', '0002_scheduler'),
        ('grading', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='StageGradingConfig',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('panel_weight', models.PositiveSmallIntegerField(default=50)),
                ('adviser_weight', models.PositiveSmallIntegerField(default=30)),
                ('peer_weight', models.PositiveSmallIntegerField(default=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'defense_stage',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='grading_configs',
                        to='defense.defensestage',
                    ),
                ),
                (
                    'semester',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='stage_grading_configs',
                        to='academic_period_management.semester',
                    ),
                ),
            ],
            options={
                'db_table': 'defense_stages_gradingconfig',
            },
        ),
        migrations.AddConstraint(
            model_name='stagegradingconfig',
            constraint=models.UniqueConstraint(
                fields=('defense_stage', 'semester'),
                name='unique_grading_config_per_stage_semester',
            ),
        ),
        migrations.RunPython(seed_grading_configs_from_rubrics, migrations.RunPython.noop),
    ]
