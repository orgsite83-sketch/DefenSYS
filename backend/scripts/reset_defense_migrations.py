"""One-off: align django_migrations after defense app consolidation (dev DB).

After this script, run fix_defense_table_names.py if you kept an existing database
(renames legacy table names to match consolidated db_table settings).
"""
import os
import subprocess
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.db import connection

OLD_APPS = ('defense_stages', 'defense_scheduler', 'defense_board')
NEW_ROWS = (
    ('defense', '0001_initial'),
    ('defense', '0002_scheduler'),
)

with connection.cursor() as cursor:
    for app in OLD_APPS:
        cursor.execute('DELETE FROM django_migrations WHERE app = %s', [app])
    for app, name in NEW_ROWS:
        cursor.execute(
            'SELECT 1 FROM django_migrations WHERE app = %s AND name = %s',
            [app, name],
        )
        if not cursor.fetchone():
            cursor.execute(
                'INSERT INTO django_migrations (app, name, applied) VALUES (%s, %s, NOW())',
                [app, name],
            )

print('Updated django_migrations for defense consolidation.')
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'fix_defense_table_names.py')], check=False)
