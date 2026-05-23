"""Clear auto-seeded deliverables so every stage defaults to empty (admin-configured only)."""

from django.db import migrations


def clear_stage_deliverables(apps, schema_editor):
    StageDeliverable = apps.get_model('defense', 'StageDeliverable')
    StageDeliverable.objects.all().delete()


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0007_seed_stage_deliverables'),
    ]

    operations = [
        migrations.RunPython(clear_stage_deliverables, migrations.RunPython.noop),
    ]
