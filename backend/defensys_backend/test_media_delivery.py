"""Protected delivery uses bounded ranges and media-only, expiring cookies."""
from datetime import timedelta
from pathlib import Path
from types import SimpleNamespace
import tempfile
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import override_settings
from django.core.cache import cache
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken


@override_settings(MEDIA_SESSION_ENABLED=True, MEDIA_X_ACCEL_PREFIX='', DEBUG=True,
                   CACHES={'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}})
class ProtectedMediaDeliveryTests(APITestCase):
    def test_guest_grant_rechecks_invitation_revocation(self):
        token = AccessToken.for_user(self.user)
        token['guest_panelist'] = True
        token['guest_code_id'] = 123
        token['guest_code'] = 'test-guest'
        token['access_version'] = 1
        self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + str(token))
        auth = 'authentication_access_control.guest_authentication.'
        invitation = SimpleNamespace(access_version=1)
        with patch(auth + 'GuestPanelistCode.objects.select_related') as query, \
                patch(auth + 'invitation_is_available', return_value=True) as available, \
                patch(auth + 'invitation_schedule_ids', return_value=[1]):
            query.return_value.filter.return_value.first.return_value = invitation
            self.assertEqual(self.client.post('/api/media/session/').status_code, 200)
            self.client.credentials()
            self.assertEqual(self.content(self.client.get(self.url, HTTP_RANGE='bytes=0-1')), b'01')
            available.return_value = False
            self.assertEqual(self.client.get(self.url, HTTP_RANGE='bytes=0-1').status_code, 401)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.storage = override_settings(STORAGES={
            'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage',
                        'OPTIONS': {'location': self.directory.name}},
            'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'},
        })
        self.storage.enable()
        self.addCleanup(self.storage.disable)
        (Path(self.directory.name) / 'sample video.mp4').write_bytes(b'0123456789')
        self.user = get_user_model().objects.create_user(username='media-reader', role='student')
        self.token = str(AccessToken.for_user(self.user))
        self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + self.token)
        self.permission = patch('defensys_backend.media_views.can_read_media', return_value=True)
        self.check = self.permission.start()
        self.addCleanup(self.permission.stop)
        cache.clear()
        self.url = '/api/media/files/sample%20video.mp4'

    def content(self, response):
        return b''.join(response.streaming_content) if response.streaming else response.content

    def test_get_head_and_ranges(self):
        full = self.client.get(self.url)
        self.assertEqual(self.content(full), b'0123456789')
        head = self.client.head(self.url)
        self.assertEqual(head['Content-Length'], '10')
        self.assertEqual(head.content, b'')
        for value, expected, content_range in [
            ('bytes=2-4', b'234', 'bytes 2-4/10'),
            ('bytes=7-', b'789', 'bytes 7-9/10'),
            ('bytes=-3', b'789', 'bytes 7-9/10'),
        ]:
            response = self.client.get(self.url, HTTP_RANGE=value)
            self.assertEqual(response.status_code, 206)
            self.assertEqual(response['Content-Range'], content_range)
            self.assertEqual(self.content(response), expected)
        for invalid in ('bytes=20-', 'bytes=-0', 'bytes=5-2', 'bytes=0-1,3-4'):
            response = self.client.get(self.url, HTTP_RANGE=invalid)
            self.assertEqual(response.status_code, 416)
            self.assertEqual(response['Content-Range'], 'bytes */10')
        mismatch = self.client.get(self.url, HTTP_RANGE='bytes=1-2', HTTP_IF_RANGE='"old-etag"')
        self.assertEqual(mismatch.status_code, 200)
        self.assertEqual(self.content(mismatch), b'0123456789')

    def test_cookie_only_authenticates_media_and_permissions_are_rechecked(self):
        issued = self.client.post('/api/media/session/')
        self.assertEqual(issued.status_code, 200)
        cookie = next(iter(issued.cookies.values()))
        self.assertTrue(cookie['httponly'])
        self.assertEqual(cookie['path'], '/api/media/')
        self.assertNotIn(self.token, cookie.value)
        self.client.credentials()
        response = self.client.get(self.url, HTTP_RANGE='bytes=0-1')
        self.assertEqual(response.status_code, 206)
        self.assertEqual(self.content(response), b'01')
        self.assertEqual(self.client.get('/api/me/').status_code, 401)
        self.check.return_value = False
        self.assertEqual(self.client.get(self.url).status_code, 404)

    def test_expiry_account_changes_and_revocation(self):
        self.assertEqual(self.client.post('/api/media/session/').status_code, 200)
        self.client.credentials()
        cache.clear()
        self.assertEqual(self.client.get(self.url).status_code, 401)
        self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + self.token)
        self.client.post('/api/media/session/')
        self.user.is_active = False
        self.user.save(update_fields=['is_active'])
        self.client.credentials()
        self.assertEqual(self.client.get(self.url).status_code, 401)

    def test_environment_secret_and_untrusted_origin_fail_closed(self):
        self.assertEqual(self.client.post('/api/media/session/', HTTP_ORIGIN='https://other.invalid').status_code, 403)
        self.client.post('/api/media/session/')
        self.client.credentials()
        with override_settings(SECRET_KEY='another-environment'):
            self.assertEqual(self.client.get(self.url).status_code, 401)

    def test_grant_lifetime_is_bounded_by_access_token(self):
        token = AccessToken.for_user(self.user)
        token.set_exp(lifetime=timedelta(seconds=5))
        self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + str(token))
        response = self.client.post('/api/media/session/')
        self.assertLessEqual(response.data['expires_in'], 5)

    @override_settings(MEDIA_X_ACCEL_PREFIX='/_protected_test_media')
    def test_internal_delivery_does_not_read_file_body_and_still_authorizes(self):
        with patch('django.core.files.storage.filesystem.FileSystemStorage.open', side_effect=AssertionError('body opened')):
            response = self.client.get(self.url)
        self.assertEqual(response['X-Accel-Redirect'], '/_protected_test_media/sample%20video.mp4')
        self.assertEqual(response.content, b'')
        self.assertIn('no-store', response['Cache-Control'])
        self.check.return_value = False
        self.assertEqual(self.client.get(self.url).status_code, 404)

    def test_logout_revokes_media_even_for_an_already_invalid_refresh(self):
        self.client.post('/api/media/session/')
        self.client.post('/api/logout/', {'refresh': 'invalid'}, format='json')
        self.client.credentials()
        self.assertEqual(self.client.get(self.url).status_code, 401)

    def test_cookie_can_revoke_but_cannot_extend_its_own_lifetime(self):
        self.client.post('/api/media/session/')
        self.client.credentials()
        self.assertEqual(self.client.post('/api/media/session/').status_code, 403)
        self.assertEqual(self.client.delete('/api/media/session/').status_code, 204)
        self.assertEqual(self.client.get(self.url).status_code, 401)

    def test_missing_auth_and_traversal_cannot_open_body(self):
        with patch('django.core.files.storage.filesystem.FileSystemStorage.open', side_effect=AssertionError('body opened')):
            self.client.credentials()
            self.assertEqual(self.client.get(self.url, HTTP_RANGE='bytes=0-1').status_code, 401)
            self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + self.token)
            self.assertEqual(self.client.get('/api/media/files/%2e%2e/outside.mp4').status_code, 404)
