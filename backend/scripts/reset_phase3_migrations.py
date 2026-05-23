"""One-off: align django_migrations after Phase 3 app consolidation (dev DB)."""
import os
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.db import connection

OLD_APPS = (
    'rubric_engine',
    'grade_center',
    'digital_vault',
    'capstone_deliverables',
    'repository_audit',
)
NEW_ROWS = (
    ('grading', '0001_initial'),
    ('grading', '0002_grades'),
    ('grading', '0003_peerevaluationsubmission'),
    ('repository', '0001_vaultentry'),
    ('repository', '0002_deliverablesubmission'),
    ('repository', '0003_repositoryauditlog'),
    ('repository', '0004_vaultentry_ml_category_and_approved_default'),
    ('repository', '0005_alter_vaultentry_file'),
    ('repository', '0006_audit_filter_indexes'),
    ('defense', '0001_initial'),
    ('defense', '0002_scheduler'),
    ('defense', '0003_stagegradingconfig'),
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

    # defense.0002_scheduler must appear applied after grading.0001_initial
    if connection.vendor == 'postgresql':
        cursor.execute(
            """
            UPDATE django_migrations AS g
            SET applied = d.applied - INTERVAL '1 second'
            FROM django_migrations AS d
            WHERE g.app = 'grading' AND g.name = '0001_initial'
              AND d.app = 'defense' AND d.name = '0002_scheduler'
              AND g.applied >= d.applied
            """
        )

print('Updated django_migrations for Phase 3 consolidation.')
