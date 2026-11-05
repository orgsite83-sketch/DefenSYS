"""Create the fresh online client-testing checkout, DB, media, and private config.

Uses migrations only: no backup import, demo data, user accounts, or service starts.
Run as defensys after sudo -v. Existing resources are refused and never deleted.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tarfile
import tempfile
from urllib.parse import urlsplit, urlunsplit

DATABASE = 'defensys_clienttest'
HOST = 'client-test.defensys.site'
SETTINGS = '''"""Fresh isolated online client testing."""
from .settings import *

if DATABASES['default']['NAME'] != 'defensys_clienttest' or DATABASES['default']['USER'] != 'defensys_clienttest':
    raise ImproperlyConfigured('Client testing requires its dedicated database and role.')
if DEBUG:
    raise ImproperlyConfigured('Online client testing requires DEBUG=False.')
SESSION_COOKIE_NAME = 'defensys_clienttest_sessionid'
CSRF_COOKIE_NAME = 'defensys_clienttest_csrftoken'
SESSION_COOKIE_DOMAIN = None
CSRF_COOKIE_DOMAIN = None
CHANNEL_LAYERS['default']['CONFIG']['prefix'] = 'defensys-clienttest'
if SMS_BACKEND != 'console' or EMAIL_BACKEND != 'django.core.mail.backends.console.EmailBackend':
    raise ImproperlyConfigured('Client testing requires console notifications.')
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if os.name != 'posix' or os.getuid() == 0:
        parser.error('Run as the normal defensys SSH user, not root.')
    import pwd
    from dotenv import dotenv_values
    import psycopg2
    from psycopg2 import sql
    if pwd.getpwuid(os.getuid()).pw_name != 'defensys':
        parser.error('Expected the defensys SSH account.')
    source = Path('/opt/defensys')
    base = Path.home() / 'defensys-environments'
    checkout = base / 'clienttest'
    if base.is_symlink() or checkout.exists() or checkout.is_symlink():
        parser.error('Client checkout already exists or environment base is linked; stop and inspect.')
    production = dotenv_values(source / 'backend/.env')
    if production.get('POSTGRES_HOST', 'localhost') not in ('localhost', '127.0.0.1', '::1'):
        parser.error('Expected the existing local PostgreSQL server.')
    if production.get('POSTGRES_DB', 'defensys_db') == DATABASE:
        parser.error('Client-test name is already configured for production.')
    port = str(production.get('POSTGRES_PORT') or '5432')
    if not port.isdigit():
        parser.error('Invalid PostgreSQL port.')
    admin = ['sudo', '-n', '-u', 'postgres', 'psql', '-X', '-p', port,
             '-d', 'postgres', '-A', '-t', '-v', 'ON_ERROR_STOP=1']

    def admin_sql(query):
        return subprocess.run(admin, input=query, text=True, capture_output=True, check=True).stdout.strip()

    if admin_sql("SELECT datname FROM pg_database WHERE datname='defensys_clienttest';"):
        parser.error('Client database already exists; nothing was overwritten.')
    if admin_sql("SELECT rolname FROM pg_roles WHERE rolname='defensys_clienttest';"):
        parser.error('Client role already exists; no password was changed.')
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    print(json.dumps({'checkout': str(checkout), 'database': DATABASE,
                      'source_revision': revision, 'fresh_setup': True, 'apply': args.apply}), flush=True)
    if not args.apply:
        return
    os.umask(0o077)
    base.mkdir(mode=0o700, exist_ok=True)
    base.chmod(0o700)
    # Archive committed source only; no production .env, media, or uncommitted files.
    with tempfile.TemporaryDirectory(prefix='.client-source-', dir=base) as temp:
        archive_path = Path(temp) / 'source.tar'
        subprocess.run(['git', '-C', str(source), 'archive', '--format=tar',
                        '--output', str(archive_path), revision], check=True)
        checkout.mkdir(mode=0o700)
        with tarfile.open(archive_path) as archive:
            archive.extractall(checkout, filter='data')
    backend = checkout / 'backend'
    if (backend / '.env').exists():
        raise ValueError('Committed source unexpectedly contains backend/.env; stopped.')
    media = backend / 'media'
    if media.exists():
        raise ValueError('Committed source unexpectedly contains media; stopped.')
    media.mkdir(mode=0o700)
    recovery = checkout / 'recovery'
    recovery.mkdir(mode=0o700)
    password = secrets.token_urlsafe(40)
    redis = urlsplit(production.get('REDIS_URL') or 'redis://127.0.0.1:6379/0')
    user_config = dotenv_values(base / 'usertest/backend/.env')
    occupied = {redis.path.rstrip('/'), urlsplit(user_config.get('REDIS_URL') or '').path.rstrip('/')}
    redis_db = next('/' + str(n) for n in range(1, 16) if '/' + str(n) not in occupied)
    config = {
        'DJANGO_SETTINGS_MODULE': 'defensys_backend.settings_online_clienttest',
        'DJANGO_SECRET_KEY': secrets.token_urlsafe(64),
        'DJANGO_DEBUG': 'False', 'DJANGO_ALLOWED_HOSTS': HOST + ',localhost,127.0.0.1',
        'DJANGO_CSRF_TRUSTED_ORIGINS': 'https://' + HOST,
        'DJANGO_SECURE_SSL_REDIRECT': 'True', 'DJANGO_SESSION_COOKIE_SECURE': 'True',
        'DJANGO_CSRF_COOKIE_SECURE': 'True', 'DJANGO_DB_CONN_MAX_AGE': '0',
        'POSTGRES_DB': DATABASE, 'POSTGRES_USER': DATABASE, 'POSTGRES_PASSWORD': password,
        'POSTGRES_HOST': '127.0.0.1', 'POSTGRES_PORT': port,
        'REDIS_URL': urlunsplit((redis.scheme, redis.netloc, redis_db, '', '')),
        'DEFENSYS_USE_INMEMORY_CHANNELS': 'False',
        'EMAIL_BACKEND': 'django.core.mail.backends.console.EmailBackend',
        'SMS_BACKEND': 'console', 'SENTRY_DSN': '', 'FRONTEND_URL': 'https://' + HOST,
    }
    with (backend / '.env').open('x', encoding='utf-8') as output:
        for key, value in config.items():
            output.write(f"{key}='{value}'\n")
    with (backend / 'defensys_backend/settings_online_clienttest.py').open('x', encoding='utf-8') as output:
        output.write(SETTINGS)
    admin_sql(f"CREATE ROLE {DATABASE} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD '{password}';\n"
              f"CREATE DATABASE {DATABASE} OWNER {DATABASE} TEMPLATE template0;\n"
              f"REVOKE CONNECT ON DATABASE {DATABASE} FROM PUBLIC;\n")
    child_env = {key: value for key, value in os.environ.items()
                 if not key.startswith(('POSTGRES_', 'DJANGO_', 'EMAIL_', 'SMS_', 'JWT_',
                                        'TWILIO_', 'SEMAPHORE_', 'DEFENSYS_'))
                 and key not in ('REDIS_URL', 'SECRET_KEY', 'SENTRY_DSN', 'FRONTEND_URL')}
    child_env.update(config)
    for command in (['migrate', '--noinput'], ['check']):
        subprocess.run([sys.executable, str(backend / 'manage.py'), *command],
                       cwd=backend, env=child_env, check=True)
    counts = {}
    with psycopg2.connect(dbname=DATABASE, user=DATABASE, password=password,
                          host='127.0.0.1', port=port, connect_timeout=10) as conn:
        conn.set_session(readonly=True)
        with conn.cursor() as cursor:
            cursor.execute('SELECT current_database(), current_user')
            if cursor.fetchone() != (DATABASE, DATABASE):
                raise ValueError('Unexpected client database identity.')
            cursor.execute("SELECT tablename FROM pg_tables WHERE schemaname='public'")
            tables = [row[0] for row in cursor.fetchall()]
            for table in tables:
                cursor.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(table)))
                counts[table] = cursor.fetchone()[0]
    permitted = {'django_migrations', 'django_content_type', 'auth_permission'}
    nonempty = {table: count for table, count in counts.items() if count and table not in permitted}
    if nonempty:
        raise ValueError('Unexpected seeded data; no data was deleted: ' + json.dumps(nonempty))
    if any(media.iterdir()):
        raise ValueError('Unexpected uploads in fresh client media.')
    report = {'database': DATABASE, 'source_revision': revision,
              'fresh_application_tables_verified': True, 'table_counts': counts,
              'media_files': 0, 'administrator_created': False,
              'services_started': False, 'production_changed': False}
    with (recovery / 'database_setup_report.json').open('x', encoding='utf-8') as output:
        json.dump(report, output, indent=2)
    print('Fresh client database migrated and verified. No accounts or academic data were seeded.')
    print('No production/user-test data changed. No services started.')
    print('Create the designated client administrator interactively before using the environment.')


if __name__ == '__main__':
    main()
