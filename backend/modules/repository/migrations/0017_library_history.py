from django.db import migrations, models


def preserve_saved_shelves(apps, schema_editor):
    shelf = apps.get_model('repository', 'UserBookShelf')
    shelf.objects.using(schema_editor.connection.alias).filter(
        status__in=['want_to_read', 'favorited'],
    ).update(is_saved=True)
    # Existing reading records are history, not proof of completed reading.
    for item in shelf.objects.using(schema_editor.connection.alias).filter(
        status__in=['reading', 'completed'],
    ).iterator():
        item.last_opened_at = item.updated_at
        item.save(using=schema_editor.connection.alias, update_fields=['last_opened_at'])


class Migration(migrations.Migration):
    dependencies = [('repository', '0016_project_classification_evidence')]
    operations = [
        migrations.AddField(model_name='userbookshelf', name='is_saved',
                            field=models.BooleanField(default=False)),
        migrations.AddField(model_name='userbookshelf', name='last_opened_at',
                            field=models.DateTimeField(blank=True, null=True)),
        migrations.RunPython(preserve_saved_shelves, migrations.RunPython.noop),
    ]
