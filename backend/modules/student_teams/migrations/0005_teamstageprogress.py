import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models
from django.utils import timezone


def _single_id(queryset):
    ids = list(queryset.values_list('id', flat=True)[:2])
    return ids[0] if len(ids) == 1 else None


def backfill_team_stage_progress(apps, schema_editor):
    StudentTeam = apps.get_model('student_teams', 'StudentTeam')
    TeamStageProgress = apps.get_model('student_teams', 'TeamStageProgress')
    DefenseStage = apps.get_model('defense', 'DefenseStage')
    TeamGrade = apps.get_model('grading', 'TeamGrade')

    now = timezone.now()
    teams = StudentTeam.objects.filter(level__icontains='Capstone').exclude(
        ready_for_stage__isnull=True,
        current_defense_stage__isnull=True,
    )
    teams = teams.exclude(ready_for_stage='', current_defense_stage='')

    for team in teams.iterator():
        stage_label = team.ready_for_stage or team.current_defense_stage
        stage_id = _single_id(DefenseStage.objects.filter(label=stage_label))
        if stage_id is None:
            continue

        status = 'ready'
        if team.status == 'Approved':
            status = 'passed'
        elif team.status == 'Failed':
            status = 'failed'

        grade_id = (
            TeamGrade.objects.filter(
                team_id=team.id,
                semester_id=team.semester_id,
                scope='capstone',
                defense_stage_id=stage_id,
            )
            .values_list('id', flat=True)
            .first()
        )
        defaults = {
            'status': status,
            'grade_id': grade_id,
        }
        if status == 'ready':
            defaults['ready_at'] = now
        elif status in ('passed', 'failed'):
            defaults['graded_at'] = now

        TeamStageProgress.objects.update_or_create(
            team_id=team.id,
            semester_id=team.semester_id,
            defense_stage_id=stage_id,
            defaults=defaults,
        )


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0009_stagegradingconfig_rubrics'),
        ('grading', '0005_explicit_stage_identity'),
        ('student_teams', '0004_weeklyprogressreport'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='TeamStageProgress',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('status', models.CharField(choices=[('locked', 'Locked'), ('ready', 'Ready'), ('scheduled', 'Scheduled'), ('grading', 'Grading'), ('passed', 'Passed'), ('failed', 'Failed'), ('archived', 'Archived')], default='locked', max_length=20)),
                ('ready_at', models.DateTimeField(blank=True, null=True)),
                ('scheduled_at', models.DateTimeField(blank=True, null=True)),
                ('graded_at', models.DateTimeField(blank=True, null=True)),
                ('archived_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('created_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='created_team_stage_progress', to=settings.AUTH_USER_MODEL)),
                ('defense_stage', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='team_progress', to='defense.defensestage')),
                ('grade', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='stage_progress_records', to='grading.teamgrade')),
                ('semester', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='team_stage_progress', to='academic_period_management.semester')),
                ('team', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='stage_progress', to='student_teams.studentteam')),
                ('updated_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='updated_team_stage_progress', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['team__name', 'defense_stage__display_order', 'defense_stage__label'],
            },
        ),
        migrations.AddConstraint(
            model_name='teamstageprogress',
            constraint=models.UniqueConstraint(fields=('team', 'semester', 'defense_stage'), name='unique_team_stage_progress'),
        ),
        migrations.AddIndex(
            model_name='teamstageprogress',
            index=models.Index(fields=['semester', 'defense_stage', 'status'], name='team_stage_progress_idx'),
        ),
        migrations.RunPython(
            backfill_team_stage_progress,
            migrations.RunPython.noop,
        ),
    ]
