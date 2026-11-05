import re
from pathlib import Path
import unittest
from unittest.mock import MagicMock
import urllib.error

from execution.configure_testing_nginx import challenge_config, https_config, verify_acme_route


class NginxIsolationTests(unittest.TestCase):
    def test_protected_delivery_is_internal_and_only_enabled_for_usertest(self):
        template = (Path(__file__).resolve().parents[1] / 'deployment/nginx/releases.conf').read_text()
        text = https_config(template, '/home/defensys/defensys-environments/usertest/backend/media')
        self.assertEqual(text.count('location ^~ /_protected_usertest_media/'), 1)
        self.assertIn('internal;', text)
        self.assertIn('disable_symlinks on;', text)
        self.assertIn('max_ranges 1;', text)
        self.assertNotIn('/_protected_usertest_media/', text.split('server_name client-test.defensys.site;')[1])
        with self.assertRaises(ValueError):
            https_config(template, '/tmp/root; injected')
    def test_probe_retries_a_reload_404_and_checks_the_exact_response(self):
        opener = MagicMock()
        response = MagicMock()
        response.status = 200
        response.read.return_value = b'ready\n'
        response.__enter__.return_value = response
        opener.open.side_effect = [urllib.error.HTTPError('local', 404, 'Not Found', {}, None), response]
        verify_acme_route('test.defensys.site', b'ready\n', attempts=2, delay=0, opener=opener)
        self.assertEqual(opener.open.call_count, 2)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.get_header('Host'), 'test.defensys.site')

    def test_probe_rejects_a_persistent_missing_or_wrong_file(self):
        opener = MagicMock()
        response = MagicMock()
        response.status = 200
        response.read.return_value = b'wrong virtual host'
        response.__enter__.return_value = response
        opener.open.return_value = response
        with self.assertRaises(RuntimeError):
            verify_acme_route('test.defensys.site', b'ready\n', attempts=2, delay=0, opener=opener)

    def test_challenge_routes_cannot_fall_back_to_a_production_backend(self):
        text = challenge_config()
        self.assertIn('server_name test.defensys.site client-test.defensys.site;', text)
        self.assertIn('location ^~ /.well-known/acme-challenge/', text)
        self.assertNotIn('proxy_pass', text)
        self.assertIn('return 503', text)

    def test_https_preserves_separate_upstreams_release_storage_and_authenticated_media(self):
        template = (Path(__file__).resolve().parents[1] / 'deployment/nginx/releases.conf').read_text()
        text = https_config(template)
        names = [name for group in re.findall(r'server_name\s+([^;]+);', text) for name in group.split()]
        self.assertEqual(set(names), {'test.defensys.site', 'client-test.defensys.site'})
        ports = set(re.findall(r'proxy_pass http://127\.0\.0\.1:(\d+)', text))
        self.assertEqual(ports, {'8100', '8101', '8200', '8201'})
        self.assertNotIn('/var/www/defensys-releases/', text)
        for env, port in [('usertest', 8100), ('clienttest', 8200)]:
            self.assertIn(f'alias /var/www/defensys-{env}-releases/web/', text)
            self.assertIn(f'location /media/ {{\n        proxy_pass http://127.0.0.1:{port};', text)
        self.assertNotRegex(text, r'location /media/\s*\{\s*alias')
        self.assertIn('/etc/letsencrypt/live/defensys-testing/fullchain.pem', text)


if __name__ == '__main__':
    unittest.main()
