from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0005_pitevent_group_flags'),
    ]

    operations = [
        migrations.AddField(
            model_name='stagegradingconfig',
            name='is_officially_complete',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='stagegradingconfig',
            name='peer_grading_enabled',
            field=models.BooleanField(default=False),
        ),
    ]
