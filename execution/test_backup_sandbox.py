"""Safety checks for recovery archives and sandbox settings; no database writes."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

from deployment.backup.backup_db import perform_full_backup, verify_full_backup


ROOT = Path(__file__).resolve().parents[1]


def setUpModule():
    (ROOT / '.tmp').mkdir(exist_ok=True)


class ArchiveSafetyTests(unittest.TestCase):
    def make_archive(self, path, *, content=b'original', listed_content=b'original', extra=False):
        manifest = {'format': 'defensys-full-v1', 'files': [
            {'path': 'database.dump', 'bytes': len(listed_content),
             'sha256': hashlib.sha256(listed_content).hexdigest()},
        ]}
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('database.dump', content)
            archive.writestr('manifest.json', json.dumps(manifest))
            if extra:
                archive.writestr('unrecorded.txt', b'extra')

    def test_valid_archive_is_verified(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            path = Path(directory) / 'backup.zip'
            self.make_archive(path)
            self.assertEqual(verify_full_backup(path)['format'], 'defensys-full-v1')

    def test_changed_bytes_are_rejected_even_with_a_valid_zip_crc(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            path = Path(directory) / 'backup.zip'
            self.make_archive(path, content=b'modified')
            with self.assertRaisesRegex(ValueError, 'verification failed'):
                verify_full_backup(path)

    def test_unrecorded_entries_are_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            path = Path(directory) / 'backup.zip'
            self.make_archive(path, extra=True)
            with self.assertRaisesRegex(ValueError, 'manifest'):
                verify_full_backup(path)

    def test_existing_backup_is_never_overwritten(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            path = Path(directory) / 'existing.zip'
            path.write_bytes(b'keep this recovery copy')
            with self.assertRaises(FileExistsError):
                perform_full_backup(path)
            self.assertEqual(path.read_bytes(), b'keep this recovery copy')


class SandboxSafetyTests(unittest.TestCase):
    def inspect_settings(self, **overrides):
        env = {**os.environ, 'DJANGO_SETTINGS_MODULE': 'defensys_backend.settings_sandbox',
               'POSTGRES_DB': 'defensys_db', 'POSTGRES_HOST': 'localhost',
               'DEFENSYS_SANDBOX_DB': 'defensys_sandbox', 'SENTRY_DSN': '', **overrides}
        code = '''
import json
from django.conf import settings
from defensys_backend import settings as normal
from django.http import HttpResponse
from django.test import RequestFactory
from defensys_backend.cors import LocalCorsMiddleware
lan_access = {}
for host in ('192.168.1.20', '172.20.10.2', '10.0.0.5'):
    origin = f'http://{host}:57583'
    request = RequestFactory().get('/api/health/', HTTP_HOST=f'{host}:8000', HTTP_ORIGIN=origin)
    response = LocalCorsMiddleware(lambda request: HttpResponse('ok'))(request)
    lan_access[host] = request.get_host() == f'{host}:8000' and response.get('Access-Control-Allow-Origin') == origin
print(json.dumps({
    'database': settings.DATABASES['default']['NAME'],
    'test_database': settings.DATABASES['default']['TEST']['NAME'],
    'uploads': str(settings.MEDIA_ROOT),
    'storage': str(settings.STORAGES['default']['OPTIONS']['location']),
    'tokens_isolated': settings.SIMPLE_JWT['SIGNING_KEY'] != normal.SIMPLE_JWT['SIGNING_KEY'],
    'email': settings.EMAIL_BACKEND, 'sms': settings.SMS_BACKEND,
    'normal_database': normal.DATABASES['default']['NAME'],
    'normal_media': str(normal.MEDIA_ROOT),
    'lan_access': lan_access,
}))
'''
        return subprocess.run([sys.executable, '-c', code], cwd=ROOT / 'backend',
                              env=env, text=True, capture_output=True)

    def test_database_uploads_tokens_and_notifications_are_isolated(self):
        result = self.inspect_settings()
        self.assertEqual(result.returncode, 0, result.stderr)
        cfg = json.loads(result.stdout)
        self.assertEqual(cfg['database'], 'defensys_sandbox')
        self.assertEqual(cfg['test_database'], 'test_defensys_sandbox')
        self.assertEqual(cfg['normal_database'], 'defensys_db')
        self.assertNotEqual(cfg['uploads'], cfg['normal_media'])
        self.assertEqual(cfg['uploads'], cfg['storage'])
        self.assertTrue(cfg['tokens_isolated'])
        self.assertEqual(cfg['email'], 'django.core.mail.backends.console.EmailBackend')
        self.assertEqual(cfg['sms'], 'console')

    def test_original_database_cannot_be_targeted(self):
        result = self.inspect_settings(DEFENSYS_SANDBOX_DB='defensys_db')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Sandbox database names', result.stderr)

    def test_lan_launcher_hosts_and_browser_origins_are_accepted(self):
        # Sandbox DEBUG/CORS must work even if the normal .env uses DEBUG=False.
        result = self.inspect_settings(DJANGO_DEBUG='False', POSTGRES_PASSWORD='settings-test-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        access = json.loads(result.stdout)['lan_access']
        self.assertTrue(access)
        self.assertTrue(all(access.values()), access)

    def test_remote_server_is_rejected(self):
        result = self.inspect_settings(POSTGRES_HOST='example.invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('local PostgreSQL server', result.stderr)


if __name__ == '__main__':
    (ROOT / '.tmp').mkdir(exist_ok=True)
    unittest.main()
