from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('grading', '0027_gradebreakdown_section_snapshot'),
    ]

    operations = [
        migrations.AlterField(
            model_name='rubriccriterion',
            name='name',
            field=models.CharField(max_length=1000),
        ),
        migrations.AlterField(
            model_name='gradebreakdown',
            name='criterion_name',
            field=models.CharField(max_length=1000),
        ),
        migrations.AlterField(
            model_name='panelistcriterionscore',
            name='criterion_name_snapshot',
            field=models.CharField(max_length=1000),
        ),
    ]
