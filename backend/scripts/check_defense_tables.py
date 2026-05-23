import os
import sys

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
django.setup()

from django.db import connection

TABLES = [
    'defense_stages_defensestage',
    'defense_stages_stagedeliverable',
    'defense_scheduler_defenseschedule',
    'defense_scheduler_schedule',
    'defense_scheduler_schedulepanelist',
]

with connection.cursor() as cursor:
    for name in TABLES:
        cursor.execute(
            """
            SELECT EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = %s
            )
            """,
            [name],
        )
        print(f'{name}:', 'exists' if cursor.fetchone()[0] else 'missing')
