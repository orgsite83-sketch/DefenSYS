from datetime import datetime, timedelta, timezone

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
        self.repo_assistant = User.objects.create_user(
            username='audit-repo-assistant',
            password='pass12345',
            role='faculty',
            is_repo_assistant=True,
            repo_assistant_year='3rd Year',
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
            (SystemAuditLog.CATEGORY_REPOSITORY, 'repository.vault_upload'),
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
            action='repository.vault_upload',
            target_type='VaultEntry',
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

    def test_repository_assistant_cannot_review_audit_trail(self):
        self.client.force_authenticate(user=self.repo_assistant)

        response = self.client.get('/api/audit-logs/')

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
