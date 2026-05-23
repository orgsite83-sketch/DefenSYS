"""One-off: align django_migrations after Phase 2 app consolidation (dev DB)."""
import os
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.db import connection

OLD_APPS = ('student_academic_records', 'team_documents', 'student_weekly_progress')
NEW_ROWS = (
    ('user_management', '0003_studentacademicrecord'),
    ('student_teams', '0003_teamdocument'),
    ('student_teams', '0004_weeklyprogressreport'),
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

print('Updated django_migrations for Phase 2 consolidation.')
