from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('grading', '0020_remove_peerevaluationsubmission_unique_peer_submission_per_evaluator_evaluatee_and_more')]
    operations = [
        migrations.AddField(model_name='teamgrade', name='legacy_deliverable_policy',
                            field=models.JSONField(blank=True, default=dict, editable=False)),
    ]
