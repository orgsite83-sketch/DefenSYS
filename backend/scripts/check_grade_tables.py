import os
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.db import connection

EXPECTED = [
    'rubric_engine_rubric',
    'rubric_engine_rubriccriterion',
    'grade_center_teamgrade',
    'grade_center_studentpeergrade',
    'grade_center_gradebreakdown',
]

with connection.cursor() as cursor:
    cursor.execute(
        """
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
        AND (tablename LIKE 'grade%%' OR tablename LIKE 'rubric%%')
        ORDER BY 1
        """
    )
    existing = {row[0] for row in cursor.fetchall()}

print('Existing grade/rubric tables:', sorted(existing))
for name in EXPECTED:
    print(f'  {name}:', 'OK' if name in existing else 'MISSING')
