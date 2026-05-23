from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('grading', '0001_initial'),
        ('defense', '0008_clear_stage_deliverable_seed'),
    ]

    operations = [
        migrations.AddField(
            model_name='stagegradingconfig',
            name='panel_rubric',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='stage_configs_as_panel',
                to='grading.rubric',
            ),
        ),
        migrations.AddField(
            model_name='stagegradingconfig',
            name='adviser_rubric',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='stage_configs_as_adviser',
                to='grading.rubric',
            ),
        ),
        migrations.AddField(
            model_name='stagegradingconfig',
            name='peer_rubric',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='stage_configs_as_peer',
                to='grading.rubric',
            ),
        ),
    ]
