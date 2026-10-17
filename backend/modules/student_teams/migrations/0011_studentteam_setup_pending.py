from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('student_teams', '0010_sectionassignment_concept_policies_and_more')]
    operations = [
        migrations.AddField(model_name='studentteam', name='setup_pending',
                            field=models.BooleanField(default=False)),
        migrations.AddField(model_name='studentteam', name='project_pending',
                            field=models.BooleanField(default=False)),
        migrations.AlterField(model_name='studentteam', name='project_title',
                              field=models.CharField(max_length=255, blank=True)),
    ]
