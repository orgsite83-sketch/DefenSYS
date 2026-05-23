import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('student_teams', '0003_teamdocument'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='WeeklyProgressReport',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('week_number', models.PositiveSmallIntegerField()),
                ('report_date', models.DateField()),
                ('accomplishments', models.JSONField(blank=True, default=list)),
                ('contributions', models.JSONField(blank=True, default=list)),
                ('issues', models.JSONField(blank=True, default=list)),
                ('plans', models.JSONField(blank=True, default=list)),
                ('report_file', models.FileField(blank=True, null=True, upload_to='weekly_reports/%Y/%m/')),
                ('file_size', models.CharField(blank=True, max_length=50, null=True)),
                ('extracted_text', models.TextField(blank=True, default='', help_text='Full text extracted from PDF for ML search')),
                ('topics', models.JSONField(blank=True, default=list, help_text='Auto-extracted keywords/topics from PDF content')),
                ('summary', models.TextField(blank=True, default='', help_text='Auto-generated summary of PDF content')),
                ('submitted_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('student', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='weekly_progress_reports', to=settings.AUTH_USER_MODEL)),
                ('team', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='student_progress_reports', to='student_teams.studentteam')),
            ],
            options={
                'db_table': 'student_weekly_progress_weeklyprogressreport',
                'ordering': ['-report_date', '-week_number'],
                'indexes': [
                    models.Index(fields=['student', 'report_date'], name='student_wee_student_059a10_idx'),
                    models.Index(fields=['team', 'report_date'], name='student_wee_team_id_0cb02e_idx'),
                ],
                'constraints': [
                    models.UniqueConstraint(fields=('student', 'team', 'week_number'), name='unique_student_weekly_report'),
                ],
            },
        ),
    ]
