"""Regression checks for partial web deployments; no network or database."""
import json
import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_web_release import verify, ROOT


class VerificationTests(unittest.TestCase):
    def setUp(self):
        self.release = 'web-1-0-2-3-test'
        bootstrap = f'entrypointBaseUrl assetBase /releases/web/{self.release}/'.encode()
        self.responses = {
            '/releases/latest.json': (json.dumps({'schema_version': 1, 'web': {
                'release_id': self.release, 'build': 3}}).encode(), 'application/json'),
            '/index.html': (b"searchParams.set('startup', Date.now())", 'text/html'),
            '/flutter_service_worker.js': ((ROOT / 'deployment/web/retire_flutter_service_worker.js').read_bytes(), 'application/javascript'),
            '/flutter_bootstrap.js': (bootstrap, 'application/javascript'),
            f'/releases/web/{self.release}/flutter_bootstrap.js': (bootstrap, 'application/javascript'),
        }

    def fetch(self, origin, path):
        body, content_type = self.responses[path]
        return body, {'Content-Type': content_type, 'Cache-Control':
                      'public, immutable' if path.startswith('/releases/web/') else 'no-store'}

    def test_complete_release(self):
        with patch('verify_web_release.fetch', side_effect=self.fetch):
            self.assertTrue(verify('https://defensys.site', self.release)['verified'])

    def test_html_fallback_is_rejected(self):
        self.responses['/releases/latest.json'] = (b'<html>Flutter app</html>', 'text/html')
        with patch('verify_web_release.fetch', side_effect=self.fetch):
            with self.assertRaisesRegex(ValueError, 'Nginx release include'):
                verify('https://defensys.site')

    def test_old_cache_worker_is_rejected(self):
        self.responses['/flutter_service_worker.js'] = (b"self.addEventListener('fetch', cacheFirst)", 'application/javascript')
        with patch('verify_web_release.fetch', side_effect=self.fetch):
            with self.assertRaisesRegex(ValueError, 'unexpected service worker'):
                verify('https://defensys.site')

    def test_mixed_release_is_rejected(self):
        self.responses['/flutter_bootstrap.js'] = (b'/releases/web/old-release/', 'application/javascript')
        with patch('verify_web_release.fetch', side_effect=self.fetch):
            with self.assertRaisesRegex(ValueError, 'does not match'):
                verify('https://defensys.site')

    def test_cacheable_startup_is_rejected(self):
        with patch('verify_web_release.fetch', return_value=(b'{}', {
                'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=86400'})):
            with self.assertRaisesRegex(ValueError, 'missing Cache-Control'):
                verify('https://defensys.site')


if __name__ == '__main__':
    unittest.main()
