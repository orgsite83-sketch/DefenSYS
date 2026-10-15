from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0034_deliverable_submission_timing'),
    ]

    operations = [
        migrations.AddField(
            model_name='defenseschedule',
            name='materials_late_upload_until',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
