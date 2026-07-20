from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APIRequestFactory
from rest_framework.test import APITestCase

from .audit import audit_scope_metadata, log_high_impact_action
from .models import SystemAuditLog


User = get_user_model()


class UserManagerTests(APITestCase):
    def test_create_superuser_defaults_to_admin_role(self):
        user = User.objects.create_superuser(
            username='admin',
            password='pass12345',
        )

        self.assertEqual(user.role, 'admin')
        self.assertTrue(user.is_staff)
        self.assertTrue(user.is_superuser)


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

    @override_settings(
        DEBUG=False,
        CORS_ALLOWED_ORIGINS=['https://dev.defensys.site'],
    )
    def test_configured_cors_origin_is_allowed_when_debug_false(self):
        response = self.client.options(
            '/api/login/',
            HTTP_ORIGIN='https://dev.defensys.site',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
        )

        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            response.headers['Access-Control-Allow-Origin'],
            'https://dev.defensys.site',
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

    def test_logout_endpoint_is_throttled(self):
        from rest_framework.settings import api_settings
        original_rate = api_settings.DEFAULT_THROTTLE_RATES.get('logout')
        api_settings.DEFAULT_THROTTLE_RATES['logout'] = '1/min'
        try:
            response1 = self.client.post(
                '/api/logout/',
                {'refresh': 'not-a-valid-token'},
                format='json',
            )
            # Invalid token yields 401 unauthorized
            self.assertEqual(response1.status_code, 401)

            response2 = self.client.post(
                '/api/logout/',
                {'refresh': 'not-a-valid-token'},
                format='json',
            )
            # Throttled request yields 429 Too Many Requests
            self.assertEqual(response2.status_code, 429)
        finally:
            api_settings.DEFAULT_THROTTLE_RATES['logout'] = original_rate

    def test_me_patch_avatar_valid(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        tokens = self._login()
        small_gif = (
            b'\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x00\x00\x00\x21\xf9\x04'
            b'\x01\x0a\x00\x01\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02'
            b'\x02\x4c\x01\x00\x3b'
        )
        avatar_file = SimpleUploadedFile('avatar.png', small_gif, content_type='image/png')
        response = self.client.patch(
            '/api/me/',
            {'avatar': avatar_file},
            format='multipart',
            HTTP_AUTHORIZATION=f'Bearer {tokens["access"]}',
        )
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.avatar.name.endswith('.png'))

    def test_me_patch_avatar_invalid_extension(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        tokens = self._login()
        avatar_file = SimpleUploadedFile('avatar.txt', b'dummy_png_data', content_type='image/png')
        response = self.client.patch(
            '/api/me/',
            {'avatar': avatar_file},
            format='multipart',
            HTTP_AUTHORIZATION=f'Bearer {tokens["access"]}',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Unsupported file format. Please upload JPEG, PNG, or WEBP.')

    def test_me_patch_avatar_invalid_content_type(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        tokens = self._login()
        avatar_file = SimpleUploadedFile('avatar.png', b'dummy_png_data', content_type='text/plain')
        response = self.client.patch(
            '/api/me/',
            {'avatar': avatar_file},
            format='multipart',
            HTTP_AUTHORIZATION=f'Bearer {tokens["access"]}',
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['detail'], 'Unsupported file format. Please upload JPEG, PNG, or WEBP.')


class SystemAuditLogApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='audit-admin',
            password='pass12345',
            role='admin',
        )
        self.pit_lead = User.objects.create_user(
            username='audit-pit-lead',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        self.documenter = User.objects.create_user(
            username='audit-documenter',
            password='pass12345',
            role='faculty',
            is_documenter=True,
        )
        self.client.force_authenticate(user=self.admin)

    def test_log_high_impact_action_captures_request_metadata(self):
        request = APIRequestFactory().post(
            '/api/audit-logs/',
            {},
            HTTP_USER_AGENT='Audit Test Browser',
            REMOTE_ADDR='203.0.113.10',
        )
        request.user = self.admin

        log_high_impact_action(
            category=SystemAuditLog.CATEGORY_GRADE_CENTER,
            action='grade.publish',
            target=self.admin,
            target_type='TeamGrade',
            target_id=128,
            old_values={'status': 'pending'},
            new_values={'status': 'published'},
            reason='Approved after review.',
            request=request,
        )

        log = SystemAuditLog.objects.get()
        self.assertEqual(log.actor, self.admin)
        self.assertEqual(log.category, SystemAuditLog.CATEGORY_GRADE_CENTER)
        self.assertEqual(log.action, 'grade.publish')
        self.assertEqual(log.target_type, 'TeamGrade')
        self.assertEqual(log.target_id, '128')
        self.assertEqual(log.ip_address, '203.0.113.10')
        self.assertEqual(log.user_agent, 'Audit Test Browser')
        self.assertEqual(log.review_status, SystemAuditLog.REVIEW_CAPTURED)

    def test_audit_log_api_filters_by_category(self):
        categories = [
            (SystemAuditLog.CATEGORY_ACADEMIC_PERIOD, 'semester.active_switch'),
            (SystemAuditLog.CATEGORY_GRADE_CENTER, 'grade.manual_edit'),
            (SystemAuditLog.CATEGORY_SCHEDULING, 'schedule.status_change'),
            (SystemAuditLog.CATEGORY_STUDENT_TEAMS, 'team.adviser_change'),
            (SystemAuditLog.CATEGORY_REPOSITORY, 'repository.archive_upload'),
            (SystemAuditLog.CATEGORY_GUEST_ACCESS, 'guest_code.exchange'),
        ]
        for category, action in categories:
            SystemAuditLog.objects.create(
                actor=self.admin,
                category=category,
                action=action,
                target_type='AuditTarget',
                target_id=action,
                old_values={'before': 'old'},
                new_values={'after': 'new'},
            )

        response = self.client.get(
            '/api/audit-logs/',
            {'category': SystemAuditLog.CATEGORY_GRADE_CENTER},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['counts']['filtered'], 1)
        self.assertEqual(len(response.data['audit_logs']), 1)
        self.assertEqual(
            response.data['audit_logs'][0]['category'],
            SystemAuditLog.CATEGORY_GRADE_CENTER,
        )
        self.assertEqual(response.data['audit_logs'][0]['action'], 'grade.manual_edit')

    def test_admin_can_review_global_audit_trail_records(self):
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.pit_upload',
            target_type='VaultEntry',
            target_id='1',
            new_values={'entry_type': 'pit', 'year_level': '3rd Year'},
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.capstone_upload',
            target_type='VaultEntry',
            target_id='2',
            new_values={'entry_type': 'capstone', 'year_level': '3rd Year'},
        )

        response = self.client.get('/api/audit-logs/')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['counts']['filtered'], 2)

    def test_audit_trail_response_stays_separate_from_repository_upload_payload(self):
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.archive_upload',
            target_type='ArchiveEntry',
            target_id='1',
            new_values={'entry_type': 'pit', 'year_level': '3rd Year'},
        )

        response = self.client.get('/api/audit-logs/')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('audit_logs', response.data)
        self.assertNotIn('upload_window', response.data)
        self.assertNotIn('capstone_upload_window', response.data)
        self.assertNotIn('entries', response.data)

    def test_pit_lead_reviews_only_assigned_year_pit_audit_records(self):
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.assigned_pit_upload',
            target_type='VaultEntry',
            target_id='1',
            new_values={'entry_type': 'pit', 'year_level': '3rd Year'},
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.other_pit_upload',
            target_type='VaultEntry',
            target_id='2',
            new_values={'entry_type': 'pit', 'year_level': '2nd Year'},
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.capstone_upload',
            target_type='VaultEntry',
            target_id='3',
            new_values={'entry_type': 'capstone', 'year_level': '3rd Year'},
        )
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/audit-logs/')
        actions = [log['action'] for log in response.data['audit_logs']]

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['counts']['filtered'], 1)
        self.assertEqual(actions, ['repository.assigned_pit_upload'])

    def test_audit_scope_metadata_marks_pit_year_scope(self):
        class Team:
            pk = 7
            name = 'PIT Team'
            year_level = '3rd Year'

        metadata = audit_scope_metadata(scope='pit', team=Team())

        self.assertEqual(metadata['scope'], 'pit')
        self.assertEqual(metadata['track'], 'pit')
        self.assertEqual(metadata['entry_type'], 'pit')
        self.assertEqual(metadata['year_level'], '3rd Year')
        self.assertEqual(metadata['team_year_level'], '3rd Year')
        self.assertEqual(metadata['pit_year_level'], '3rd Year')

    def test_pit_lead_reviews_standardized_pit_scope_metadata(self):
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_SCHEDULING,
            action='schedule.status_change',
            target_type='DefenseSchedule',
            target_id='1',
            new_values={
                **audit_scope_metadata(scope='pit', year_level='3rd Year'),
                'status': 'done',
            },
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_SCHEDULING,
            action='schedule.other_year',
            target_type='DefenseSchedule',
            target_id='2',
            new_values={
                **audit_scope_metadata(scope='pit', year_level='2nd Year'),
                'status': 'done',
            },
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_SCHEDULING,
            action='schedule.capstone',
            target_type='DefenseSchedule',
            target_id='3',
            new_values={
                **audit_scope_metadata(scope='capstone', year_level='3rd Year'),
                'status': 'done',
            },
        )
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/audit-logs/')
        actions = [log['action'] for log in response.data['audit_logs']]

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(actions, ['schedule.status_change'])

    def test_documenter_cannot_review_audit_trail(self):
        self.client.force_authenticate(user=self.documenter)

        response = self.client.get('/api/audit-logs/')

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_audit_log_api_filters_by_track_and_year_level(self):
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.pit_upload_3rd',
            target_type='VaultEntry',
            target_id='1',
            new_values={'entry_type': 'pit', 'year_level': '3rd Year'},
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.pit_upload_2nd',
            target_type='VaultEntry',
            target_id='2',
            new_values={'entry_type': 'pit', 'year_level': '2nd Year'},
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.capstone_upload',
            target_type='VaultEntry',
            target_id='3',
            new_values={'entry_type': 'capstone', 'year_level': '3rd Year'},
        )

        # Filter by track='pit'
        response = self.client.get('/api/audit-logs/', {'track': 'pit'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        actions = [log['action'] for log in response.data['audit_logs']]
        self.assertIn('repository.pit_upload_3rd', actions)
        self.assertIn('repository.pit_upload_2nd', actions)
        self.assertNotIn('repository.capstone_upload', actions)

        # Filter by track='capstone'
        response = self.client.get('/api/audit-logs/', {'track': 'capstone'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        actions = [log['action'] for log in response.data['audit_logs']]
        self.assertNotIn('repository.pit_upload_3rd', actions)
        self.assertNotIn('repository.pit_upload_2nd', actions)
        self.assertIn('repository.capstone_upload', actions)

        # Filter by year_level='3rd Year'
        response = self.client.get('/api/audit-logs/', {'year_level': '3rd Year'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        actions = [log['action'] for log in response.data['audit_logs']]
        self.assertIn('repository.pit_upload_3rd', actions)
        self.assertNotIn('repository.pit_upload_2nd', actions)
        self.assertIn('repository.capstone_upload', actions)

        # Filter by track='pit' and year_level='3rd Year'
        response = self.client.get('/api/audit-logs/', {'track': 'pit', 'year_level': '3rd Year'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        actions = [log['action'] for log in response.data['audit_logs']]
        self.assertIn('repository.pit_upload_3rd', actions)
        self.assertNotIn('repository.pit_upload_2nd', actions)
        self.assertNotIn('repository.capstone_upload', actions)

    def test_user_history_api(self):
        SystemAuditLog.objects.create(
            actor=self.documenter,
            category=SystemAuditLog.CATEGORY_REPOSITORY,
            action='repository.upload',
            target_type='VaultEntry',
            target_id='1',
        )
        SystemAuditLog.objects.create(
            actor=self.admin,
            category=SystemAuditLog.CATEGORY_ACADEMIC_PERIOD,
            action='academic.create',
            target_type='AcademicPeriod',
            target_id='2',
        )

        # Logged in as documenter
        self.client.force_authenticate(user=self.documenter)
        response = self.client.get('/api/me/history/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        logs = response.data['history']
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0]['action'], 'repository.upload')

        # Logged in as admin
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/me/history/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        logs = response.data['history']
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0]['action'], 'academic.create')

        # Unauthenticated user
        self.client.logout()
        response = self.client.get('/api/me/history/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class PasswordManagementTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='student-test',
            password='oldpassword123',
            email='student@example.com',
            role='student',
        )
        self.admin = User.objects.create_user(
            username='admin-test',
            password='adminpassword123',
            email='admin@example.com',
            role='admin',
            is_staff=True,
            is_superuser=True,
        )

    def test_change_password_success(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            '/api/change-password/',
            {
                'current_password': 'oldpassword123',
                'new_password': 'newpassword123',
                'confirm_password': 'newpassword123',
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        # Check that the password was actually updated
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('newpassword123'))

    def test_change_password_wrong_current(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            '/api/change-password/',
            {
                'current_password': 'wrongpassword',
                'new_password': 'newpassword123',
                'confirm_password': 'newpassword123',
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_change_password_mismatch(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            '/api/change-password/',
            {
                'current_password': 'oldpassword123',
                'new_password': 'newpassword123',
                'confirm_password': 'differentpassword',
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_request_password_reset_success(self):
        response = self.client.post(
            '/api/password-reset/',
            {'identifier': 'student-test'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('link has been sent', response.data['detail'])

    def test_request_password_reset_email_failure(self):
        with patch('authentication_access_control.password_reset.send_password_reset_email', return_value=False):
            response = self.client.post(
                '/api/password-reset/',
                {'identifier': 'student-test'},
                format='json',
            )
            self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
            self.assertIn('Failed to send password reset email', response.data['detail'])

    def test_request_password_reset_nonexistent_user(self):
        # Should still return 200 to prevent user enumeration
        response = self.client.post(
            '/api/password-reset/',
            {'identifier': 'nonexistent'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_admin_reset_password_success(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.post(
            f'/api/users/{self.user.pk}/reset-password/',
            {'send_email': False},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        # Admin reset sets the password to their username (student-test)
        self.assertTrue(self.user.check_password('student-test'))

    def test_admin_reset_password_unauthorized(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            f'/api/users/{self.admin.pk}/reset-password/',
            {'send_email': False},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_api_confirm_password_reset_success(self):
        from django.utils.http import urlsafe_base64_encode
        from django.utils.encoding import force_bytes
        from django.contrib.auth.tokens import default_token_generator

        uidb64 = urlsafe_base64_encode(force_bytes(self.user.pk))
        token = default_token_generator.make_token(self.user)

        response = self.client.post(
            '/api/password-reset/confirm/',
            {
                'uidb64': uidb64,
                'token': token,
                'new_password': 'newpassword123',
                'confirm_password': 'newpassword123',
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('newpassword123'))

    def test_api_confirm_password_reset_mismatch(self):
        from django.utils.http import urlsafe_base64_encode
        from django.utils.encoding import force_bytes
        from django.contrib.auth.tokens import default_token_generator

        uidb64 = urlsafe_base64_encode(force_bytes(self.user.pk))
        token = default_token_generator.make_token(self.user)

        response = self.client.post(
            '/api/password-reset/confirm/',
            {
                'uidb64': uidb64,
                'token': token,
                'new_password': 'newpassword123',
                'confirm_password': 'mismatchpassword',
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_api_confirm_password_reset_invalid_token(self):
        from django.utils.http import urlsafe_base64_encode
        from django.utils.encoding import force_bytes

        uidb64 = urlsafe_base64_encode(force_bytes(self.user.pk))

        response = self.client.post(
            '/api/password-reset/confirm/',
            {
                'uidb64': uidb64,
                'token': 'invalid-token',
                'new_password': 'newpassword123',
                'confirm_password': 'newpassword123',
            },
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class HealthCheckApiTests(APITestCase):
    def test_health_check_endpoint_success(self):
        response = self.client.get('/api/health/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'healthy')
        self.assertEqual(response.data['checks']['database'], 'healthy')

    def test_health_check_endpoint_database_failure(self):
        from unittest.mock import patch
        from django.db import OperationalError

        with patch('defensys_backend.views.connection.cursor') as mock_cursor:
            mock_cursor.side_effect = OperationalError("Database connection failed")
            response = self.client.get('/api/health/')

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(response.data['status'], 'unhealthy')
        self.assertIn('unhealthy', response.data['checks']['database'])


class SystemAuditLogPaginationTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_superuser(
            username='audit-admin',
            email='auditadmin@example.com',
            password='Password123!',
            role='admin',
        )
        self.client.force_authenticate(user=self.admin)

        # Create 15 system audit log entries for testing pagination
        for i in range(15):
            SystemAuditLog.objects.create(
                category=SystemAuditLog.CATEGORY_REPOSITORY,
                action=f'TEST_ACTION_{i}',
                target_type='User',
                target_id=str(i),
                reason='Pagination test',
                actor=self.admin,
                review_status=SystemAuditLog.REVIEW_CAPTURED,
            )

    def test_audit_log_pagination_default_page_size(self):
        response = self.client.get('/api/audit-logs/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('count', response.data)
        self.assertIn('total_pages', response.data)
        self.assertIn('current_page', response.data)
        self.assertIn('audit_logs', response.data)
        self.assertEqual(response.data['count'], 15)
        self.assertEqual(response.data['current_page'], 1)
        self.assertEqual(len(response.data['audit_logs']), 15)

    def test_audit_log_pagination_custom_page_size(self):
        response = self.client.get('/api/audit-logs/?page_size=5')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 15)
        self.assertEqual(response.data['total_pages'], 3)
        self.assertEqual(response.data['current_page'], 1)
        self.assertEqual(len(response.data['audit_logs']), 5)
        self.assertIsNotNone(response.data['next'])

        # Fetch page 2
        response_p2 = self.client.get('/api/audit-logs/?page=2&page_size=5')
        self.assertEqual(response_p2.status_code, status.HTTP_200_OK)
        self.assertEqual(response_p2.data['current_page'], 2)
        self.assertEqual(len(response_p2.data['audit_logs']), 5)

    def test_audit_log_pagination_legacy_limit_param(self):
        response = self.client.get('/api/audit-logs/?limit=5')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 15)
        self.assertEqual(response.data['total_pages'], 3)
        self.assertEqual(len(response.data['audit_logs']), 5)




