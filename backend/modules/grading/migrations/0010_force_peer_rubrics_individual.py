from django.db import migrations

def force_peer_rubrics_to_individual(apps, schema_editor):
    Rubric = apps.get_model('grading', 'Rubric')
    Rubric.objects.filter(evaluation_type='peer').update(target_type='individual')

class Migration(migrations.Migration):
    dependencies = [
        ('grading', '0009_studentstagegrade_and_more'),
    ]

    operations = [
        migrations.RunPython(force_peer_rubrics_to_individual),
    ]
