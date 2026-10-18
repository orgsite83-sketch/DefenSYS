from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('defense', '0039_pit_team_membership_policy')]
    operations = [
        migrations.AlterField(
            model_name='piteventgradingconfig', name='peer_grading_enabled',
            field=models.BooleanField(default=True),
        ),
    ]
