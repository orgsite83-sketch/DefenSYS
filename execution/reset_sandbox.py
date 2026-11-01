"""Preview or flush only a local sandbox, preserving administrator sign-ins.

Uses Django's flush/loaddata commands, backs up the sandbox before applying,
and never opens a writable connection to the normal DefenSYS database.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
SANDBOX_SETTINGS = 'defensys_backend.settings_sandbox'


def validate_target(expected, actual, normal, host):
    if not re.fullmatch(r'defensys_sandbox(?:_[a-z0-9_]+)?', expected):
        raise ValueError('Only a named defensys_sandbox database may be reset.')
    if actual != expected or actual == normal:
        raise ValueError('Connected database is not the separate requested sandbox.')
    if host not in {'localhost', '127.0.0.1', '::1'}:
        raise ValueError('Sandbox reset requires local PostgreSQL.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default=os.environ.get('DEFENSYS_SANDBOX_DB', 'defensys_sandbox'))
    parser.add_argument('--apply', action='store_true', help='Back up and clear the verified sandbox.')
    args = parser.parse_args()
    os.environ['DJANGO_SETTINGS_MODULE'] = SANDBOX_SETTINGS
    os.environ['DEFENSYS_SANDBOX_DB'] = args.database
    sys.path[:0] = [str(ROOT / 'backend'), str(ROOT)]

    import django
    django.setup()
    from django.apps import apps
    from django.conf import settings
    from django.contrib.auth import get_user_model
    from django.contrib.auth.models import Group
    from django.core import serializers
    from django.core.management import call_command
    from django.db import connection, transaction
    from django.db.models import Q
    from defensys_backend import settings as normal_settings
    import psycopg2
    from psycopg2 import sql

    cfg = settings.DATABASES['default']
    normal = normal_settings.DATABASES['default']
    with connection.cursor() as cursor:
        cursor.execute('SELECT current_database()')
        actual = cursor.fetchone()[0]
    validate_target(args.database, actual, normal['NAME'], cfg['HOST'])

    def normal_counts():
        # Aggregate reads only; do not load or print real account data.
        with psycopg2.connect(dbname=normal['NAME'], user=normal['USER'], password=normal['PASSWORD'],
                              host=normal['HOST'], port=normal['PORT'], connect_timeout=10) as conn:
            conn.set_session(readonly=True)
            with conn.cursor() as cursor:
                cursor.execute("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")
                tables = [row[0] for row in cursor.fetchall()]
                result = {}
                for table in tables:
                    cursor.execute(sql.SQL('SELECT count(*) FROM public.{}').format(sql.Identifier(table)))
                    result[table] = cursor.fetchone()[0]
                return result

    User = get_user_model()
    administrators = list(User.objects.filter(Q(role='admin') | Q(is_superuser=True)).order_by('pk'))
    if not administrators:
        raise RuntimeError('No existing sandbox administrator can be retained; no reset performed.')
    counts = {model._meta.label: model.objects.count() for model in apps.get_models()
              if model._meta.managed and not model._meta.proxy}
    report = {'sandbox': actual, 'normal_database': normal['NAME'], 'apply': args.apply,
              'administrators_retained': len(administrators), 'rows_before': sum(counts.values())}
    if not args.apply:
        print(json.dumps(report, indent=2))
        return 0

    before_normal = normal_counts()
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    backup_dir = ROOT / '.backups' / f'{actual}_before_flush_{stamp}'
    backup_dir.mkdir(parents=True, exist_ok=False)
    # Reuse the deterministic existing backup tool with the verified connection.
    from deployment.backup.backup_db import perform_backup
    for key, value in {'POSTGRES_DB': actual, 'POSTGRES_HOST': cfg['HOST'],
                       'POSTGRES_PORT': cfg['PORT'], 'POSTGRES_USER': cfg['USER'],
                       'POSTGRES_PASSWORD': cfg['PASSWORD']}.items():
        os.environ[key] = str(value)
    backup = perform_backup(backup_dir)
    subprocess.run(['pg_restore', '--list', str(backup)], check=True, capture_output=True)

    groups = list(Group.objects.filter(pk__in=[pk for admin in administrators
        for pk in admin.groups.values_list('pk', flat=True)]).order_by('pk'))
    fixture = serializers.serialize('json', [*groups, *administrators], use_natural_foreign_keys=True)
    credentials = {admin.pk: admin.password for admin in administrators}
    tmp = ROOT / '.tmp'
    tmp.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', suffix='.json',
                                     prefix='sandbox-admin-restore-', dir=tmp, delete=False) as file:
        file.write(fixture)
        fixture_path = Path(file.name)
    try:
        with transaction.atomic():
            with connection.cursor() as cursor:
                cursor.execute('SELECT current_database()')
                validate_target(args.database, cursor.fetchone()[0], normal['NAME'], cfg['HOST'])
            call_command('flush', database='default', interactive=False, verbosity=0)
            call_command('loaddata', str(fixture_path), database='default', verbosity=0)
            restored = dict(User.objects.values_list('pk', 'password'))
            if restored != credentials:
                raise RuntimeError('Administrator identities or password hashes changed; reset rolled back.')
            allowed = {User._meta.label, 'auth.Group', 'auth.Permission', 'contenttypes.ContentType'}
            remaining = {model._meta.label: model.objects.count() for model in apps.get_models()
                         if model._meta.managed and not model._meta.proxy and model._meta.label not in allowed}
            if any(remaining.values()):
                raise RuntimeError(f'Unexpected application rows remain; reset rolled back: {remaining}')
    finally:
        fixture_path.unlink(missing_ok=True)

    after_normal = normal_counts()
    report.update(backup=str(backup), application_rows_after=sum(remaining.values()),
                  normal_table_counts_unchanged=before_normal == after_normal,
                  normal_counts_sha256=hashlib.sha256(json.dumps(before_normal, sort_keys=True).encode()).hexdigest())
    output = backup_dir / 'reset-report.json'
    output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    if before_normal != after_normal:
        raise RuntimeError('The normal database counts changed concurrently; inspect the reset report.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
