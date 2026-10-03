from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from user_management.models import SectionInstructorAssignment
from .serializers import UserSerializer

User = get_user_model()


class WorkspaceNavigationTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.year = SchoolYear.objects.create(label='2026-2027')
        cls.current = Semester.objects.create(school_year=cls.year, label=Semester.FIRST, is_active=True)
        cls.previous = Semester.objects.create(school_year=cls.year, label=Semester.SECOND)
        cls.faculty = User.objects.create_user(username='workspace-panel', role='faculty', is_panelist=True)

    def test_regular_panelist_defaults_to_evaluation_workspace(self):
        self.assertFalse(UserSerializer(self.faculty).data['has_staff_workspace'])

    def test_staff_flags_choose_management_without_changing_panelist_eligibility(self):
        for flag in ('is_pit_lead', 'is_adviser', 'is_documenter', 'is_uploader'):
            with self.subTest(flag=flag):
                user = User.objects.create_user(username=f'workspace-{flag}', role='faculty', **{flag: True})
                data = UserSerializer(user).data
                self.assertTrue(data['has_staff_workspace'])
                self.assertFalse(data['is_panelist'])

    def test_current_instructor_assignment_preserves_staff_home(self):
        assignment = SectionInstructorAssignment.objects.create(
            faculty=self.faculty, semester=self.current, year_level='1st Year', section='A')
        self.assertTrue(UserSerializer(self.faculty).data['has_staff_workspace'])
        assignment.is_active = False
        assignment.save(update_fields=['is_active'])
        self.assertFalse(UserSerializer(self.faculty).data['has_staff_workspace'])

    def test_historical_instructor_assignment_does_not_choose_current_management_home(self):
        SectionInstructorAssignment.objects.create(
            faculty=self.faculty, semester=self.previous, year_level='4th Year', section='A')
        self.assertFalse(UserSerializer(self.faculty).data['has_staff_workspace'])

    def test_student_and_admin_have_distinct_homes(self):
        for role, expected in [('student', False), ('admin', True)]:
            user = User.objects.create_user(username=f'workspace-{role}', role=role)
            self.assertEqual(UserSerializer(user).data['has_staff_workspace'], expected)

    def test_profile_refresh_exposes_current_hint_and_cannot_write_it(self):
        self.client.force_authenticate(self.faculty)
        response = self.client.get('/api/me/')
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['has_staff_workspace'])
        response = self.client.patch('/api/me/', {'has_staff_workspace': True}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['has_staff_workspace'])
