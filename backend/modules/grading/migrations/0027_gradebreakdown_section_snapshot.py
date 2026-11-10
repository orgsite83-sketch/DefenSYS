from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('grading', '0026_panelistcriterionscore_section_snapshot_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='gradebreakdown',
            name='section_snapshot',
            field=models.CharField(blank=True, default='', max_length=150),
        ),
    ]

