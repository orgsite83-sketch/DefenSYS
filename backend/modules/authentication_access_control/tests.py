from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase


User = get_user_model()


class LoginApiTests(APITestCase):
    @override_settings(DEBUG=True)
    def test_local_cors_preflight_is_allowed_for_flutter_web(self):
        response = self.client.options(
            '/api/login/',
            HTTP_ORIGIN='http://localhost:5173',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
        )

        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            response.headers['Access-Control-Allow-Origin'],
            'http://localhost:5173',
        )

    def test_login_returns_user_profile_with_phase_one_role_flags(self):
        User.objects.create_user(
            username='faculty-1',
            password='pass12345',
            role='faculty',
            first_name='Ada',
            last_name='Lovelace',
            is_panelist=True,
            is_adviser=True,
        )

        response = self.client.post(
            '/api/login/',
            {'username': 'faculty-1', 'password': 'pass12345'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertEqual(response.data['user']['name'], 'Ada Lovelace')
        self.assertTrue(response.data['user']['is_panelist'])
        self.assertTrue(response.data['user']['is_adviser'])
        self.assertTrue(response.data['user']['facultyRoles']['panelist'])
        self.assertTrue(response.data['user']['facultyRoles']['adviser'])


class JwtSessionApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='session-user',
            password='pass12345',
            role='admin',
        )

    def _login(self):
        response = self.client.post(
            '/api/login/',
            {'username': 'session-user', 'password': 'pass12345'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        return response.data

    def test_refresh_with_valid_refresh_returns_new_access(self):
        tokens = self._login()
        response = self.client.post(
            '/api/token/refresh/',
            {'refresh': tokens['refresh']},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn('access', response.data)
        if 'refresh' in response.data:
            self.assertNotEqual(response.data['refresh'], tokens['refresh'])

    def test_refresh_with_invalid_refresh_returns_401(self):
        response = self.client.post(
            '/api/token/refresh/',
            {'refresh': 'not-a-valid-token'},
            format='json',
        )
        self.assertEqual(response.status_code, 401)

    def _decode_refresh_exp(self, refresh_token: str) -> datetime:
        payload = jwt.decode(
            refresh_token,
            settings.SECRET_KEY,
            algorithms=['HS256'],
        )
        return datetime.fromtimestamp(payload['exp'], tz=timezone.utc)

    def test_remember_me_issues_longer_refresh_than_standard_login(self):
        standard = self.client.post(
            '/api/login/',
            {'username': 'session-user', 'password': 'pass12345', 'remember_me': False},
            format='json',
        )
        remembered = self.client.post(
            '/api/login/',
            {'username': 'session-user', 'password': 'pass12345', 'remember_me': True},
            format='json',
        )
        self.assertEqual(standard.status_code, 200)
        self.assertEqual(remembered.status_code, 200)

        standard_exp = self._decode_refresh_exp(standard.data['refresh'])
        remember_exp = self._decode_refresh_exp(remembered.data['refresh'])
        self.assertGreater(remember_exp, standard_exp + timedelta(days=1))

    def test_reuse_old_refresh_after_rotation_returns_401(self):
        tokens = self._login()
        old_refresh = tokens['refresh']
        refresh_response = self.client.post(
            '/api/token/refresh/',
            {'refresh': old_refresh},
            format='json',
        )
        self.assertEqual(refresh_response.status_code, 200)
        reuse_response = self.client.post(
            '/api/token/refresh/',
            {'refresh': old_refresh},
            format='json',
        )
        self.assertEqual(reuse_response.status_code, 401)

    def test_logout_blacklists_refresh(self):
        tokens = self._login()
        logout_response = self.client.post(
            '/api/logout/',
            {'refresh': tokens['refresh']},
            format='json',
        )
        self.assertEqual(logout_response.status_code, 200)
        refresh_response = self.client.post(
            '/api/token/refresh/',
            {'refresh': tokens['refresh']},
            format='json',
        )
        self.assertEqual(refresh_response.status_code, 401)

    def test_me_requires_authentication(self):
        response = self.client.get('/api/me/')
        self.assertEqual(response.status_code, 401)

    def test_me_returns_current_user_with_valid_access(self):
        tokens = self._login()
        response = self.client.get(
            '/api/me/',
            HTTP_AUTHORIZATION=f'Bearer {tokens["access"]}',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['username'], 'session-user')
        self.assertEqual(response.data['role'], 'admin')
