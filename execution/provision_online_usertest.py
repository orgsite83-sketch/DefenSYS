"""Provision the staged online user-test database and config; never start services.

Requires a prior sudo -v. Existing databases, roles and configuration are refused.
Failure retains the new test resources for inspection rather than dropping data.
"""

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import secrets
import subprocess
import sys
from urllib.parse import urlsplit, urlunsplit

DATABASE = 'defensys_usertest'
ROLE = 'defensys_usertest'
HOSTNAME = 'test.defensys.site'

TEST_SETTINGS = '''"""Isolated online user testing. Never use for production."""
from .settings import *

if DATABASES['default']['NAME'] != 'defensys_usertest':
    raise ImproperlyConfigured('User testing requires its dedicated database.')
if DATABASES['default']['USER'] != 'defensys_usertest':
    raise ImproperlyConfigured('User testing requires its dedicated database role.')
if DEBUG:
    raise ImproperlyConfigured('Online user testing requires DEBUG=False.')
SESSION_COOKIE_NAME = 'defensys_usertest_sessionid'
CSRF_COOKIE_NAME = 'defensys_usertest_csrftoken'
SESSION_COOKIE_DOMAIN = None
CSRF_COOKIE_DOMAIN = None
CHANNEL_LAYERS['default']['CONFIG']['prefix'] = 'defensys-usertest'
if SMS_BACKEND != 'console' or EMAIL_BACKEND != 'django.core.mail.backends.console.EmailBackend':
    raise ImproperlyConfigured('Online user testing must use console notifications.')
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--pg-restore', default='pg_restore')
    parser.add_argument('--sql-import', type=Path,
                        help='Prepared PG16 SQL with its checksum/provenance JSON sidecar.')
    parser.add_argument('--resume-empty', action='store_true',
                        help='Reuse the exact saved test config only if its DB is still empty.')
    args = parser.parse_args()
    if os.name != 'posix':
        parser.error('This tool runs on the Linux server.')
    from dotenv import dotenv_values
    import psycopg2
    from psycopg2 import sql

    checkout = args.checkout.expanduser().resolve(strict=True)
    expected = (Path.home() / 'defensys-environments/usertest').resolve()
    if checkout != expected or checkout == Path('/opt/defensys').resolve():
        parser.error('Only ~/defensys-environments/usertest is accepted.')
    production = dotenv_values('/opt/defensys/backend/.env')
    if production.get('POSTGRES_HOST', 'localhost') not in ('localhost', '127.0.0.1', '::1'):
        parser.error('Expected PostgreSQL on the same server.')
    if production.get('POSTGRES_DB', 'defensys_db') == DATABASE:
        parser.error('The selected test DB is already configured as production.')
    port = str(production.get('POSTGRES_PORT') or '5432')
    if not port.isdigit():
        parser.error('Invalid PostgreSQL port.')
    backend = checkout / 'backend'
    env_path = backend / '.env'
    module_path = backend / 'defensys_backend/settings_online_usertest.py'
    report_path = checkout / 'recovery/database_restore_report.json'
    for path in ((report_path,) if args.resume_empty else (env_path, module_path, report_path)):
        if path.exists() or path.is_symlink():
            parser.error(f'Target already exists; stop and inspect before retrying: {path}')
    manifest = json.loads((checkout / 'recovery/restore_manifest.json').read_text())
    dump = checkout / 'recovery/database.dump'
    with dump.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != manifest['database_sha256']:
            parser.error('Staged dump checksum mismatch.')
    prepared = None
    if args.sql_import:
        args.sql_import = args.sql_import.expanduser().resolve(strict=True)
        prepared = json.loads(args.sql_import.with_suffix(args.sql_import.suffix + '.json').read_text())
        with args.sql_import.open('rb') as stream:
            sql_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
        if (prepared.get('source_dump_sha256') != manifest['database_sha256']
                or prepared.get('sql_sha256') != sql_hash
                or prepared.get('table_counts') != manifest['table_counts']
                or prepared.get('database') != DATABASE or prepared.get('role') != ROLE
                or prepared.get('target_major') != 16
                or prepared.get('removed_settings') != ['SET transaction_timeout = 0;']):
            parser.error('Prepared SQL checksum/provenance does not match this staged backup.')
    else:
        listing = subprocess.run([args.pg_restore, '--list', str(dump)],
                                 text=True, capture_output=True)
        if listing.returncode:
            parser.error('pg_restore cannot read this backup; no provisioning performed.\n' + listing.stderr)
        source = re.search(r'Dumped from database version:\s*(\d+)', listing.stdout)
        if source is None:
            parser.error('Could not determine the source PostgreSQL major version.')
    admin = ['sudo', '-n', '-u', 'postgres', 'psql', '-X', '-p', port,
             '-d', 'postgres', '-A', '-t', '-v', 'ON_ERROR_STOP=1']

    def admin_sql(query):
        return subprocess.run(admin, input=query, text=True, capture_output=True, check=True).stdout.strip()

    server_major = int(admin_sql('SHOW server_version_num;')) // 10000
    if prepared is not None and server_major != prepared['target_major']:
        parser.error('Prepared SQL targets a different PostgreSQL major version.')
    if prepared is None and server_major < int(source.group(1)):
        parser.error(f'Backup source is PostgreSQL {source.group(1)}, target is {server_major}. '
                     'Direct cross-version downgrade requires a separate compatibility-reviewed transfer.')
    has_db = bool(admin_sql("SELECT datname FROM pg_database WHERE datname = 'defensys_usertest';"))
    has_role = bool(admin_sql("SELECT rolname FROM pg_roles WHERE rolname = 'defensys_usertest';"))
    saved_config = None
    if args.resume_empty:
        if not has_db or not has_role or not env_path.is_file() or not module_path.is_file():
            parser.error('Resume requires the previously created test DB, role, and config.')
        saved_config = dict(dotenv_values(env_path))
        if (saved_config.get('POSTGRES_DB') != DATABASE or saved_config.get('POSTGRES_USER') != ROLE
                or saved_config.get('POSTGRES_HOST') != '127.0.0.1'
                or saved_config.get('POSTGRES_PORT') != port
                or module_path.read_text() != TEST_SETTINGS):
            parser.error('Saved config does not match the exact isolated test environment.')
        with psycopg2.connect(dbname=DATABASE, user=ROLE,
                              password=saved_config['POSTGRES_PASSWORD'],
                              host='127.0.0.1', port=port, connect_timeout=10) as conn:
            conn.set_session(readonly=True)
            with conn.cursor() as cursor:
                cursor.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace "
                               "WHERE n.nspname NOT IN ('pg_catalog','information_schema') "
                               "AND n.nspname NOT LIKE 'pg_toast%' AND c.relkind IN ('r','p','S','v','m','f')")
                if cursor.fetchone()[0] != 0:
                    parser.error('Resume refused: test DB already contains relations; nothing was overwritten.')
    elif has_db or has_role:
        parser.error('The user-test DB or role already exists; refusing to overwrite or reset credentials.')
    print(json.dumps({'database': DATABASE, 'role': ROLE, 'hostname': HOSTNAME,
                      'checkout': str(checkout), 'apply': args.apply}), flush=True)
    if not args.apply:
        return
    password = secrets.token_urlsafe(40)
    redis = urlsplit(production.get('REDIS_URL') or 'redis://127.0.0.1:6379/0')
    redis_db = '/2' if redis.path.rstrip('/') == '/1' else '/1'
    config = {
        'DJANGO_SETTINGS_MODULE': 'defensys_backend.settings_online_usertest',
        'DJANGO_SECRET_KEY': secrets.token_urlsafe(64),
        'DJANGO_DEBUG': 'False', 'DJANGO_ALLOWED_HOSTS': HOSTNAME + ',localhost,127.0.0.1',
        'DJANGO_CSRF_TRUSTED_ORIGINS': 'https://' + HOSTNAME,
        'DJANGO_SECURE_SSL_REDIRECT': 'True', 'DJANGO_SESSION_COOKIE_SECURE': 'True',
        'DJANGO_CSRF_COOKIE_SECURE': 'True', 'DJANGO_DB_CONN_MAX_AGE': '0',
        'POSTGRES_DB': DATABASE, 'POSTGRES_USER': ROLE, 'POSTGRES_PASSWORD': password,
        'POSTGRES_HOST': '127.0.0.1', 'POSTGRES_PORT': port,
        'REDIS_URL': urlunsplit((redis.scheme, redis.netloc, redis_db, '', '')),
        'DEFENSYS_USE_INMEMORY_CHANNELS': 'False',
        'EMAIL_BACKEND': 'django.core.mail.backends.console.EmailBackend',
        'SMS_BACKEND': 'console', 'SENTRY_DSN': '',
        'FRONTEND_URL': 'https://' + HOSTNAME,
    }
    if saved_config is not None:
        config = saved_config
        password = config['POSTGRES_PASSWORD']
    else:
        os.umask(0o077)
        with env_path.open('x', encoding='utf-8') as output:
            for key, value in config.items():
                output.write(f"{key}='{value}'\n")
        with module_path.open('x', encoding='utf-8') as output:
            output.write(TEST_SETTINGS)
        # Generated password contains only URL-safe characters; it never appears in argv/logs.
        admin_sql(f"CREATE ROLE {ROLE} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD '{password}';\n"
                  f"CREATE DATABASE {DATABASE} OWNER {ROLE} TEMPLATE template0;\n"
                  f"REVOKE CONNECT ON DATABASE {DATABASE} FROM PUBLIC;\n")
    pg_env = os.environ.copy()
    pg_env['PGPASSWORD'] = password
    if prepared is not None:
        subprocess.run(['psql', '-X', '-q', '-h', '127.0.0.1', '-p', port, '-U', ROLE,
                        '-d', DATABASE, '--no-password', '-v', 'ON_ERROR_STOP=1',
                        '--single-transaction', '--file', str(args.sql_import)],
                       env=pg_env, stdout=subprocess.DEVNULL, check=True)
    else:
        subprocess.run([args.pg_restore, '-h', '127.0.0.1', '-p', port, '-U', ROLE, '-d', DATABASE,
                        '--no-password', '--no-owner', '--no-privileges', '--exit-on-error',
                        '--single-transaction', str(dump)], env=pg_env, check=True)
    counts = {}
    with psycopg2.connect(dbname=DATABASE, user=ROLE, password=password,
                          host='127.0.0.1', port=port, connect_timeout=10) as conn:
        conn.set_session(readonly=True)
        with conn.cursor() as cursor:
            cursor.execute('SELECT current_database(), current_user')
            if cursor.fetchone() != (DATABASE, ROLE):
                raise ValueError('Unexpected restore connection identity.')
            for table, expected_count in manifest['table_counts'].items():
                cursor.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(table)))
                counts[table] = cursor.fetchone()[0]
                if counts[table] != expected_count:
                    raise ValueError('Restored table count mismatch: ' + table)
    print('All restored table counts match the backup.', flush=True)
    child_env = {key: value for key, value in os.environ.items()
                 if not key.startswith(('POSTGRES_', 'DJANGO_', 'EMAIL_', 'SMS_', 'JWT_',
                                        'TWILIO_', 'SEMAPHORE_', 'DEFENSYS_'))
                 and key not in ('REDIS_URL', 'SECRET_KEY', 'SENTRY_DSN', 'FRONTEND_URL')}
    child_env.update(config)
    for command in (['migrate', '--noinput'], ['check']):
        subprocess.run([sys.executable, str(backend / 'manage.py'), *command],
                       cwd=backend, env=child_env, check=True)
    # Invalidate old browser/refresh sessions only in the restored test database.
    with psycopg2.connect(dbname=DATABASE, user=ROLE, password=password,
                          host='127.0.0.1', port=port, connect_timeout=10) as conn:
        with conn.cursor() as cursor:
            cursor.execute('DELETE FROM django_session')
            cursor.execute('DELETE FROM token_blacklist_blacklistedtoken')
            cursor.execute('DELETE FROM token_blacklist_outstandingtoken')
    report = {'database': DATABASE, 'role': ROLE, 'hostname': HOSTNAME,
              'table_counts_before_migrations': counts,
              'media_files': manifest['media_files'], 'old_sessions_invalidated': True,
              'services_started': False, 'production_configuration_changed': False}
    with report_path.open('x', encoding='utf-8') as output:
        json.dump(report, output, indent=2)
    print(f'User-test database restored and migrated: {DATABASE}', flush=True)
    print(f'Private test configuration: {env_path}', flush=True)
    print('Existing account passwords preserved. Test email/SMS use console delivery.')
    print('No services started. Production configuration and database were not changed.')


if __name__ == '__main__':
    main()
