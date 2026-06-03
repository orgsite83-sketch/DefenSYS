from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('student_teams', '0005_teamstageprogress'),
    ]

    operations = [
        migrations.AddField(
            model_name='studentteam',
            name='section',
            field=models.CharField(blank=True, default='', max_length=80),
        ),
    ]
