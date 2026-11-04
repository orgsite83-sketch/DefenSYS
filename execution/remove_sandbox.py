"""Back up and permanently remove one separate local sandbox and its uploads.

Preview by default. Active clients require explicit --disconnect-clients.
Never writes to the normal application database.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default='defensys_sandbox')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--disconnect-clients', action='store_true')
    args = parser.parse_args()
    os.environ['DJANGO_SETTINGS_MODULE'] = 'defensys_backend.settings_sandbox'
    os.environ['DEFENSYS_SANDBOX_DB'] = args.database
    sys.path[:0] = [str(ROOT / 'backend'), str(ROOT)]
    from django.conf import settings
    from defensys_backend import settings as normal_settings
    from execution.reset_sandbox import validate_target
    from deployment.backup.backup_db import perform_backup
    import psycopg2
    from psycopg2 import sql

    cfg = settings.DATABASES['default']
    normal = normal_settings.DATABASES['default']['NAME']
    validate_target(args.database, cfg['NAME'], normal, cfg['HOST'])
    parent = ROOT / '.sandbox'
    target = parent / args.database
    if parent.resolve() != parent.absolute() or target.resolve() != target.absolute():
        raise ValueError('Sandbox directory must not be a link or junction.')
    if target.resolve().parent != (ROOT / '.sandbox').resolve():
        raise ValueError('Removal target is outside the sandbox directory.')
    # Refuse linked descendants before backing up or removing anything.
    paths = list(target.rglob('*')) if target.exists() else []
    if any(p.resolve() != p.absolute() for p in paths):
        raise ValueError('Sandbox contains a link or junction.')
    conn = psycopg2.connect(dbname='postgres', user=cfg['USER'], password=cfg['PASSWORD'],
                            host=cfg['HOST'], port=cfg['PORT'], connect_timeout=10)
    conn.autocommit = True
    try:
        with conn.cursor() as cursor:
            cursor.execute('SELECT datname FROM pg_database WHERE datname IN (%s, %s)',
                           [args.database, normal])
            existing = {r[0] for r in cursor.fetchall()}
            if normal not in existing or args.database not in existing:
                raise ValueError('Expected separate normal and sandbox databases must both exist.')
            cursor.execute('SELECT count(*) FROM pg_stat_activity WHERE datname=%s', [args.database])
            active = cursor.fetchone()[0]
            print(json.dumps({'sandbox': args.database, 'normal_database_preserved': normal,
                              'directory': str(target), 'active_connections': active,
                              'apply': args.apply}), flush=True)
            if not args.apply:
                return
            if active and not args.disconnect_clients:
                raise RuntimeError('Stop sandbox clients before removal; nothing was deleted.')
            if active:
                cursor.execute('SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
                               'WHERE datname=%s', [args.database])
                if not all(row[0] for row in cursor.fetchall()):
                    raise RuntimeError('Could not disconnect all sandbox clients.')
            backup = ROOT / '.backups' / (args.database + '_before_removal_' +
                                         datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f'))
            backup.mkdir(parents=True, exist_ok=False)
            for key, value in {'POSTGRES_DB': args.database, 'POSTGRES_USER': cfg['USER'],
                               'POSTGRES_PASSWORD': cfg['PASSWORD'], 'POSTGRES_HOST': cfg['HOST'],
                               'POSTGRES_PORT': cfg['PORT']}.items():
                os.environ[key] = str(value)
            dump = perform_backup(backup)
            subprocess.run(['pg_restore', '--list', str(dump)], check=True, capture_output=True)
            uploads = backup / 'sandbox_files.zip'
            with zipfile.ZipFile(uploads, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
                for path in paths:
                    if path.is_file():
                        archive.write(path, path.relative_to(target).as_posix())
            with zipfile.ZipFile(uploads) as archive:
                if archive.testzip() is not None:
                    raise ValueError('Sandbox file archive verification failed.')
            # DROP refuses new active connections too; do not force-disconnect clients.
            cursor.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(args.database)))
            if target.exists():
                shutil.rmtree(target)
            cursor.execute('SELECT datname FROM pg_database WHERE datname IN (%s, %s)',
                           [args.database, normal])
            if {r[0] for r in cursor.fetchall()} != {normal}:
                raise RuntimeError('Database removal verification failed.')
            print(json.dumps({'removed': args.database, 'uploads_removed': not target.exists(),
                              'backup': str(backup), 'normal_database_preserved': normal}), flush=True)
    finally:
        conn.close()


if __name__ == '__main__':
    main()
