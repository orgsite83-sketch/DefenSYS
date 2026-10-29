from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('grading', '0024_rubric_custom_scale')]

    operations = [
        migrations.AddField(model_name='teamgrade', name='outcome_metadata',
            field=models.JSONField(default=dict, blank=True, editable=False)),
        migrations.AddField(model_name='gradeattempthistory', name='outcome_metadata',
            field=models.JSONField(default=dict, blank=True)),
    ]
