from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from repository.deliverables.models import DeliverableSubmission
from repository.archive.models import ArchiveEntry
from student_teams.models import StudentTeam, TeamMembership
from .services import UNCLASSIFIED_TECH_STACK, extract_tech, extract_domain, stack_color


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
            deliverable_type=DeliverableSubmission.TYPE_POST,
            required=False,
            file_name='Team_CloudSync_Executive_Journal.pdf',
            uploaded_by=self.faculty,
        )
        DeliverableSubmission.objects.create(
            team=self.old_team,
            stage_label='Concept Proposal',
            deliverable_id='D4.1',
            label='D4.1 - Approved Concept Paper',
            deliverable_type=DeliverableSubmission.TYPE_POST,
            required=False,
            file_name='Team_MobileAid_Flutter_Attendance.pdf',
            uploaded_by=self.faculty,
        )
        ArchiveEntry.objects.create(
            file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            team_name='Team VaultSync',
            academic_year='2026-2027',
            status=ArchiveEntry.STATUS_APPROVED,
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
        # Verify new DSS multi-dimensional payload elements
        self.assertIn('kpi_summary', response.data)
        self.assertIn('competency_matrix', response.data)
        self.assertIn('domain_distribution', response.data)
        self.assertIn('defense_funnel', response.data)
        self.assertIn('longitudinal_5year', response.data)
        self.assertIn('prescriptions', response.data)

        # Verify clustered breakdown fields in competency matrix
        if response.data['competency_matrix']:
            first_item = response.data['competency_matrix'][0]
            self.assertIn('evaluator_breakdown', first_item)
            self.assertIn('stage_breakdown', first_item)
            self.assertIn('score_spread', first_item)
            self.assertIn('panel', first_item['evaluator_breakdown'])
            self.assertIn('adviser', first_item['evaluator_breakdown'])
            self.assertIn('peer', first_item['evaluator_breakdown'])

    def test_dss_track_scoping_and_subsystems(self):
        self.client.force_authenticate(user=self.admin)

        # Test Capstone Scoping
        capstone_res = self.client.get('/api/curriculum-analytics/?scope=capstone')
        self.assertEqual(capstone_res.status_code, 200)
        self.assertEqual(capstone_res.data['selected_scope'], 'capstone')
        self.assertEqual(capstone_res.data['entries_count'], 2)  # 2 capstone submissions

        # Test PIT Scoping
        pit_res = self.client.get('/api/curriculum-analytics/?scope=pit')
        self.assertEqual(pit_res.status_code, 200)
        self.assertEqual(pit_res.data['selected_scope'], 'pit')
        self.assertEqual(pit_res.data['entries_count'], 1)  # 1 PIT archive entry

        # Verify DSS Subsystems Data Architecture
        self.assertIn('metadata_catalog', capstone_res.data)
        catalog_keys = [item['key'] for item in capstone_res.data['metadata_catalog']]
        self.assertIn('cpi', catalog_keys)
        self.assertIn('divergence', catalog_keys)
        self.assertIn('friction', catalog_keys)

        self.assertIn('evaluator_calibration', capstone_res.data)
        self.assertIn('calibration_status', capstone_res.data['evaluator_calibration'])

        self.assertIn('simulation_scenarios', capstone_res.data)
        self.assertIn('benchmark_scenarios', capstone_res.data['simulation_scenarios'])
        self.assertIn('weight_scenarios', capstone_res.data['simulation_scenarios'])


    def test_domain_extraction_identifies_specialization(self):
        domain = extract_domain({
            'file_name': 'Team_YOLO_Camera_System.pdf',
            'team_name': 'Team VisionAI',
            'project_title': 'Deep Learning Computer Vision Detection System',
            'deliverable_label': 'Executive Journal',
            'stage': 'Final Defense',
            'year_level': '4th Year',
            'summary': 'YOLO and neural networks for object detection',
            'topics': ['Machine Learning', 'Computer Vision'],
            'category': 'Machine Learning',
            'category_confidence': 90,
            'extracted_text': '',
        })
        self.assertEqual(domain, 'Artificial Intelligence & ML')

    def test_unknown_project_tech_is_unclassified(self):
        stack = extract_tech({
            'file_name': 'Team_Obscure_Abstract.pdf',
            'team_name': 'Team Obscure',
            'project_title': 'Untitled Research Output',
            'deliverable_label': 'Executive Journal',
            'stage': 'Final Defense',
            'year_level': '4th Year',
            'summary': '',
            'topics': [],
            'category': '',
            'category_confidence': None,
            'extracted_text': '',
        })

        self.assertEqual(stack, UNCLASSIFIED_TECH_STACK)
        self.assertEqual(stack_color(stack), '#6B7280')

    def test_low_confidence_category_does_not_invent_stack(self):
        stack = extract_tech({
            'file_name': 'Team_Low_Confidence.pdf',
            'team_name': 'Team Low Confidence',
            'project_title': 'General Project',
            'deliverable_label': 'Executive Journal',
            'stage': 'Final Defense',
            'year_level': '4th Year',
            'summary': '',
            'topics': [],
            'category': 'Database Systems',
            'category_confidence': 5,
            'extracted_text': '',
        })

        self.assertEqual(stack, UNCLASSIFIED_TECH_STACK)

    def test_pit_course_code_alone_does_not_invent_stack(self):
        stack = extract_tech({
            'type': 'pit',
            'file_name': '1stYear.PIT101.GeneralOutput.1stSemester.pdf',
            'team_name': 'Team Course Only',
            'project_title': '',
            'deliverable_label': '1stYear.PIT101.GeneralOutput.1stSemester.pdf',
            'stage': 'PIT101',
            'year_level': '1st Year',
            'summary': '',
            'topics': [],
            'category': '',
            'category_confidence': None,
            'extracted_text': '',
        })

        self.assertEqual(stack, UNCLASSIFIED_TECH_STACK)

    def test_non_admin_cannot_read_curriculum_analytics(self):
        self.client.force_authenticate(user=self.faculty)

        response = self.client.get('/api/curriculum-analytics/')

        self.assertEqual(response.status_code, 403)

        self.client.force_authenticate(user=self.admin)

        response = self.client.post('/api/curriculum-analytics/proposal/', {}, format='json')

        self.assertEqual(response.status_code, 200)
        self.assertTrue('Curriculum Decision Support Proposal' in response.data['title'] or 'Curriculum' in response.data['title'])
        self.assertTrue(response.data['recommendations'])

    def test_admin_downloads_curriculum_proposal_pdf(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/curriculum-analytics/proposal/pdf/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'application/pdf')
        self.assertTrue(len(response.content) > 1000)

    def test_admin_dashboard_reports_phase_fifteen_analytics_counts(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['analytics_entries'], 3)
        self.assertEqual(response.data['stats']['analytics_academic_years'], 2)
        self.assertEqual(response.data['migration']['phase'], 15)
