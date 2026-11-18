from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('defense', '0052_merge_planned_window_sessions')]

    operations = [
        migrations.AddField(
            model_name='panelistevaluationdraft',
            name='versioned',
            field=models.BooleanField(default=False),
        ),
    ]
