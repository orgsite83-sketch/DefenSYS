"""
Rename legacy defense tables to match consolidated db_table names.

Safe to run multiple times. Does not drop data.
"""
import os
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.db import connection

RENAMES = (
    ('defense_stages_defensestage', 'defense_stages_stage'),
    ('defense_scheduler_defenseschedule', 'defense_scheduler_schedule'),
)


def table_exists(cursor, name):
    cursor.execute(
        """
        SELECT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = %s
        )
        """,
        [name],
    )
    return cursor.fetchone()[0]


with connection.cursor() as cursor:
    for old_name, new_name in RENAMES:
        old_ok = table_exists(cursor, old_name)
        new_ok = table_exists(cursor, new_name)
        if new_ok:
            print(f'Skip {old_name} -> {new_name}: target already exists')
            continue
        if not old_ok:
            print(f'Skip {old_name} -> {new_name}: source missing')
            continue
        cursor.execute(f'ALTER TABLE "{old_name}" RENAME TO "{new_name}"')
        print(f'Renamed {old_name} -> {new_name}')

print('Done.')
