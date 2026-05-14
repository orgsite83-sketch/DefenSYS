from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('academic_period_management', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='semester',
            name='capstone_peer_evaluation_enabled',
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name='semester',
            name='capstone_adviser_grading_enabled',
            field=models.BooleanField(default=True),
        ),
    ]
