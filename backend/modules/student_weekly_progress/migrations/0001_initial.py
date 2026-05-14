# Generated migration

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('student_teams', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='WeeklyProgressReport',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('week_number', models.PositiveSmallIntegerField()),
                ('report_date', models.DateField()),
                ('accomplishments', models.JSONField(default=list)),
                ('contributions', models.JSONField(default=list)),
                ('issues', models.JSONField(default=list)),
                ('plans', models.JSONField(default=list)),
                ('submitted_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('student', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='weekly_progress_reports', to=settings.AUTH_USER_MODEL)),
                ('team', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='student_progress_reports', to='student_teams.studentteam')),
            ],
            options={
                'ordering': ['-report_date', '-week_number'],
                'indexes': [
                    models.Index(fields=['student', 'report_date'], name='student_wee_student_idx'),
                    models.Index(fields=['team', 'report_date'], name='student_wee_team_id_idx'),
                ],
            },
        ),
        migrations.AddConstraint(
            model_name='weeklyprogressreport',
            constraint=models.UniqueConstraint(fields=('student', 'team', 'week_number'), name='unique_student_weekly_report'),
        ),
    ]
