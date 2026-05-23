import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academic_period_management', '0001_initial'),
        ('defense', '0003_stagegradingconfig'),
        ('grading', '0002_grades'),
    ]

    operations = [
        migrations.CreateModel(
            name='PitEventGradingConfig',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('event_name', models.CharField(max_length=120)),
                ('panel_weight', models.PositiveSmallIntegerField(default=80)),
                ('peer_weight', models.PositiveSmallIntegerField(default=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'panel_rubric',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name='pit_event_configs_as_panel',
                        to='grading.rubric',
                    ),
                ),
                (
                    'peer_rubric',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name='pit_event_configs_as_peer',
                        to='grading.rubric',
                    ),
                ),
                (
                    'semester',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name='pit_event_grading_configs',
                        to='academic_period_management.semester',
                    ),
                ),
            ],
            options={
                'db_table': 'defense_scheduler_piteventgradingconfig',
                'ordering': ['event_name'],
            },
        ),
        migrations.AddConstraint(
            model_name='piteventgradingconfig',
            constraint=models.UniqueConstraint(
                fields=('semester', 'event_name'),
                name='unique_pit_event_config_per_semester',
            ),
        ),
    ]
