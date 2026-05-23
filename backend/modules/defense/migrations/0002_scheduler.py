import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('academic_period_management', '0001_initial'),
        ('defense', '0001_initial'),
        ('grading', '0001_initial'),
        ('student_teams', '0001_initial'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='DefenseSchedule',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('batch_id', models.UUIDField(db_index=True, default=uuid.uuid4, editable=False)),
                ('scope', models.CharField(choices=[('capstone', 'Capstone'), ('pit', 'PIT')], default='capstone', max_length=20)),
                ('event_name', models.CharField(blank=True, max_length=120)),
                ('scheduled_date', models.DateField()),
                ('start_time', models.TimeField()),
                ('slot_duration', models.PositiveSmallIntegerField(default=60)),
                ('room', models.CharField(max_length=120)),
                ('status', models.CharField(choices=[('scheduled', 'Scheduled'), ('done', 'Done'), ('cancelled', 'Cancelled'), ('archived', 'Archived')], default='scheduled', max_length=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('created_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='created_defense_schedules', to=settings.AUTH_USER_MODEL)),
                ('defense_stage', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='defense_schedules', to='defense.defensestage')),
                ('rubric', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='defense_schedules', to='grading.rubric')),
                ('semester', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='defense_schedules', to='academic_period_management.semester')),
                ('team', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='defense_schedules', to='student_teams.studentteam')),
            ],
            options={
                'db_table': 'defense_scheduler_schedule',
                'ordering': ['scheduled_date', 'start_time', 'team__name'],
            },
        ),
        migrations.CreateModel(
            name='SchedulePanelist',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('order', models.PositiveSmallIntegerField(default=0)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('panelist', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='schedule_panel_assignments', to=settings.AUTH_USER_MODEL)),
                ('schedule', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='panel_assignments', to='defense.defenseschedule')),
            ],
            options={
                'db_table': 'defense_scheduler_schedulepanelist',
                'ordering': ['order', 'panelist__username'],
            },
        ),
        migrations.AddField(
            model_name='defenseschedule',
            name='panelists',
            field=models.ManyToManyField(blank=True, related_name='panel_defense_schedules', through='defense.SchedulePanelist', to=settings.AUTH_USER_MODEL),
        ),
        migrations.AddConstraint(
            model_name='schedulepanelist',
            constraint=models.UniqueConstraint(fields=('schedule', 'panelist'), name='unique_panelist_per_schedule'),
        ),
        migrations.AddIndex(
            model_name='defenseschedule',
            index=models.Index(fields=['scheduled_date', 'status'], name='defense_sch_schedul_idx'),
        ),
        migrations.AddIndex(
            model_name='defenseschedule',
            index=models.Index(fields=['scope', 'status'], name='defense_sch_scope_idx'),
        ),
        migrations.AddIndex(
            model_name='defenseschedule',
            index=models.Index(fields=['room', 'scheduled_date', 'start_time'], name='defense_sch_room_idx'),
        ),
    ]
