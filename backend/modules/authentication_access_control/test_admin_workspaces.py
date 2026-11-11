from datetime import date
from io import StringIO
import json

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.serializers import UserSerializer
from authentication_access_control.workspace_authentication import bind_workspace
from authentication_access_control.scopes import is_admin_user, manageable_teams_for
from student_teams.models import StudentTeam, TeamMembership
from student_teams.serializers import StudentTeamWriteSerializer
from student_teams.weekly_progress.models import WeeklyProgressReport
from student_teams.formation_access import require_generation_scope
from user_management.models import FacultyRoleAssignment, SectionInstructorAssignment


class AdminWorkspaceTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.admin = User.objects.create_user(username='workspace-admin', role='admin',
            is_adviser=True, is_pit_lead=True, pit_lead_year='2nd Year', is_uploader=True)
        cls.other = User.objects.create_user(username='workspace-other-adviser', role='faculty', is_adviser=True)
        cls.term = Semester.objects.create(school_year=SchoolYear.objects.create(label='2097-2098'),
            label=Semester.FIRST, is_active=True)
        cls.teams = {}
        for key, year, scope, adviser, section in [
            ('own', '4th Year', 'Capstone', cls.admin, 'BSIT-4A'),
            ('other', '4th Year', 'Capstone', cls.other, 'BSIT-4B'),
            ('lead', '2nd Year', 'PIT', None, 'BSIT-2A'),
            ('instructor', '1st Year', 'PIT', None, 'BSIT-1A'),
            ('unassigned', '1st Year', 'PIT', None, 'BSIT-1B'),
        ]:
            student = User.objects.create_user(username=f'workspace-student-{key}', role='student')
            team = StudentTeam.objects.create(name=f'Workspace {key}', leader=student,
                semester=cls.term, year_level=year, level=f'{year} {scope}', section=section, adviser=adviser)
            TeamMembership.objects.create(team=team, student=student, is_leader=True)
            cls.teams[key] = team
        SectionInstructorAssignment.objects.create(faculty=cls.admin, semester=cls.term,
            year_level='1st Year', section='BSIT-1A', is_active=True)
        for key in ('own', 'other'):
            team = cls.teams[key]
            WeeklyProgressReport.objects.create(team=team, student=team.leader,
                week_number=1, report_date=date(2097, 10, 1))

    def authenticate(self, workspace='', **headers):
        token = str(RefreshToken.for_user(self.admin).access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}',
            **({'HTTP_X_DEFENSYS_WORKSPACE': workspace} if workspace else {}), **headers)

    def test_adviser_request_narrows_admin_lists_details_reports_and_files(self):
        self.authenticate('adviser')
        response = self.client.get('/api/teams/', {'workspace': 'adviser'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual({row['id'] for row in response.data['teams']}, {self.teams['own'].pk})
        self.assertEqual(self.client.get(f"/api/teams/{self.teams['other'].pk}/").status_code, 404)
        response = self.client.get('/api/teams/weekly-progress/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual({row['team'] for row in response.data['reports']}, {self.teams['own'].pk})
        report = WeeklyProgressReport.objects.get(team=self.teams['other'])
        self.assertEqual(self.client.get(f'/api/teams/weekly-progress/{report.pk}/file/').status_code, 404)
        self.admin.refresh_from_db()
        self.assertEqual(self.admin.role, 'admin')

    def test_pit_lead_and_instructor_contexts_do_not_inherit_global_admin_scope(self):
        for key, expected, headers in (
            ('pit_lead', 'lead', {}),
            ('instructor', 'instructor', {'HTTP_X_DEFENSYS_YEAR': '1st Year', 'HTTP_X_DEFENSYS_SECTION': 'BSIT-1A'}),
        ):
            self.authenticate(key, **headers)
            response = self.client.get('/api/teams/', {'workspace': key})
            self.assertEqual(response.status_code, 200, response.data)
            self.assertEqual({row['id'] for row in response.data['teams']}, {self.teams[expected].pk})
            response = self.client.patch(f"/api/teams/{self.teams['other'].pk}/?workspace={key}",
                {'name': 'Unauthorized change'}, format='json')
            self.assertEqual(response.status_code, 404, response.data)
        self.authenticate()
        response = self.client.get('/api/teams/', {'workspace': 'operations'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual({row['id'] for row in response.data['teams']}, {t.pk for t in self.teams.values()})

    def test_revoked_unknown_and_unassigned_contexts_fail_closed(self):
        for key in ('unknown', 'panelist', 'documenter'):
            self.authenticate(key)
            self.assertEqual(self.client.get('/api/teams/').status_code, 403)
        self.authenticate('instructor', HTTP_X_DEFENSYS_YEAR='1st Year', HTTP_X_DEFENSYS_SECTION='BSIT-1B')
        self.assertEqual(self.client.get('/api/teams/').status_code, 403)
        self.admin.is_adviser = False
        self.admin.save(update_fields=['is_adviser'])
        self.authenticate('adviser')
        self.assertEqual(self.client.get('/api/teams/').status_code, 403)

    def test_pit_lead_masterlist_and_analytics_keep_the_assigned_year(self):
        self.authenticate('pit_lead')
        response = self.client.get('/api/grading/grades/masterlist/', {
            'workspace': 'pit_lead', 'scope': 'pit', 'coverage': 'semester',
            'year_level': '2nd Year', 'semester_id': self.term.pk})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.client.get('/api/grading/grades/masterlist/', {
            'workspace': 'pit_lead', 'scope': 'pit', 'coverage': 'semester',
            'year_level': '1st Year', 'semester_id': self.term.pk}).status_code, 403)
        self.assertEqual(self.client.get('/api/curriculum-analytics/').status_code, 403)
        self.assertEqual(self.client.get('/api/curriculum-analytics/explorer/',
            {'scope': 'capstone'}).status_code, 403)
    def test_request_metadata_does_not_change_identity_and_generation_requires_assignment(self):
        bind_workspace(self.admin, {'X-Defensys-Workspace': 'instructor',
            'X-Defensys-Year': '1st Year', 'X-Defensys-Section': 'BSIT-1A'})
        self.assertFalse(is_admin_user(self.admin))
        self.assertFalse(manageable_teams_for(self.admin).exists())
        require_generation_scope(self.admin, self.term, '1st Year PIT', 'BSIT-1A')
        from student_teams.roster_workspace import scope
        term, year, section, choices = scope(self.admin,
            {'workspace': 'operations', 'year_level': '1st Year', 'section': 'BSIT-1A'})
        self.assertEqual((term.pk, year, section), (self.term.pk, '1st Year', 'BSIT-1A'))
        self.assertEqual(choices, [{'year_level': '1st Year', 'section': 'BSIT-1A'}])
        from rest_framework.exceptions import PermissionDenied
        with self.assertRaises(PermissionDenied):
            require_generation_scope(self.admin, self.term, '1st Year PIT', 'BSIT-1B')
        self.assertEqual(self.admin.role, 'admin')

    def test_login_payload_advertises_assigned_staff_contexts(self):
        data = UserSerializer(self.admin).data
        self.assertEqual(data['role'], 'admin')
        self.assertTrue(data['staff_workspaces']['adviser'])
        self.assertEqual(data['staff_workspaces']['pit_instructor_sections'],
            [{'year_level': '1st Year', 'section': 'BSIT-1A'}])

    def test_assigning_admin_enables_adviser_once_and_reconciliation_respects_revocation(self):
        self.admin.is_adviser = False
        self.admin.save(update_fields=['is_adviser'])
        out = StringIO()
        call_command('reconcile_adviser_workspaces', user_id=[self.admin.pk], stdout=out)
        self.assertEqual(json.loads(out.getvalue())['accounts'][0]['status'], 'eligible')
        self.admin.refresh_from_db()
        self.assertFalse(self.admin.is_adviser)
        with self.assertRaises(CommandError):
            call_command('reconcile_adviser_workspaces', apply=True, stdout=StringIO())
        call_command('reconcile_adviser_workspaces', apply=True, user_id=[self.admin.pk],
            actor_id=self.admin.pk, stdout=StringIO())
        call_command('reconcile_adviser_workspaces', apply=True, user_id=[self.admin.pk],
            actor_id=self.admin.pk, stdout=StringIO())
        self.admin.refresh_from_db()
        serializer = StudentTeamWriteSerializer()
        serializer._ensure_adviser_role(self.admin, changed_by=self.admin)
        serializer._ensure_adviser_role(self.admin, changed_by=self.admin)
        self.assertEqual(FacultyRoleAssignment.objects.filter(user=self.admin, role_key='adviser').count(), 1)
        self.assertEqual(self.admin.role, 'admin')
        self.admin.is_adviser = False
        self.admin.save(update_fields=['is_adviser'])
        FacultyRoleAssignment.objects.create(user=self.admin, role_key='adviser', action='revoked')
        out = StringIO()
        call_command('reconcile_adviser_workspaces', apply=True, user_id=[self.admin.pk],
            actor_id=self.admin.pk, stdout=out)
        self.assertEqual(json.loads(out.getvalue())['accounts'][0]['status'], 'explicitly_revoked')
        self.admin.refresh_from_db()
        self.assertFalse(self.admin.is_adviser)
