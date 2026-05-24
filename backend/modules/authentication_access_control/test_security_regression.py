"""Phase 1 security regression smoke tests (run with app test suite)."""

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
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
