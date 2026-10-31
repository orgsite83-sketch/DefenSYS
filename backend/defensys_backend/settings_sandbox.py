"""Opt-in local database and uploads for starting a workflow from scratch.

Use --settings=defensys_backend.settings_sandbox. Normal settings and .env
remain the source of PostgreSQL connection credentials, never sandbox data.
"""

import hashlib
import os
import re

# Disable external error reporting before loading base settings.
os.environ['SENTRY_DSN'] = ''

from .settings import *  # noqa: E402,F403

_source_database = DATABASES['default']['NAME']
_sandbox_database = os.environ.get('DEFENSYS_SANDBOX_DB', 'defensys_sandbox')
if not re.fullmatch(r'defensys_sandbox(?:_[a-z0-9_]+)?', _sandbox_database):
    raise ImproperlyConfigured('Sandbox database names must start with defensys_sandbox.')
if len(_sandbox_database.encode('utf-8')) > 58 or _sandbox_database == _source_database:
    raise ImproperlyConfigured('Sandbox must use a separate database with a short name.')
if DATABASES['default']['HOST'] not in {'localhost', '127.0.0.1', '::1'}:
    raise ImproperlyConfigured('Sandbox settings require a local PostgreSQL server.')

DATABASES = {'default': {**DATABASES['default'], 'NAME': _sandbox_database,
                         'TEST': {'NAME': f'test_{_sandbox_database}'}}}
MEDIA_ROOT = BASE_DIR.parent / '.sandbox' / _sandbox_database / 'media'
if MEDIA_ROOT.resolve() != MEDIA_ROOT.absolute():
    raise ImproperlyConfigured('Sandbox uploads must not use filesystem links or junctions.')
STORAGES = {
    'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage',
                'OPTIONS': {'location': MEDIA_ROOT, 'base_url': MEDIA_URL}},
    'staticfiles': STORAGES['staticfiles'],
}

# Isolate authentication tokens and notifications from the normal environment.
SECRET_KEY = hashlib.sha256(f'{SECRET_KEY}:sandbox:{_sandbox_database}'.encode()).hexdigest()
SIMPLE_JWT = {**SIMPLE_JWT, 'SIGNING_KEY': SECRET_KEY}
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'
SMS_BACKEND = 'console'
CHANNEL_LAYERS = {'default': {'BACKEND': 'channels.layers.InMemoryChannelLayer'}}
SENTRY_DSN = ''
DEBUG = True
# Match normal development settings so the LAN/hotspot launcher can reach us.
ALLOWED_HOSTS = ['*']
CORS_ALLOW_LAN = True
SECURE_SSL_REDIRECT = False
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False
SECURE_HSTS_SECONDS = 0
SESSION_COOKIE_NAME = 'defensys_sandbox_sessionid'
CSRF_COOKIE_NAME = 'defensys_sandbox_csrftoken'
