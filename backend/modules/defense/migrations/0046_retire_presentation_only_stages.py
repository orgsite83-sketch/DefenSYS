from django.db import migrations


def retire_presentation_only(apps, schema_editor):
    stage = apps.get_model('defense', 'DefenseStage')
    stage.objects.using(schema_editor.connection.alias).filter(
        is_presentation_only=True,
    ).update(is_presentation_only=False)


class Migration(migrations.Migration):
    dependencies = [('defense', '0045_hearing_document_snapshot')]

    operations = [migrations.RunPython(retire_presentation_only, migrations.RunPython.noop)]
