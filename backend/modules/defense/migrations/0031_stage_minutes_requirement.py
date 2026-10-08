from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('defense', '0030_defenseschedule_project_title_snapshot_and_more')]
    operations = [
        migrations.AddField(model_name='defensestage', name='minutes_required', field=models.BooleanField(default=False)),
        migrations.AddField(model_name='defensestage', name='minutes_deliverable_id', field=models.CharField(default='MINUTES', max_length=20)),
        migrations.AddField(model_name='defensestage', name='minutes_deliverable_label', field=models.CharField(blank=True, default='', max_length=180)),
        migrations.AddField(model_name='defenseschedule', name='minutes_required', field=models.BooleanField(blank=True, default=None, null=True)),
        migrations.AddField(model_name='defenseschedule', name='minutes_deliverable_id', field=models.CharField(blank=True, default='', max_length=20)),
        migrations.AddField(model_name='defenseschedule', name='minutes_deliverable_label', field=models.CharField(blank=True, default='', max_length=180)),
    ]
