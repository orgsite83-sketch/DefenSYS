from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from capstone_deliverables.models import DeliverableSubmission
from digital_vault.models import VaultEntry
from student_teams.models import StudentTeam, TeamMembership


User = get_user_model()


class CurriculumAnalyticsApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.faculty = User.objects.create_user(
            username='faculty-user',
            password='pass12345',
            role='faculty',
        )
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.previous_year = SchoolYear.objects.create(label='2025-2026')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        self.previous_semester = Semester.objects.create(
            school_year=self.previous_year,
            label=Semester.FIRST,
        )
        self.team = StudentTeam.objects.create(
            name='Team CloudSync',
            project_title='Cloud File Storage System',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.faculty,
        )
        self.old_team = StudentTeam.objects.create(
            name='Team MobileAid',
            project_title='Flutter Attendance Mobile App',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.previous_semester,
            leader=self.student,
            adviser=self.faculty,
        )
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='Final Defense',
            deliverable_id='D17',
            label='D17 - 7-Page Executive Journal',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_CloudSync_Executive_Journal.pdf',
            uploaded_by=self.faculty,
        )
        DeliverableSubmission.objects.create(
            team=self.old_team,
            stage_label='Concept Proposal',
            deliverable_id='D4.1',
            label='D4.1 - Approved Concept Paper',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_MobileAid_Flutter_Attendance.pdf',
            uploaded_by=self.faculty,
        )
        VaultEntry.objects.create(
            file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            team_name='Team VaultSync',
            academic_year='2026-2027',
            status=VaultEntry.STATUS_APPROVED,
            uploaded_by=self.faculty,
        )

    def test_admin_gets_curriculum_distribution_and_suggestions(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/curriculum-analytics/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['entries_count'], 3)
        self.assertIn('2026-2027', response.data['academic_years'])
        self.assertTrue(response.data['distribution'])
        self.assertTrue(response.data['suggestions'])
        self.assertEqual(response.data['trend_cards']['total_entries'], 3)

    def test_non_admin_cannot_read_curriculum_analytics(self):
        self.client.force_authenticate(user=self.faculty)

        response = self.client.get('/api/curriculum-analytics/')

        self.assertEqual(response.status_code, 403)

    def test_classifier_returns_domain_and_similar_projects(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.post(
            '/api/curriculum-analytics/classify/',
            {
                'text': 'A Flutter mobile app with cloud file storage and responsive UI.',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn(response.data['domain'], ['Mobile Development', 'Web Development'])
        self.assertGreater(response.data['confidence'], 0)
        self.assertTrue(response.data['pipeline'])
        self.assertTrue(response.data['similar_projects'])

    def test_proposal_endpoint_generates_recommendations(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.post('/api/curriculum-analytics/proposal/', {}, format='json')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['title'], 'Curriculum Analytics Proposal')
        self.assertTrue(response.data['recommendations'])

    def test_admin_dashboard_reports_phase_fifteen_analytics_counts(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['analytics_entries'], 3)
        self.assertEqual(response.data['stats']['analytics_academic_years'], 2)
        self.assertEqual(response.data['migration']['phase'], 15)
