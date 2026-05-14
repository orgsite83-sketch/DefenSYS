# Generated migration for adding file upload to WeeklyProgressReport

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('student_weekly_progress', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='weeklyprogressreport',
            name='report_file',
            field=models.CharField(blank=True, max_length=500, null=True),
        ),
        migrations.AddField(
            model_name='weeklyprogressreport',
            name='file_size',
            field=models.CharField(blank=True, max_length=50, null=True),
        ),
        migrations.AlterField(
            model_name='weeklyprogressreport',
            name='accomplishments',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AlterField(
            model_name='weeklyprogressreport',
            name='contributions',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AlterField(
            model_name='weeklyprogressreport',
            name='issues',
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AlterField(
            model_name='weeklyprogressreport',
            name='plans',
            field=models.JSONField(blank=True, default=list),
        ),
    ]
