"""Restore a full local backup into a new DB, preserving the previous setup."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'backend'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--reuse-media', action='store_true', help='Retain local media after verifying every backup file checksum.')
    args = parser.parse_args()
    explicit_database = os.environ.get('POSTGRES_DB')
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    from django.conf import settings
    import psycopg2
    from psycopg2 import sql
    from deployment.backup.backup_db import verify_full_backup

    cfg = settings.DATABASES['default']
    if cfg['HOST'] not in ('localhost', '127.0.0.1', '::1'):
        parser.error('Only a local PostgreSQL server can be restored.')
    if explicit_database:
        parser.error('Unset POSTGRES_DB first so backend/.env controls the switch.')
    media = Path(settings.MEDIA_ROOT).resolve()
    if media != (ROOT / 'backend/media').resolve() or media.is_symlink():
        parser.error('Expected the normal local backend/media directory.')
    if settings.STORAGES['default']['BACKEND'] != 'django.core.files.storage.FileSystemStorage':
        parser.error('Only local filesystem media is supported.')
    archive_path = args.archive.resolve()
    manifest = verify_full_backup(archive_path)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    target = 'defensys_restored_' + stamp
    recovery = (ROOT / '.backups' / ('before_restore_' + stamp)).resolve()
    stage = (ROOT / '.tmp' / ('restore_' + stamp)).resolve()
    for path in (recovery, stage, media):
        if not path.is_relative_to(ROOT):
            parser.error('Recovery paths must remain inside the workspace.')
    env_path = ROOT / 'backend/.env'
    original_env = env_path.read_bytes()
    env_text = original_env.decode('utf-8-sig')
    pattern = r'(?m)^(POSTGRES_DB\s*=)[^\r\n]*'
    if len(re.findall(pattern, env_text)) != 1:
        parser.error('Expected exactly one POSTGRES_DB entry in backend/.env.')
    print(json.dumps({'backup': str(archive_path), 'previous_database': cfg['NAME'],
                      'new_database': target, 'media_files': manifest['media_files'],
                      'preserved_setup': str(recovery), 'reuse_media': args.reuse_media, 'apply': args.apply}), flush=True)
    if not args.apply:
        return

    stage.mkdir(parents=True, exist_ok=False)
    recovery.mkdir(parents=True, exist_ok=False)
    (recovery / 'backend.env').write_bytes(original_env)
    staged_media = stage / 'media'
    staged_media.mkdir()
    checked_media_dirs = set()
    with zipfile.ZipFile(archive_path) as archive:
        for entry in manifest['files']:
            name = entry['path']
            if name != 'database.dump' and not name.startswith('media/'):
                continue
            if args.reuse_media and name.startswith('media/'):
                relative = Path(name[6:])
                if relative.is_absolute() or '..' in relative.parts:
                    raise ValueError('Media entry escapes local media directory.')
                existing = media / relative
                for directory in existing.parents:
                    if directory == media:
                        break
                    if directory not in checked_media_dirs:
                        if directory.is_symlink() or directory.is_junction():
                            raise ValueError('Linked media directory is not supported.')
                        checked_media_dirs.add(directory)
                if existing.is_symlink() or not existing.is_file():
                    raise ValueError('Backup media file is absent locally: ' + name)
                digest = hashlib.sha256()
                with existing.open('rb') as source:
                    while chunk := source.read(1024 * 1024):
                        digest.update(chunk)
                if digest.hexdigest() != entry['sha256']:
                    raise ValueError('Local media checksum mismatch: ' + name)
                continue
            destination = (stage / name).resolve()
            if not destination.is_relative_to(stage):
                raise ValueError('Archive entry escapes staging directory.')
            destination.parent.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256()
            with archive.open(name) as source, destination.open('xb') as output:
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
                    output.write(chunk)
            if digest.hexdigest() != entry['sha256']:
                raise ValueError('Extracted file checksum mismatch: ' + name)
    print('Matching database and media extracted and verified.', flush=True)
    connect = dict(user=cfg['USER'], password=cfg['PASSWORD'], host=cfg['HOST'],
                   port=cfg['PORT'], connect_timeout=10)
    with psycopg2.connect(dbname=cfg['NAME'], **connect) as conn:
        with conn.cursor() as cursor:
            cursor.execute('SELECT current_database(), host(inet_server_addr())')
            actual, address = cursor.fetchone()
            if actual != cfg['NAME'] or address not in ('127.0.0.1', '::1'):
                raise ValueError('Unexpected database server identity.')
    admin = psycopg2.connect(dbname='postgres', **connect)
    admin.autocommit = True
    try:
        with admin.cursor() as cursor:
            cursor.execute(sql.SQL('CREATE DATABASE {} TEMPLATE template0').format(sql.Identifier(target)))
    finally:
        admin.close()
    pg_env = os.environ.copy()
    pg_env['PGPASSWORD'] = str(cfg['PASSWORD'])
    subprocess.run(['pg_restore', '-h', str(cfg['HOST']), '-p', str(cfg['PORT']),
                    '-U', str(cfg['USER']), '-d', target, '--no-password', '--no-owner',
                    '--no-privileges', '--exit-on-error', '--single-transaction',
                    str(stage / 'database.dump')], env=pg_env, check=True)
    counts = {}
    with psycopg2.connect(dbname=target, **connect) as conn:
        conn.set_session(readonly=True)
        with conn.cursor() as cursor:
            for table, expected in manifest['table_counts'].items():
                cursor.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(table)))
                counts[table] = cursor.fetchone()[0]
                if counts[table] != expected:
                    raise ValueError('Restored table count mismatch: ' + table)
    print('All restored table counts match the backup.', flush=True)
    migrate_env = os.environ.copy()
    migrate_env['POSTGRES_DB'] = target
    subprocess.run([sys.executable, str(ROOT / 'backend/manage.py'), 'migrate', '--noinput'],
                   env=migrate_env, cwd=ROOT, check=True)
    # Switch only after restoration, checks and migrations succeed.
    if env_path.read_bytes() != original_env:
        raise ValueError('backend/.env changed during restore; refusing to replace it.')
    previous_media = recovery / 'media'
    had_media = media.exists() and not args.reuse_media
    if had_media:
        media.rename(previous_media)
    try:
        if not args.reuse_media:
            staged_media.rename(media)
        updated = re.sub(pattern, lambda m: m.group(1) + target, env_text)
        encoding = 'utf-8-sig' if original_env.startswith(b'\xef\xbb\xbf') else 'utf-8'
        replacement = stage / 'backend.env'
        replacement.write_bytes(updated.encode(encoding))
        os.replace(replacement, env_path)
    except BaseException:
        if not args.reuse_media and media.exists():
            media.rename(stage / 'media_after_failed_switch')
        if had_media:
            previous_media.rename(media)
        raise
    report = {'archive': str(archive_path), 'database': target,
              'previous_database': cfg['NAME'],
              'previous_media': None if args.reuse_media else str(previous_media),
              'media_reused': args.reuse_media,
              'previous_env': str(recovery / 'backend.env'),
              'media_files': manifest['media_files'], 'verified_table_counts': counts}
    (recovery / 'restore_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Local database and media switched successfully. Recovery report: ' + str(recovery / 'restore_report.json'))


if __name__ == '__main__':
    main()
