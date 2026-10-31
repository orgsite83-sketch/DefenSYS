#!/usr/bin/env python3
"""
DefenSYS Database Backup Script
Dumps the PostgreSQL database to a compressed custom-format file and cleans up old backups.
"""

import os
import sys
import subprocess
import datetime
import glob
import argparse
import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

# Default configuration
DEFAULT_RETENTION_DAYS = 7
DEFAULT_BACKUP_DIR = "/var/backups/defensys"
FALLBACK_BACKUP_DIR = "./backups"

def load_env_file():
    """Locate and load the database environment configuration from .env."""
    script_dir = Path(__file__).resolve().parent
    
    # Check possible paths for .env
    possible_paths = [
        script_dir / "../../backend/.env",
        Path.cwd() / "backend/.env",
        Path.cwd() / ".env",
        Path.home() / ".defensys.env"
    ]
    
    # Override via environment variable if set
    env_override = os.environ.get("DEFENSYS_ENV_PATH")
    if env_override:
        possible_paths.insert(0, Path(env_override))

    loaded = False
    for path in possible_paths:
        if path.exists():
            print(f"Loading environment from: {path.resolve()}")
            # Simple manual parser to avoid dependency issues if run outside venv
            try:
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "=" in line:
                            parts = line.split("=", 1)
                            key = parts[0].strip()
                            val = parts[1].strip().strip("'").strip('"')
                            os.environ.setdefault(key, val)
                loaded = True
                break
            except Exception as e:
                print(f"Warning: Failed to read {path}: {e}")
                
    if not loaded:
        print("Warning: No .env configuration file loaded. Falling back to environment defaults.")

def get_backup_dir():
    """Retrieve and verify the backup directory, with user and local fallbacks."""
    backup_dir = os.environ.get("DEFENSYS_BACKUP_DIR", DEFAULT_BACKUP_DIR)
    path = Path(backup_dir)
    
    try:
        path.mkdir(parents=True, exist_ok=True)
        # Try writing a small test file to verify permissions
        test_file = path / ".test_write"
        test_file.touch()
        test_file.unlink()
        return path
    except Exception:
        fallback_path = Path(__file__).resolve().parent / FALLBACK_BACKUP_DIR
        print(f"Warning: Cannot write to '{backup_dir}'. Using local fallback: '{fallback_path}'")
        fallback_path.mkdir(parents=True, exist_ok=True)
        return fallback_path

def perform_backup(backup_dir, *, snapshot=None):
    """Execute pg_dump to back up the database."""
    # Retrieve configuration with defaults
    db_name = os.environ.get("POSTGRES_DB", "defensys_db")
    db_user = os.environ.get("POSTGRES_USER", "defensys")
    db_password = os.environ.get("POSTGRES_PASSWORD", "")
    db_host = os.environ.get("POSTGRES_HOST", "localhost")
    db_port = os.environ.get("POSTGRES_PORT", "5432")
    
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    backup_file = backup_dir / f"defensys_db_{timestamp}.dump"
    
    print(f"Starting backup for database: '{db_name}' on '{db_host}:{db_port}'...")
    
    # Build command
    # -F c: Custom binary format (highly recommended for pg_restore)
    # -b: Include large objects
    # -v: Verbose output
    cmd = [
        "pg_dump",
        "-h", db_host,
        "-p", db_port,
        "-U", db_user,
        "-d", db_name,
        "-F", "c",
        "-b",
        "--no-password",
        "--lock-wait-timeout=10s",
        "-f", str(backup_file)
    ]
    if snapshot:
        cmd.append(f"--snapshot={snapshot}")
    
    # Execute pg_dump, passing the password securely via environment variables
    env = os.environ.copy()
    env["PGPASSWORD"] = db_password
    
    try:
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
        print(f"Success! Database backup completed: {backup_file.resolve()}")
        # Print pg_dump log warnings if any
        if result.stderr:
            print("pg_dump notes:\n" + result.stderr)
        return backup_file
    except subprocess.CalledProcessError as e:
        print(f"Error: Database backup failed!", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        # Clean up partial file if created
        if backup_file.exists():
            backup_file.unlink()
        sys.exit(1)
    except FileNotFoundError:
        print("Error: 'pg_dump' utility not found. Please make sure PostgreSQL client tools are installed.", file=sys.stderr)
        sys.exit(1)

def run_retention_cleanup(backup_dir):
    """Scan backup directory and remove files exceeding the retention limit."""
    try:
        retention_days = int(os.environ.get("DEFENSYS_BACKUP_RETENTION_DAYS", DEFAULT_RETENTION_DAYS))
    except ValueError:
        retention_days = DEFAULT_RETENTION_DAYS
        
    print(f"Cleaning up backups older than {retention_days} days in '{backup_dir}'...")
    
    cutoff = datetime.datetime.now() - datetime.timedelta(days=retention_days)
    pattern = str(backup_dir / "defensys_db_*.dump")
    files = glob.glob(pattern)
    
    removed_count = 0
    for file_path in files:
        path = Path(file_path)
        # Check modification time
        mtime = datetime.datetime.fromtimestamp(path.stat().st_mtime)
        if mtime < cutoff:
            try:
                path.unlink()
                print(f"Removed expired backup: {path.name} (Created {mtime.strftime('%Y-%m-%d %H:%M:%S')})")
                removed_count += 1
            except Exception as e:
                print(f"Warning: Failed to delete '{path.name}': {e}")
                
    print(f"Retention cleanup finished. Removed {removed_count} file(s).")

def verify_full_backup(path):
    """Read every archived byte and compare it with the recorded SHA-256."""
    with zipfile.ZipFile(path) as archive:
        manifest = json.loads(archive.read('manifest.json'))
        if manifest.get('format') != 'defensys-full-v1':
            raise ValueError('Unsupported full-backup format.')
        expected = {entry['path'] for entry in manifest['files']}
        names = archive.namelist()
        if len(names) != len(set(names)) or set(names) != expected | {'manifest.json'}:
            raise ValueError('Archive entries do not match the manifest.')
        for entry in manifest['files']:
            digest = hashlib.sha256()
            size = 0
            with archive.open(entry['path']) as stream:
                while chunk := stream.read(1024 * 1024):
                    digest.update(chunk)
                    size += len(chunk)
            if digest.hexdigest() != entry['sha256'] or size != entry['bytes']:
                raise ValueError(f"Archive verification failed: {entry['path']}")
    print(f"Verified {len(expected)} files, including database, media and source.")
    return manifest


def perform_full_backup(output):
    """Capture PostgreSQL, local uploads, working source and recovery config.

    PostgreSQL counts and pg_dump share a read-only snapshot. Uploads are
    checked for concurrent edits; pause application writes for a coordinated
    database/media recovery point. Full archives never undergo dump retention.
    """
    root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(root / 'backend'))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')
    os.environ['SENTRY_DSN'] = ''
    from django.conf import settings
    import psycopg2
    from psycopg2 import sql

    if settings.STORAGES['default']['BACKEND'] != 'django.core.files.storage.FileSystemStorage':
        raise ValueError('Full backup currently supports local filesystem uploads only.')
    media = Path(settings.STORAGES['default']['OPTIONS']['location']).resolve()
    output = Path(output).resolve()
    if output == media or output.is_relative_to(media):
        raise ValueError('The backup destination must be outside the uploads folder.')
    if output.exists():
        raise FileExistsError(f'Refusing to replace an existing backup: {output}')
    for binary in ('pg_dump', 'pg_restore', 'git'):
        if not shutil.which(binary):
            raise ValueError(f'Required utility is missing: {binary}')
    output.parent.mkdir(parents=True, exist_ok=True)
    cfg = settings.DATABASES['default']
    for key, value in {'POSTGRES_DB': cfg['NAME'], 'POSTGRES_USER': cfg['USER'],
                       'POSTGRES_PASSWORD': cfg['PASSWORD'], 'POSTGRES_HOST': cfg['HOST'],
                       'POSTGRES_PORT': cfg['PORT']}.items():
        os.environ[key] = str(value)
    conn = psycopg2.connect(dbname=cfg['NAME'], user=cfg['USER'], password=cfg['PASSWORD'],
                            host=cfg['HOST'], port=cfg['PORT'], connect_timeout=10)
    conn.set_session(isolation_level='REPEATABLE READ', readonly=True)
    manifest = {
        'format': 'defensys-full-v1',
        'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'database': cfg['NAME'], 'media_root': str(media),
        'contains_secrets': True,
        'consistency': 'PostgreSQL snapshot; pause application writes to coordinate uploads.',
        'files': [], 'table_counts': {},
    }

    def media_inventory():
        inventory = {}
        if not media.is_dir():
            raise ValueError(f'Uploads directory is missing: {media}')
        for path in media.rglob('*'):
            if path.is_symlink() or not path.resolve().is_relative_to(media):
                raise ValueError(f'Uploads contain a link outside local storage: {path}')
            if path.is_file():
                stat = path.stat()
                inventory[path] = (stat.st_size, stat.st_mtime_ns)
        return inventory

    def add_file(archive, path, name):
        if path.is_symlink():
            raise ValueError(f'Cannot archive a symbolic link: {path}')
        before = path.stat()
        digest = hashlib.sha256()
        size = 0
        with path.open('rb') as source, archive.open(name, 'w', force_zip64=True) as target:
            while chunk := source.read(1024 * 1024):
                target.write(chunk)
                digest.update(chunk)
                size += len(chunk)
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise ValueError(f'File changed while backing up: {path}. Pause writes and rerun.')
        manifest['files'].append({'path': name, 'bytes': size, 'sha256': digest.hexdigest()})

    temporary_root = root / '.tmp'
    temporary_root.mkdir(exist_ok=True)
    created_archive = False
    try:
        initial_media = media_inventory()
        with tempfile.TemporaryDirectory(prefix='full-backup-', dir=temporary_root) as temporary:
            with conn.cursor() as cursor:
                cursor.execute('SELECT pg_export_snapshot(), version()')
                snapshot, manifest['postgres_version'] = cursor.fetchone()
                cursor.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")
                for (table,) in cursor.fetchall():
                    cursor.execute(sql.SQL('SELECT count(*) FROM public.{}').format(sql.Identifier(table)))
                    manifest['table_counts'][table] = cursor.fetchone()[0]
                dump = perform_backup(Path(temporary), snapshot=snapshot)
            conn.rollback()
            subprocess.run(['pg_restore', '--list', str(dump)], check=True, capture_output=True)
            source_names = subprocess.check_output(
                ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root,
            ).decode('utf-8').split('\0')
            source_files = {root / name for name in source_names if name and (root / name).is_file()}
            # These local instructions and docs are intentionally ignored by git.
            for directory in ('directives', 'docs'):
                if (root / directory).is_dir():
                    source_files.update(p for p in (root / directory).rglob('*') if p.is_file())
            configs = [root / name for name in ('.env', 'backend/.env', 'frontend/.env')
                       if (root / name).is_file()]
            with zipfile.ZipFile(output, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                created_archive = True
                add_file(archive, dump, 'database.dump')
                for path in sorted(initial_media):
                    add_file(archive, path, 'media/' + path.relative_to(media).as_posix())
                for path in sorted(source_files):
                    relative = path.relative_to(root)
                    if relative.parts[0] in {'.backups', '.sandbox', '.tmp', '.git'} or path in configs:
                        continue
                    if path.is_relative_to(media):
                        continue
                    add_file(archive, path, 'source/' + relative.as_posix())
                for path in configs:
                    add_file(archive, path, 'config/' + path.relative_to(root).as_posix())
                if initial_media != media_inventory():
                    raise ValueError('Uploads changed during backup. Pause application writes and rerun.')
                manifest['media_files'] = len(initial_media)
                manifest['media_bytes'] = sum(size for size, _ in initial_media.values())
                archive.writestr('manifest.json', json.dumps(manifest, indent=2))
        verify_full_backup(output)
    except BaseException:
        if created_archive:
            output.unlink(missing_ok=True)
        raise
    finally:
        conn.close()
    print(f'Full backup saved: {output} ({output.stat().st_size:,} bytes)')
    print('Contains private records and recovery configuration. Keep this archive private.')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--full', action='store_true', help='Back up DB, uploads, current source and .env.')
    mode.add_argument('--verify', type=Path, help='Verify every file in an existing full ZIP archive.')
    parser.add_argument('--output', type=Path, help='New ZIP path for --full; existing files are refused.')
    args = parser.parse_args()
    if args.output and not args.full:
        parser.error('--output requires --full.')
    if args.verify:
        verify_full_backup(args.verify)
        return
    if args.full:
        timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
        output = args.output or Path(__file__).resolve().parents[2] / '.backups' / f'defensys_full_{timestamp}.zip'
        perform_full_backup(output)
        return
    load_env_file()
    backup_dir = get_backup_dir()
    perform_backup(backup_dir)
    run_retention_cleanup(backup_dir)

if __name__ == "__main__":
    main()
