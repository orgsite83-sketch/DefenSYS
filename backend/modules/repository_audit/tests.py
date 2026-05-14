from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from capstone_deliverables.models import DeliverableSubmission
from digital_vault.models import VaultEntry
from student_teams.models import StudentTeam, TeamMembership
from .models import RepositoryAuditLog


User = get_user_model()


class RepositoryAuditApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.pit_lead = User.objects.create_user(
            username='pit-lead',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        self.other_pit_lead = User.objects.create_user(
            username='pit-lead-2',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
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
        self.capstone_team = StudentTeam.objects.create(
            name='Team Cipher',
            project_title='Secure Vault Search',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.pit_lead,
        )
        self.pit_team = StudentTeam.objects.create(
            name='Team VaultSync',
            project_title='CloudFileSyncSystem',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            status=StudentTeam.STATUS_APPROVED,
        )
        TeamMembership.objects.create(team=self.capstone_team, student=self.student, is_leader=True)
        DeliverableSubmission.objects.create(
            team=self.capstone_team,
            stage_label='Concept Proposal',
            deliverable_id='D1',
            label='D1 - Advisers Acceptance Form',
            deliverable_type=DeliverableSubmission.TYPE_PRE,
            required=True,
            file_name='Team_Cipher_D1.pdf',
            uploaded_by=self.admin,
        )
        DeliverableSubmission.objects.create(
            team=self.capstone_team,
            stage_label='Final Defense',
            deliverable_id='D15',
            label='D15 - Fully Functional Software System and Source Code',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_Cipher_Source_Code.zip',
            uploaded_by=self.admin,
        )
        self.pit_entry = VaultEntry.objects.create(
            file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            team=self.pit_team,
            academic_year='2026-2027',
            status=VaultEntry.STATUS_PENDING,
            uploaded_by=self.pit_lead,
        )
        VaultEntry.objects.create(
            file_name='2ndYear.PIT201.CampusSocialNetwork.1stSemester.pdf',
            academic_year='2026-2027',
            status=VaultEntry.STATUS_APPROVED,
            uploaded_by=self.other_pit_lead,
        )

    def test_admin_sees_unified_pit_and_all_capstone_entries(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/repository-audit/')
        file_names = [entry['file_name'] for entry in response.data['entries']]

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['total'], 4)
        self.assertIn('Team_Cipher_D1.pdf', file_names)
        self.assertIn('Team_Cipher_Source_Code.zip', file_names)
        self.assertEqual(response.data['scope']['scope'], 'admin')

    def test_pit_lead_is_scoped_to_assigned_year_and_pit_entries(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/repository-audit/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['total'], 1)
        self.assertEqual(response.data['entries'][0]['type'], 'pit')
        self.assertEqual(response.data['entries'][0]['year_level'], '3rd Year')
        self.assertEqual(response.data['scope']['scope'], 'pit_lead')

    def test_pit_upload_validates_filename_and_matches_team(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.post(
            '/api/repository-audit/upload-pit/',
            {
                'file_names': [
                    '3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
                    'bad-file.pdf',
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(len(response.data['skipped']), 1)
        entry = VaultEntry.objects.get(file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf')
        self.assertEqual(entry.team, self.pit_team)

    def test_classify_and_admin_override_update_pit_status_and_logs(self):
        self.client.force_authenticate(user=self.pit_lead)
        classify = self.client.post(
            '/api/repository-audit/classify/',
            {'entry_id': f'pit-{self.pit_entry.id}'},
            format='json',
        )
        self.assertEqual(classify.status_code, 200)
        self.pit_entry.refresh_from_db()
        self.assertEqual(self.pit_entry.status, VaultEntry.STATUS_APPROVED)

        forbidden = self.client.post(
            '/api/repository-audit/override-status/',
            {'entry_id': f'pit-{self.pit_entry.id}', 'status': VaultEntry.STATUS_NEEDS_REVISION},
            format='json',
        )
        self.assertEqual(forbidden.status_code, 403)

        self.client.force_authenticate(user=self.admin)
        override = self.client.post(
            '/api/repository-audit/override-status/',
            {'entry_id': f'pit-{self.pit_entry.id}', 'status': VaultEntry.STATUS_NEEDS_REVISION},
            format='json',
        )

        self.assertEqual(override.status_code, 200)
        self.pit_entry.refresh_from_db()
        self.assertEqual(self.pit_entry.status, VaultEntry.STATUS_NEEDS_REVISION)
        self.assertEqual(RepositoryAuditLog.objects.filter(source_id=self.pit_entry.id).count(), 2)

    @override_settings(ENABLE_PROTOTYPE_TOOLS=True)
    def test_admin_demo_fill_pit_works_without_imported_teams(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.post(
            '/api/repository-audit/demo-fill/',
            {'type': 'pit', 'year_level': '1st Year'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['created_count'], 3)
        self.assertEqual(VaultEntry.objects.filter(year_level='1st Year').count(), 3)

    def test_admin_dashboard_reports_phase_fourteen_repository_counts(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['repository_files'], 4)
        self.assertEqual(response.data['stats']['pending_repository_files'], 1)
        self.assertEqual(response.data['stats']['approved_repository_files'], 2)
        self.assertEqual(response.data['migration']['phase'], 15)
