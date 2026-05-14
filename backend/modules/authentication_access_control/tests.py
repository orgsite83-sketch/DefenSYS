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
        self.assertEqual(response.data['user']['name'], 'Ada Lovelace')
        self.assertTrue(response.data['user']['is_panelist'])
        self.assertTrue(response.data['user']['is_adviser'])
        self.assertTrue(response.data['user']['facultyRoles']['panelist'])
        self.assertTrue(response.data['user']['facultyRoles']['adviser'])
