from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam, TeamMembership

from .models import TeamDocument


User = get_user_model()


class TeamDocumentUploadAuthzTests(APITestCase):
    def setUp(self):
        self.leader = User.objects.create_user(
            username='leader-1',
            password='pass12345',
            role='student',
        )
        self.other_student = User.objects.create_user(
            username='other-student',
            password='pass12345',
            role='student',
        )
        school_year = SchoolYear.objects.create(label='2026-2027')
        semester = Semester.objects.create(
            school_year=school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        self.team = StudentTeam.objects.create(
            name='Team Alpha',
            project_title='Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=semester,
            leader=self.leader,
        )
        TeamMembership.objects.create(
            team=self.team,
            student=self.leader,
            is_leader=True,
        )

    def test_non_member_cannot_upload_team_document(self):
        self.client.force_authenticate(user=self.other_student)
        upload = SimpleUploadedFile('report.pdf', b'pdf-content', content_type='application/pdf')
        response = self.client.post(
            '/api/teams/documents/upload/',
            {
                'team_id': self.team.id,
                'document_type': 'other',
                'file': upload,
            },
            format='multipart',
        )
        self.assertEqual(response.status_code, 403)

    def test_team_member_can_upload_team_document(self):
        self.client.force_authenticate(user=self.leader)
        upload = SimpleUploadedFile('report.pdf', b'pdf-content', content_type='application/pdf')
        response = self.client.post(
            '/api/teams/documents/upload/',
            {
                'team_id': self.team.id,
                'document_type': 'other',
                'file': upload,
            },
            format='multipart',
        )
        self.assertEqual(response.status_code, 201)
