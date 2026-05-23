from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0004_piteventgradingconfig'),
    ]

    operations = [
        migrations.AddField(
            model_name='piteventgradingconfig',
            name='is_officially_complete',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='piteventgradingconfig',
            name='peer_grading_enabled',
            field=models.BooleanField(default=False),
        ),
    ]
