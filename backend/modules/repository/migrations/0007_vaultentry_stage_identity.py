import django.db.models.deletion
from django.db import migrations, models


def _single_id(queryset):
    ids = list(queryset.values_list('id', flat=True)[:2])
    return ids[0] if len(ids) == 1 else None


def backfill_vaultentry_stage_identity(apps, schema_editor):
    VaultEntry = apps.get_model('repository', 'VaultEntry')
    DefenseStage = apps.get_model('defense', 'DefenseStage')

    capstone_entries = VaultEntry.objects.filter(entry_type='capstone').exclude(stage_label='')
    for entry in capstone_entries.iterator():
        stage_id = _single_id(DefenseStage.objects.filter(label=entry.stage_label))
        if stage_id is not None:
            VaultEntry.objects.filter(pk=entry.pk).update(defense_stage_id=stage_id)


class Migration(migrations.Migration):

    dependencies = [
        ('defense', '0009_stagegradingconfig_rubrics'),
        ('repository', '0006_audit_filter_indexes'),
    ]

    operations = [
        migrations.AddField(
            model_name='vaultentry',
            name='defense_stage',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='vault_entries',
                to='defense.defensestage',
            ),
        ),
        migrations.AddField(
            model_name='vaultentry',
            name='pit_event_config',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='vault_entries',
                to='defense.piteventgradingconfig',
            ),
        ),
        migrations.RunPython(
            backfill_vaultentry_stage_identity,
            migrations.RunPython.noop,
        ),
    ]
