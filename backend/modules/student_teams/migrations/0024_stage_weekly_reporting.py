"""Stage-owned reporting periods; data is migrated after schema indexes commit."""

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('student_teams', '0023_weeklyreportingperiod_weeklyreportversion_and_more'),
        ('defense', '0050_defensestage_weekly_reporting'),
    ]

    operations = [
        migrations.AlterField(model_name='weeklyreportingperiod', name='semester',
            field=models.ForeignKey(on_delete=django.db.models.deletion.PROTECT,
                related_name='weekly_reporting_periods', to='academic_period_management.semester')),
        migrations.AddField(model_name='weeklyreportingperiod', name='defense_stage',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE,
                related_name='weekly_reporting_periods', to='defense.defensestage')),
        migrations.AddConstraint(model_name='weeklyreportingperiod',
            constraint=models.UniqueConstraint(fields=('defense_stage', 'semester'),
                name='unique_weekly_period_per_stage_term')),
    ]
