"""Verify and stage a full backup inside an isolated online testing checkout.

No database connections, configuration changes, or service restarts occur here.
Run using the server's existing backend virtualenv Python.
"""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import os
import shutil
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    checkout = args.checkout.expanduser().resolve(strict=True)
    archive_path = args.archive.expanduser().resolve(strict=True)
    allowed = (Path.home() / 'defensys-environments').resolve()
    if not checkout.is_relative_to(allowed) or checkout == allowed:
        parser.error('Checkout must be inside ~/defensys-environments/.')
    if checkout.name not in ('usertest', 'clienttest'):
        parser.error('Expected a named isolated testing checkout.')
    if checkout.name == 'clienttest':
        parser.error('Client testing must start fresh, without restoring backup records.')
    media = checkout / 'backend/media'
    recovery = checkout / 'recovery'
    for target in (media, recovery):
        if target.exists() or target.is_symlink():
            parser.error(f'Target already exists; refusing to overwrite: {target}')
    verifier = checkout / 'deployment/backup/backup_db.py'
    spec = importlib.util.spec_from_file_location('defensys_backup_verifier', verifier)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    manifest = module.verify_full_backup(archive_path)
    entries = [entry for entry in manifest['files']
               if entry['path'] == 'database.dump' or entry['path'].startswith('media/')]
    if sum(entry['path'] == 'database.dump' for entry in entries) != 1:
        parser.error('Backup must contain exactly one database.dump.')
    media_entries = [entry for entry in entries if entry['path'].startswith('media/')]
    if len(media_entries) != manifest['media_files']:
        parser.error('Media count does not match the manifest.')
    required = sum(entry['bytes'] for entry in entries)
    if shutil.disk_usage(checkout).free < required + 512 * 1024 * 1024:
        parser.error('Insufficient free disk space for extraction and working headroom.')
    print(json.dumps({'checkout': str(checkout), 'archive': str(archive_path),
                      'media_files': len(media_entries), 'extracted_bytes': required,
                      'apply': args.apply}), flush=True)
    if not args.apply:
        return

    # Staging stays private even if the caller has a permissive shell umask.
    os.umask(0o077)
    stage = Path(tempfile.mkdtemp(prefix='.restore-stage-', dir=checkout))
    (stage / 'media').mkdir()
    copied = 0
    with zipfile.ZipFile(archive_path) as archive:
        for entry in entries:
            name = PurePosixPath(entry['path'])
            if name.is_absolute() or '..' in name.parts or '\\' in entry['path']:
                raise ValueError('Unsafe archive path: ' + entry['path'])
            destination = stage.joinpath(*name.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256()
            size = 0
            with archive.open(entry['path']) as source, destination.open('xb') as output:
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)
                    digest.update(chunk)
                    size += len(chunk)
            if digest.hexdigest() != entry['sha256'] or size != entry['bytes']:
                raise ValueError('Extracted file verification failed: ' + entry['path'])
            copied += 1
            if copied % 10000 == 0:
                print(f'Extracted and verified {copied:,} files...', flush=True)
    summary = {
        'archive': str(archive_path), 'source_database': manifest['database'],
        'backup_created_at': manifest['created_at'],
        'table_counts': manifest['table_counts'],
        'media_files': len(media_entries),
        'media_bytes': sum(entry['bytes'] for entry in media_entries),
        'database_sha256': next(entry['sha256'] for entry in entries
                                if entry['path'] == 'database.dump'),
    }
    (stage / 'restore_manifest.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    if media.exists() or recovery.exists():
        raise ValueError('Restore target appeared during extraction; staging retained.')
    stage.rename(recovery)
    (recovery / 'media').rename(media)
    print(f'Prepared {len(media_entries):,} media files: {media}', flush=True)
    print(f'Database dump: {recovery / "database.dump"}', flush=True)
    print('Staging complete. No database or running service was changed.', flush=True)


if __name__ == '__main__':
    main()
