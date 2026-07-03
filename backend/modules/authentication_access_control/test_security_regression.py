"""Phase 1 security regression smoke tests (run with app test suite)."""

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from student_teams.models import StudentTeam, TeamMembership

User = get_user_model()


class Phase1SecurityRegressionTests(APITestCase):
    """Consolidated checks for Phase 1a–1c guarantees."""

    def test_anonymous_dashboard_returns_401(self):
        response = self.client.get('/api/dashboards/admin/')
        self.assertEqual(response.status_code, 401)

    def test_unauthenticated_media_file_returns_401(self):
        response = self.client.get('/api/media/files/team_documents/2026/05/report.pdf')
        self.assertEqual(response.status_code, 401)

    def test_authenticated_media_missing_file_returns_404(self):
        user = User.objects.create_user(
            username='media-user',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=user)
        response = self.client.get('/api/media/files/does/not/exist.pdf')
        self.assertIn(response.status_code, (403, 404))

    def test_non_member_document_upload_returns_403(self):
        leader = User.objects.create_user(
            username='sec-leader',
            password='pass12345',
            role='student',
        )
        other = User.objects.create_user(
            username='sec-other',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        team = StudentTeam.objects.create(
            name='Sec Team',
            project_title='Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=semester,
            leader=leader,
        )
        TeamMembership.objects.create(team=team, student=leader, is_leader=True)

        self.client.force_authenticate(user=other)
        upload = SimpleUploadedFile('report.pdf', b'pdf', content_type='application/pdf')
        response = self.client.post(
            '/api/teams/documents/upload/',
            {'team_id': team.id, 'document_type': 'other', 'file': upload},
            format='multipart',
        )
        self.assertEqual(response.status_code, 403)

    def test_unrelated_authenticated_user_cannot_enumerate_schedules(self):
        leader = User.objects.create_user(
            username='scope-leader',
            password='pass12345',
            role='student',
        )
        unrelated = User.objects.create_user(
            username='scope-faculty',
            password='pass12345',
            role='faculty',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        team = StudentTeam.objects.create(
            name='Scope Team',
            project_title='Scoped Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=semester,
            leader=leader,
        )
        TeamMembership.objects.create(team=team, student=leader, is_leader=True)
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=semester,
            team=team,
            event_name='PIT Expo',
            scheduled_date='2026-05-20',
            start_time='09:00',
            slot_duration=60,
            room='Room 201',
            status=DefenseSchedule.STATUS_SCHEDULED,
        )

        self.client.force_authenticate(user=unrelated)
        response = self.client.get('/api/defense/schedules/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['schedules'], [])
        self.assertEqual(response.data['counts']['all'], 0)

    def test_authenticated_media_path_traversal(self):
        user = User.objects.create_user(
            username='media-traversal-user',
            password='pass12345',
            role='student',
        )
        self.client.force_authenticate(user=user)

        # Test path traversal with URL-encoded parent directory references
        response_traversal1 = self.client.get('/api/media/files/..%2Foutside.pdf')
        self.assertEqual(response_traversal1.status_code, 404)

        response_traversal2 = self.client.get('/api/media/files/team_documents%2F..%2F..%2Foutside.pdf')
        self.assertEqual(response_traversal2.status_code, 404)

        # Test absolute path and Windows device paths
        response_abs = self.client.get('/api/media/files/%2Fetc%2Fpasswd')
        self.assertEqual(response_abs.status_code, 404)

        response_win = self.client.get('/api/media/files/C:%5Cwindows%5Csystem32')
        self.assertEqual(response_win.status_code, 404)

    def test_guest_panelist_principal_django_permission_methods(self):
        from modules.authentication_access_control.guest_authentication import GuestPanelistPrincipal
        token = {
            'guest_code_id': 123,
            'guest_code': 'ABC',
            'guest_name': 'Test Guest',
            'defense_schedule_id': 456,
            'team_id': 789,
        }
        principal = GuestPanelistPrincipal(token)
        
        # Check standard properties
        self.assertTrue(principal.is_authenticated)
        self.assertTrue(principal.is_guest_panelist)
        self.assertTrue(principal.is_active)
        self.assertFalse(principal.is_anonymous)
        self.assertFalse(principal.is_superuser)
        self.assertFalse(principal.is_staff)
        self.assertEqual(principal.username, 'guest:ABC')
        self.assertEqual(principal.get_username(), 'guest:ABC')

        # Check Django permission backend methods
        self.assertFalse(principal.has_perm('some_perm'))
        self.assertFalse(principal.has_perm('some_perm', obj=object()))
        self.assertFalse(principal.has_perms(['perm1', 'perm2']))
        self.assertTrue(principal.has_perms([]))
        self.assertFalse(principal.has_module_perms('some_app'))
        self.assertEqual(principal.get_all_permissions(), set())
        self.assertEqual(principal.get_user_permissions(), set())
        self.assertEqual(principal.get_group_permissions(), set())
