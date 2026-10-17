from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('defense', '0038_piteventgradingconfig_concept_config')]
    operations = [
        migrations.AddField(model_name='piteventgradingconfig', name='team_membership_policy',
            field=models.CharField(max_length=20, default='single', choices=[
                ('single', 'One team per student'), ('multiple', 'Multiple teams per student')])),
    ]
