from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import StudentTeam, TeamMembership
from .models import VaultEntry


User = get_user_model()


class DigitalVaultApiTests(APITestCase):
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
            is_panelist=True,
        )
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        self.team = StudentTeam.objects.create(
            name='Team Cipher',
            project_title='Secure Vault Search',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.faculty,
            status=StudentTeam.STATUS_APPROVED,
        )
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='Concept Proposal',
            deliverable_id='D4.1',
            label='D4.1 - Approved Concept Paper',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_Cipher_Approved_Concept.pdf',
            file_size='512 KB',
            uploaded_by=self.faculty,
        )
        DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='Final Defense',
            deliverable_id='D15',
            label='D15 - Fully Functional Software System and Source Code',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_Cipher_Source_Code.zip',
            file_size='24 MB',
            uploaded_by=self.faculty,
        )
        VaultEntry.objects.create(
            file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            team_name='Team VaultSync',
            academic_year='2026-2027',
            status=VaultEntry.STATUS_APPROVED,
            uploaded_by=self.faculty,
        )

    def test_all_roles_can_read_public_vault(self):
        for user in [self.admin, self.faculty, self.student]:
            self.client.force_authenticate(user=user)
            response = self.client.get('/api/repository/vault/')
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.data['counts']['total'], 2)

    def test_public_vault_hides_restricted_capstone_deliverables(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]

        self.assertIn('Team_Cipher_Approved_Concept.pdf', file_names)
        self.assertIn('3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf', file_names)
        self.assertNotIn('Team_Cipher_Source_Code.zip', file_names)
        self.assertEqual(response.data['counts']['restricted'], 1)

    def test_search_and_filters_apply_to_unified_entries(self):
        self.client.force_authenticate(user=self.admin)

        pit_response = self.client.get('/api/repository/vault/', {'type': 'pit', 'year_level': '3rd Year'})
        capstone_response = self.client.get('/api/repository/vault/', {'search': 'concept', 'stage': 'Concept Proposal'})
        empty_response = self.client.get('/api/repository/vault/', {'academic_year': '2025-2026'})

        self.assertEqual(pit_response.data['counts']['filtered'], 1)
        self.assertEqual(pit_response.data['entries'][0]['stage'], 'PIT301')
        self.assertEqual(capstone_response.data['counts']['filtered'], 1)
        self.assertEqual(capstone_response.data['entries'][0]['type'], 'capstone')
        self.assertEqual(empty_response.data['entries'], [])

    def test_stage_options_include_admin_stages_and_historical_vault_stages(self):
        self.client.force_authenticate(user=self.admin)
        DefenseStage.objects.create(
            label='Admin Configured Vault Stage',
            display_order=50,
            is_active=True,
        )
        DefenseStage.objects.create(
            label='Inactive Vault Stage',
            display_order=51,
            is_active=False,
        )
        DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='Archived Legacy Stage',
            deliverable_id='D10',
            label='D10 - Legacy Vault Document',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_Cipher_Legacy.pdf',
            file_size='256 KB',
            uploaded_by=self.faculty,
        )

        response = self.client.get('/api/repository/vault/')

        self.assertEqual(response.status_code, 200)
        options = response.data['options']['stage_options']
        self.assertIn('Admin Configured Vault Stage', options)
        self.assertIn('Archived Legacy Stage', options)
        self.assertIn('Concept Proposal', options)
        self.assertIn('PIT301', options)
        self.assertNotIn('Inactive Vault Stage', options)

    def test_admin_dashboard_reports_current_phase_vault_counts(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['vault_files'], 2)
        self.assertEqual(response.data['stats']['restricted_vault_files'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)
