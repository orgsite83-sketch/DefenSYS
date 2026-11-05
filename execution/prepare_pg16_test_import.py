"""Prepare an atomic PostgreSQL 16 trial import from the verified user-test dump.

Uses a newer local pg_restore to decode the archive. Removes only the unsupported
transaction_timeout session setting, preserving schema and data. Actual PG16
compatibility is established by the server import, not by this conversion.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dump', type=Path, required=True)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--pg-restore', default='pg_restore')
    args = p.parse_args()
    output = args.output.resolve()
    metadata = output.with_suffix(output.suffix + '.json')
    if output.exists() or metadata.exists():
        p.error('Output already exists; refusing to replace it.')
    with zipfile.ZipFile(args.archive) as archive:
        manifest = json.loads(archive.read('manifest.json'))
    source_hash = digest(args.dump)
    expected = next(e['sha256'] for e in manifest['files'] if e['path'] == 'database.dump')
    if source_hash != expected:
        p.error('Source dump checksum does not match the backup manifest.')
    counts = manifest['table_counts']
    if any(not re.fullmatch('[a-z_][a-z_0-9]*', name) for name in counts):
        p.error('Unexpected table identifier in the manifest.')
    guard = "DO $identity$ BEGIN IF current_database() <> 'defensys_usertest' OR current_user <> 'defensys_usertest' THEN RAISE EXCEPTION 'Wrong testing database or role'; END IF; END $identity$;\n"
    checks = ['DO $counts$ DECLARE actual bigint; BEGIN']
    for table, count in counts.items():
        if not isinstance(count, int) or count < 0:
            p.error('Invalid manifest table count.')
        checks.append(f'SELECT count(*) INTO actual FROM public."{table}";')
        checks.append(f"IF actual <> {count} THEN RAISE EXCEPTION 'Backup count mismatch: {table}'; END IF;")
    checks.append('END $counts$;\n')
    output.parent.mkdir(parents=True, exist_ok=True)
    removed = 0
    with tempfile.TemporaryDirectory(dir=output.parent) as temp:
        raw = Path(temp) / 'restore.sql'
        subprocess.run([args.pg_restore, '--no-owner', '--no-privileges',
                        '--file', str(raw), str(args.dump)], check=True)
        with raw.open('rb') as source, output.open('xb') as dest:
            dest.write(guard.encode())
            in_copy = False
            for line in source:
                if not in_copy and line.rstrip(b'\r\n') == b'SET transaction_timeout = 0;':
                    removed += 1
                    continue
                if not in_copy and line.startswith(b'\\connect'):
                    raise ValueError('Dump changes database connection; refused.')
                dest.write(line)
                if not in_copy and line.startswith(b'COPY ') and line.rstrip().endswith(b'FROM stdin;'):
                    in_copy = True
                elif in_copy and line.rstrip(b'\r\n') == b'\\.':
                    in_copy = False
            if in_copy or removed != 1:
                raise ValueError('Unexpected SQL structure; do not upload this output.')
            dest.write(('\n' + '\n'.join(checks)).encode())
    record = {'source_dump_sha256': source_hash, 'sql_sha256': digest(output),
              'target_major': 16, 'database': 'defensys_usertest',
              'role': 'defensys_usertest', 'table_counts': counts,
              'removed_settings': ['SET transaction_timeout = 0;'],
              'validated_on_pg16': False}
    metadata.write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(json.dumps({'sql': str(output), 'metadata': str(metadata),
                      'bytes': output.stat().st_size, 'sha256': record['sql_sha256'],
                      'status': 'Prepared for an atomic PG16 import and count verification.'}, indent=2))


if __name__ == '__main__':
    main()
