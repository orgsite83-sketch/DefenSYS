"""Remove the orphan table left by the retired schedule-import migration.

Some existing databases applied 0027_schedule_import_attempt, which is no
longer part of the migration graph. Its table has no current model, but its
actor foreign key prevents Django's normal flush from truncating users.
Schedule/import drafts are stored in the frontend's SharedPreferences.
"""

from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ('defense', '0032_minutes_external_panelists'),
    ]

    operations = [
        # IF EXISTS supports fresh databases. Omit CASCADE so unexpected
        # dependencies stop the migration rather than being removed as well.
        # This cleanup is irreversible: the retired table is not recreated.
        migrations.RunSQL(
            sql='DROP TABLE IF EXISTS "defense_scheduler_import_attempt";',
        ),
    ]
