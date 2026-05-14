from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase


User = get_user_model()


class DashboardApiTests(APITestCase):
    def test_admin_dashboard_uses_django_user_counts(self):
        admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
        )
        User.objects.create_user(username='student-1', password='pass12345', role='student')
        User.objects.create_user(username='faculty-1', password='pass12345', role='faculty')

        self.client.force_authenticate(user=admin)
        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['total_students'], 1)
        self.assertEqual(response.data['stats']['total_faculty'], 2)
        self.assertEqual(response.data['stats']['total_teams'], 0)
        self.assertEqual(response.data['stats']['upcoming_defenses'], 0)
        self.assertNotEqual(response.data['stats']['total_students'], 150)

    def test_faculty_dashboard_reflects_request_user_roles(self):
        faculty = User.objects.create_user(
            username='faculty-1',
            password='pass12345',
            role='faculty',
            is_panelist=True,
            is_pit_lead=True,
            pit_lead_year='3rd Year',
            is_repo_assistant=True,
        )

        self.client.force_authenticate(user=faculty)
        response = self.client.get('/api/dashboards/faculty/')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['roles']['panelist'])
        self.assertTrue(response.data['roles']['pit_lead'])
        self.assertEqual(response.data['roles']['pit_lead_year'], '3rd Year')
        self.assertTrue(response.data['roles']['repo_assistant'])
        self.assertEqual(response.data['advised_teams'], [])

    def test_student_dashboard_returns_phase_two_empty_team_contract(self):
        student = User.objects.create_user(
            username='student-1',
            password='pass12345',
            role='student',
        )

        self.client.force_authenticate(user=student)
        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.data['team'])
        self.assertEqual(response.data['members'], [])
        self.assertFalse(response.data['peerEvalEnabled'])

    def test_panelist_dashboard_returns_empty_phase_two_collections(self):
        panelist = User.objects.create_user(
            username='panelist-1',
            password='pass12345',
            role='faculty',
            is_panelist=True,
        )

        self.client.force_authenticate(user=panelist)
        response = self.client.get('/api/dashboards/panelist/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['upcoming_defenses'], [])
        self.assertEqual(response.data['assignments'], [])
        self.assertEqual(response.data['results'], [])
