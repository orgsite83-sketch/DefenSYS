from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable
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
        
        # Clear existing stages seeded from data migrations to avoid unique constraint violations
        DefenseStage.objects.all().delete()

        # Create Defense Stages and Stage Deliverables for templates
        self.concept_stage = DefenseStage.objects.create(label='Concept Proposal', display_order=1)
        self.final_stage = DefenseStage.objects.create(label='Final Defense', display_order=2)
        
        StageDeliverable.objects.create(
            defense_stage=self.concept_stage,
            deliverable_id='D4.1',
            label='D4.1 - Approved Concept Paper',
            deliverable_type=StageDeliverable.TYPE_VAULT,
            is_restricted=False,
        )
        StageDeliverable.objects.create(
            defense_stage=self.final_stage,
            deliverable_id='D15',
            label='D15 - Fully Functional Software System and Source Code',
            deliverable_type=StageDeliverable.TYPE_VAULT,
            is_restricted=True,
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
            status=DeliverableSubmission.STATUS_ACCEPTED,
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
            status=DeliverableSubmission.STATUS_ACCEPTED,
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
            status=DeliverableSubmission.STATUS_ACCEPTED,
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

    def test_student_pit_vault_uploads_visibility(self):
        # Create a PIT team
        self.pit_team = StudentTeam.objects.create(
            name='Team PIT Cipher',
            project_title='Secure PIT Search',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.faculty,
            status=StudentTeam.STATUS_APPROVED,
        )
        # Create a pending student-uploaded PIT vault deliverable (should NOT be visible)
        DeliverableSubmission.objects.create(
            team=self.pit_team,
            stage_label='PIT Event 1',
            deliverable_id='D_PIT_1',
            label='PIT Project Doc',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_PIT_Cipher_Pending.pdf',
            file_size='256 KB',
            uploaded_by=self.student,
            status=DeliverableSubmission.STATUS_PENDING,
        )

        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertNotIn('Team_PIT_Cipher_Pending.pdf', file_names)

        # Create an accepted student-uploaded PIT vault deliverable (should be visible)
        DeliverableSubmission.objects.create(
            team=self.pit_team,
            stage_label='PIT Event 1',
            deliverable_id='D_PIT_2',
            label='PIT Project Doc 2',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_PIT_Cipher_Accepted.pdf',
            file_size='256 KB',
            uploaded_by=self.student,
            status=DeliverableSubmission.STATUS_ACCEPTED,
        )

        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertIn('Team_PIT_Cipher_Accepted.pdf', file_names)

    def test_dynamic_deliverable_restriction_toggling(self):
        from defense.scheduler.models import PitEventGradingConfig, PitEventDeliverable
        from grading.rubrics.models import Rubric

        # 1. PIT Track testing
        # Create the configuration and template for D_PIT_2
        panel_rubric = Rubric.objects.create(name='PIT Panel', scope='pit', evaluation_type='panel', status='published', semester=self.semester)
        peer_rubric = Rubric.objects.create(name='PIT Peer', scope='pit', evaluation_type='peer', status='published', semester=self.semester)
        pit_config = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='PIT Event 1',
            panel_rubric=panel_rubric,
            peer_rubric=peer_rubric,
        )
        pit_deliv = PitEventDeliverable.objects.create(
            pit_event_config=pit_config,
            deliverable_id='D_PIT_2',
            label='PIT Project Doc 2',
            deliverable_type=PitEventDeliverable.TYPE_VAULT,
            required=False,
            is_restricted=False,
        )

        # Create a submission for PIT
        self.pit_team = StudentTeam.objects.create(
            name='Team PIT Cipher',
            project_title='Secure PIT Search',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.faculty,
            status=StudentTeam.STATUS_APPROVED,
        )
        DeliverableSubmission.objects.create(
            team=self.pit_team,
            stage_label='PIT Event 1',
            deliverable_id='D_PIT_2',
            label='PIT Project Doc 2',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='Team_PIT_Cipher_Accepted.pdf',
            file_size='256 KB',
            uploaded_by=self.student,
            status=DeliverableSubmission.STATUS_ACCEPTED,
        )

        self.client.force_authenticate(user=self.admin)

        # Initially visible
        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertIn('Team_PIT_Cipher_Accepted.pdf', file_names)

        # Toggle to restricted
        pit_deliv.is_restricted = True
        pit_deliv.save()

        # Now hidden from public vault
        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertNotIn('Team_PIT_Cipher_Accepted.pdf', file_names)

        # 2. Capstone Track testing (D4.1 is initially public)
        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertIn('Team_Cipher_Approved_Concept.pdf', file_names)

        # Toggle D4.1 to restricted
        stage_deliv = StageDeliverable.objects.get(defense_stage=self.concept_stage, deliverable_id='D4.1')
        stage_deliv.is_restricted = True
        stage_deliv.save()

        # D4.1 should now be hidden
        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertNotIn('Team_Cipher_Approved_Concept.pdf', file_names)

    def test_vault_de_duplication(self):
        team = StudentTeam.objects.create(
            name='Team SyncDupe',
            project_title='Search Sync',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.faculty,
            status=StudentTeam.STATUS_APPROVED,
        )
        VaultEntry.objects.create(
            file_name='3rdYear.PIT301.SearchSync.1stSemester.pdf',
            team=team,
            team_name='Team SyncDupe',
            academic_year='2026-2027',
            semester_label='1st Semester',
            year_level='3rd Year',
            stage_label='PIT Event 1',
            entry_type=VaultEntry.TYPE_PIT,
            status=VaultEntry.STATUS_APPROVED,
        )
        DeliverableSubmission.objects.create(
            team=team,
            stage_label='PIT Event 1',
            deliverable_id='D_PIT_Sync',
            label='PIT Sync File',
            deliverable_type=DeliverableSubmission.TYPE_VAULT,
            required=False,
            file_name='StudentSyncFile.pdf',
            file_size='120 KB',
            uploaded_by=self.student,
            status=DeliverableSubmission.STATUS_ACCEPTED,
        )
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/vault/')
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertIn('StudentSyncFile.pdf', file_names)
        self.assertNotIn('3rdYear.PIT301.SearchSync.1stSemester.pdf', file_names)

