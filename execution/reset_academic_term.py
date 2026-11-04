"""Preview or explicitly clear academic rows for one exact local semester.

Preserves accounts, periods, transition logs, all rows outside the reviewed
dependency closure, and physical uploads. Apply requires a reviewed revision
and an existing full recovery archive, then also saves a current database dump.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'backend'), str(ROOT)]
os.environ['DJANGO_SETTINGS_MODULE'] = 'defensys_backend.settings'


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--semester-id', type=int, required=True)
    parser.add_argument('--semester-label', required=True)
    parser.add_argument('--database', required=True)
    parser.add_argument('--revision')
    parser.add_argument('--recovery-archive', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    import django
    django.setup()
    from django.apps import apps
    from django.conf import settings
    from django.contrib.auth import get_user_model
    from django.db import connection, transaction
    from academic_period_management.models import Semester
    from defensys_backend.db_guard import assert_safe_for_orm_writes

    if connection.vendor != 'postgresql' or settings.DATABASES['default']['HOST'] not in {'localhost', '127.0.0.1', '::1'}:
        raise ValueError('Only local PostgreSQL is supported.')
    if connection.settings_dict['NAME'] != args.database:
        raise ValueError('Database name does not match.')
    models = sorted([m for m in apps.get_models(include_auto_created=True)
                     if m._meta.managed and not m._meta.proxy], key=lambda m: m._meta.label)
    protected = {get_user_model(), Semester, apps.get_model('academic_period_management.SchoolYear'),
                 apps.get_model('academic_period_management.SemesterTransitionLog')}
    protected_tables = {m._meta.db_table for m in protected}
    semester_table = Semester._meta.db_table
    if args.apply:
        assert_safe_for_orm_writes()
        if not args.revision or not args.recovery_archive or not args.recovery_archive.is_file():
            raise ValueError('Apply requires revision and existing full recovery archive.')
        from deployment.backup.backup_db import perform_backup, verify_full_backup
        verify_full_backup(args.recovery_archive)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
        recovery = ROOT / '.backups' / f'term_{args.semester_id}_before_reset_{stamp}'
        recovery.mkdir(parents=True, exist_ok=False)
        cfg = settings.DATABASES['default']
        for key, value in {'POSTGRES_DB': cfg['NAME'], 'POSTGRES_USER': cfg['USER'],
                           'POSTGRES_PASSWORD': cfg['PASSWORD'], 'POSTGRES_HOST': cfg['HOST'],
                           'POSTGRES_PORT': cfg['PORT']}.items():
            os.environ[key] = str(value)
        import subprocess
        dump = perform_backup(recovery)
        subprocess.run(['pg_restore', '--list', str(dump)], check=True, capture_output=True)

    with transaction.atomic():
        with connection.cursor() as cursor:
            if not args.apply:
                cursor.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            tables = sorted(connection.introspection.table_names(cursor))
            if args.apply:
                cursor.execute("SET LOCAL lock_timeout = '10s'")
                cursor.execute('LOCK TABLE ' + ', '.join(connection.ops.quote_name(t) for t in tables) +
                               ' IN SHARE ROW EXCLUSIVE MODE')
            schema = {}
            for table in tables:
                constraints = connection.introspection.get_constraints(cursor, table)
                primary = [v['columns'] for v in constraints.values() if v['primary_key']]
                if len(primary) != 1 or len(primary[0]) != 1:
                    raise ValueError(f'Unsupported primary key in {table}')
                schema[table] = {'pk': primary[0][0], 'fks': [
                    (v['columns'][0], *v['foreign_key']) for v in constraints.values()
                    if v['foreign_key'] and len(v['columns']) == 1]}
        term = Semester.objects.get(pk=args.semester_id)
        if term.display_name != args.semester_label:
            raise ValueError('Semester label does not match.')
        q = connection.ops.quote_name
        def matching(table, column, ids):
            with connection.cursor() as cursor:
                cursor.execute(f'SELECT {q(schema[table]["pk"])} FROM {q(table)} WHERE {q(column)} = ANY(%s)', [list(ids)])
                return {row[0] for row in cursor.fetchall()}
        selected = {table: set() for table in tables}
        for table in tables:
            if table in protected_tables:
                continue
            for column, parent, parent_column in schema[table]['fks']:
                if parent == semester_table:
                    selected[table].update(matching(table, column, {term.pk}))
        changed = True
        while changed:
            changed = False
            for table in tables:
                for column, parent, parent_column in schema[table]['fks']:
                    if parent in selected and selected[parent]:
                        if parent_column != schema[parent]['pk']:
                            raise ValueError('Foreign key references a non-primary key.')
                        new = matching(table, column, selected[parent]) - selected[table]
                        if new:
                            if table in protected_tables:
                                raise ValueError(f'Protected records depend on selected data: {table}')
                            selected[table].update(new)
                            changed = True
        for table, ids in selected.items():
            if not ids:
                continue
            for column, parent, parent_column in schema[table]['fks']:
                if parent == semester_table:
                    with connection.cursor() as cursor:
                        cursor.execute(f'SELECT 1 FROM {q(table)} WHERE {q(schema[table]["pk"])} = ANY(%s) '
                                       f'AND {q(column)} IS NOT NULL AND {q(column)} != %s LIMIT 1', [list(ids), term.pk])
                        if cursor.fetchone():
                            raise ValueError(f'Cross-semester records found in {table}.{column}')
        plan = {table: sorted(ids) for table, ids in selected.items() if ids}
        revision = digest(plan)
        report = {'database': args.database, 'semester': term.display_name,
                  'revision': revision, 'counts': {name: len(ids) for name, ids in plan.items()},
                  'total': sum(map(len, plan.values())), 'applied': args.apply}
        if args.apply:
            if revision != args.revision:
                raise ValueError('Deletion plan changed; review a new preview.')
            # Fingerprint every retained row, including account password hashes and other terms.
            def retained():
                result = {}
                with connection.cursor() as cursor:
                    for table in tables:
                        cursor.execute(f'SELECT * FROM {q(table)} WHERE NOT ({q(schema[table]["pk"])} = ANY(%s)) '
                                       f'ORDER BY {q(schema[table]["pk"])}', [list(selected[table])])
                        result[table] = digest(cursor.fetchall())
                return result
            before = retained()
            with connection.cursor() as cursor:
                cursor.execute('SET CONSTRAINTS ALL DEFERRED')
                for table, ids in selected.items():
                    if ids:
                        cursor.execute(f'DELETE FROM {q(table)} WHERE {q(schema[table]["pk"])} = ANY(%s)', [list(ids)])
                cursor.execute('SET CONSTRAINTS ALL IMMEDIATE')
            if retained() != before:
                raise ValueError('Retained rows changed; rolling back.')
            for table, ids in selected.items():
                if ids and matching(table, schema[table]['pk'], ids):
                    raise ValueError('Selected records remain; rolling back.')
            report.update({'retained_rows_unchanged': True, 'recovery': str(recovery),
                           'physical_uploads': 'preserved for recovery; no academic records reference removed uploads'})
            (recovery / 'reset_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
