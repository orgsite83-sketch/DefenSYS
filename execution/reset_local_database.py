"""Explicitly empty one local application database after verifying recovery.

Preserves schema/migration history and recreates Django permissions. Uses actual
tables so pending model changes do not prevent a fresh-data reset. No uploads
or backup files are deleted.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'backend'), str(ROOT)]
os.environ['DJANGO_SETTINGS_MODULE'] = 'defensys_backend.settings'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--recovery-archive', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    import django
    django.setup()
    from django.conf import settings
    from django.db import connection, transaction
    from django.core.management.color import no_style
    from django.core.management.sql import emit_post_migrate_signal
    from defensys_backend.db_guard import assert_safe_for_orm_writes
    from deployment.backup.backup_db import perform_backup, verify_full_backup

    cfg = settings.DATABASES['default']
    if (connection.vendor != 'postgresql' or cfg['NAME'] != args.database or
            cfg['HOST'] not in {'localhost', '127.0.0.1', '::1'} or args.database != 'defensys_db'):
        raise ValueError('Only the explicitly named local defensys_db may be emptied.')
    if not args.apply:
        with connection.cursor() as cursor:
            tables = connection.introspection.table_names(cursor)
        print(json.dumps({'database': args.database, 'tables': len(tables), 'apply': False}))
        return
    assert_safe_for_orm_writes()
    verify_full_backup(args.recovery_archive)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    recovery = ROOT / '.backups' / f'before_full_reset_{stamp}'
    recovery.mkdir(parents=True, exist_ok=False)
    for key, value in {'POSTGRES_DB': cfg['NAME'], 'POSTGRES_USER': cfg['USER'],
                       'POSTGRES_PASSWORD': cfg['PASSWORD'], 'POSTGRES_HOST': cfg['HOST'],
                       'POSTGRES_PORT': cfg['PORT']}.items():
        os.environ[key] = str(value)
    dump = perform_backup(recovery)
    subprocess.run(['pg_restore', '--list', str(dump)], check=True, capture_output=True)
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL lock_timeout = '10s'")
            tables = sorted(connection.introspection.table_names(cursor))
            reset_tables = [t for t in tables if t != 'django_migrations']
            cursor.execute('LOCK TABLE ' + ', '.join(connection.ops.quote_name(t) for t in tables) +
                           ' IN ACCESS EXCLUSIVE MODE')
            cursor.execute('SELECT count(*) FROM django_migrations')
            migrations_before = cursor.fetchone()[0]
            for statement in connection.ops.sql_flush(no_style(), reset_tables,
                                                       reset_sequences=True, allow_cascade=False):
                cursor.execute(statement)
        emit_post_migrate_signal(verbosity=0, interactive=False, db='default')
        with connection.cursor() as cursor:
            remaining = {}
            for table in reset_tables:
                cursor.execute('SELECT count(*) FROM ' + connection.ops.quote_name(table))
                count = cursor.fetchone()[0]
                if count:
                    remaining[table] = count
            if set(remaining) - {'django_content_type', 'auth_permission'}:
                raise RuntimeError('Unexpected application rows after reset; rolling back: ' +
                                   ', '.join(sorted(remaining)))
            cursor.execute('SELECT count(*) FROM django_migrations')
            if cursor.fetchone()[0] != migrations_before:
                raise RuntimeError('Migration history changed; rolling back.')
        report = {'database': args.database, 'reset': True, 'application_tables_empty': True,
                  'system_rows_remaining': remaining, 'migration_records_preserved': migrations_before,
                  'recovery_dump': str(dump), 'uploads_and_backup_files': 'untouched'}
        (recovery / 'reset_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
