from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('grading', '0018_preserve_project_titles_and_legacy_clearance')]

    operations = [
        migrations.AddField(
            model_name='gradebreakdown', name='weight_snapshot',
            field=models.DecimalField(blank=True, null=True, max_digits=5, decimal_places=2),
        ),
        migrations.AddField(
            model_name='panelistcriterionscore', name='weight_snapshot',
            field=models.DecimalField(blank=True, null=True, max_digits=5, decimal_places=2),
        ),
        migrations.AddField(
            model_name='peerevaluationsubmission', name='weighted_score',
            field=models.DecimalField(blank=True, null=True, max_digits=5, decimal_places=2),
        ),
    ]
