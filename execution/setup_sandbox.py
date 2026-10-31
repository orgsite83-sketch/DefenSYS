"""Create a new local, empty sandbox and apply migrations without seeding data.

Existing databases are refused. Run Django commands with settings_sandbox to
use it afterwards; this tool never rewrites backend/.env or normal settings.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SANDBOX_SETTINGS = 'defensys_backend.settings_sandbox'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default='defensys_sandbox', help='New defensys_sandbox[_name] database.')
    args = parser.parse_args()
    os.environ['DEFENSYS_SANDBOX_DB'] = args.database
    os.environ['DJANGO_SETTINGS_MODULE'] = SANDBOX_SETTINGS
    sys.path.insert(0, str(ROOT / 'backend'))
    # Loading settings validates both the name and host before any DB writes.
    from django.conf import settings
    import psycopg2
    from psycopg2 import sql

    cfg = settings.DATABASES['default']
    media = Path(settings.MEDIA_ROOT)
    if media.exists() and any(media.iterdir()):
        parser.error(f'Uploads already exist at {media}; use a new sandbox name for a fresh start.')
    conn = psycopg2.connect(dbname='postgres', user=cfg['USER'], password=cfg['PASSWORD'],
                            host=cfg['HOST'], port=cfg['PORT'], connect_timeout=10)
    conn.autocommit = True
    try:
        with conn.cursor() as cursor:
            cursor.execute('SELECT 1 FROM pg_database WHERE datname = %s', [cfg['NAME']])
            if cursor.fetchone():
                parser.error(f"Database {cfg['NAME']} already exists; nothing was changed. Use another name.")
            cursor.execute(sql.SQL('CREATE DATABASE {} TEMPLATE template0').format(sql.Identifier(cfg['NAME'])))
    finally:
        conn.close()
    print(f"Created separate database: {cfg['NAME']}", flush=True)
    # No custom script ORM writes: all schema/data migration work belongs to
    # Django's normal migrate command, explicitly scoped to sandbox settings.
    result = subprocess.run([sys.executable, str(ROOT / 'backend/manage.py'), 'migrate',
                             f'--settings={SANDBOX_SETTINGS}', '--noinput'], cwd=ROOT)
    if result.returncode:
        print('Migration failed. The original DB is untouched; the partial sandbox is retained.\n'
              f'Resume with migrate --settings={SANDBOX_SETTINGS} using the same sandbox name.', file=sys.stderr)
        return result.returncode
    Path(settings.MEDIA_ROOT).mkdir(parents=True, exist_ok=True)
    print(f"Sandbox ready: {cfg['NAME']}\nUploads: {settings.MEDIA_ROOT}\n"
          'No user accounts or sample teams were created. Create your own admin with createsuperuser.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
