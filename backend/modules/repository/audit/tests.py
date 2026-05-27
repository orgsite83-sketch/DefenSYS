from decimal import Decimal
from io import BytesIO
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventGradingConfig
from defense.stages.models import DefenseStage, StageGradingConfig
from grading.grades.models import TeamGrade
from grading.rubrics.models import Rubric, RubricCriterion
from repository.deliverables.models import DeliverableSubmission
from repository.vault.models import VaultEntry
from student_teams.models import StudentTeam, TeamMembership
from .models import RepositoryAuditLog
from .services import validate_capstone_file_name, validate_pit_file_name


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
        self.repo_assistant_faculty = User.objects.create_user(
            username='repo-assist',
            password='pass12345',
            role='faculty',
            first_name='Repo',
            last_name='Assistant',
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
            entry_type=VaultEntry.TYPE_PIT,
            file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            status=VaultEntry.STATUS_APPROVED,
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

        response = self.client.get('/api/repository/audit/')
        file_names = [entry['file_name'] for entry in response.data['entries']]

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['total'], 4)
        self.assertIn('Team_Cipher_D1.pdf', file_names)
        self.assertIn('Team_Cipher_Source_Code.zip', file_names)
        self.assertEqual(response.data['scope']['scope'], 'admin')

    def test_admin_can_view_pit_but_not_upload(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/repository/audit/')
        file_names = [entry['file_name'] for entry in response.data['entries']]

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['scope']['can_upload_pit'])
        self.assertIn(self.pit_entry.file_name, file_names)

        pit_count_before = VaultEntry.objects.filter(entry_type=VaultEntry.TYPE_PIT).count()
        upload = self.client.post(
            '/api/repository/audit/upload-pit/',
            {'file_names': [self.pit_entry.file_name]},
            format='json',
        )
        self.assertEqual(upload.status_code, 403)
        self.assertEqual(
            VaultEntry.objects.filter(entry_type=VaultEntry.TYPE_PIT).count(),
            pit_count_before,
        )

    def test_pit_lead_is_scoped_to_assigned_year_and_pit_entries(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/repository/audit/')
        file_names = [entry['file_name'] for entry in response.data['entries']]

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['total'], 1)
        self.assertEqual(response.data['entries'][0]['type'], 'pit')
        self.assertEqual(response.data['entries'][0]['year_level'], '3rd Year')
        self.assertIn(self.pit_entry.file_name, file_names)
        self.assertNotIn('2ndYear.PIT201.CampusSocialNetwork.1stSemester.pdf', file_names)
        self.assertNotIn('Team_Cipher_D1.pdf', file_names)
        self.assertEqual(response.data['scope']['scope'], 'pit_lead')

    def test_pit_lead_all_records_and_capstone_filter_stay_in_assigned_pit_scope(self):
        self.client.force_authenticate(user=self.pit_lead)

        all_records = self.client.get('/api/repository/audit/', {'type': ''})
        capstone_filter = self.client.get('/api/repository/audit/', {'type': 'capstone'})

        self.assertEqual(all_records.status_code, 200)
        self.assertEqual(capstone_filter.status_code, 200)
        self.assertEqual(all_records.data['counts']['total'], 1)
        self.assertEqual(capstone_filter.data['counts']['total'], 1)
        self.assertEqual(capstone_filter.data['entries'][0]['type'], 'pit')
        self.assertEqual(capstone_filter.data['entries'][0]['year_level'], '3rd Year')

    def _open_upload_window_for_pit_team(self, event_name='3rd Year Expo'):
        panel = Rubric.objects.create(
            name='PIT Panel Audit',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        peer = Rubric.objects.create(
            name='PIT Peer Audit',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        RubricCriterion.objects.create(
            rubric=panel,
            name='Delivery',
            scale=Rubric.SCALE_100,
            max_score=100,
            display_order=0,
        )
        RubricCriterion.objects.create(
            rubric=peer,
            name='Teamwork',
            scale=Rubric.SCALE_5,
            max_score=5,
            display_order=0,
        )
        config = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name=event_name,
            panel_rubric=panel,
            peer_rubric=peer,
            is_officially_complete=True,
        )
        TeamGrade.objects.create(
            team=self.pit_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_PIT,
            stage_label=event_name,
            pit_event_config=config,
            status=TeamGrade.STATUS_PENDING,
            final_grade=Decimal('88.00'),
            panel_score=Decimal('90.00'),
            peer_score=Decimal('80.00'),
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
        )

    def test_upload_window_closed_before_official_complete(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/repository/audit/')

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['upload_window']['open'])
        self.assertFalse(response.data['scope']['can_upload_pit'])

    def test_upload_window_open_for_team_year_not_event_name_year(self):
        """3rd Year team on '2nd yr expo' is eligible when that event is complete."""
        panel = Rubric.objects.create(
            name='2nd Panel Cross',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        peer = Rubric.objects.create(
            name='2nd Peer Cross',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        RubricCriterion.objects.create(
            rubric=panel,
            name='Delivery',
            scale=Rubric.SCALE_100,
            max_score=100,
            display_order=0,
        )
        RubricCriterion.objects.create(
            rubric=peer,
            name='Teamwork',
            scale=Rubric.SCALE_5,
            max_score=5,
            display_order=0,
        )
        event_name = '2nd yr expo'
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name=event_name,
            panel_rubric=panel,
            peer_rubric=peer,
            is_officially_complete=True,
        )
        TeamGrade.objects.create(
            team=self.pit_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_PIT,
            stage_label=event_name,
            status=TeamGrade.STATUS_PENDING,
            final_grade=Decimal('88.00'),
            panel_score=Decimal('90.00'),
            peer_score=Decimal('80.00'),
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
        )

        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.get('/api/repository/audit/')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['upload_window']['open'])
        self.assertEqual(len(response.data['upload_window']['queue']), 1)

    def test_pit_upload_window_uses_event_grade_not_team_status(self):
        self._open_upload_window_for_pit_team(event_name='3rd Year Expo')
        self.pit_team.status = StudentTeam.STATUS_PENDING
        self.pit_team.save(update_fields=['status', 'updated_at'])

        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.get('/api/repository/audit/')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['upload_window']['open'])
        self.assertEqual(response.data['upload_window']['queue'][0]['team_id'], self.pit_team.id)

    def test_pit_upload_does_not_publish_grade_after_vault(self):
        self._open_upload_window_for_pit_team(event_name='3rd Year Expo')
        self.client.force_authenticate(user=self.pit_lead)
        grade = TeamGrade.objects.get(team=self.pit_team)
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)

        pdf_bytes = b'%PDF-1.4 test'
        upload_file = SimpleUploadedFile(
            '3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            pdf_bytes,
            content_type='application/pdf',
        )
        response = self.client.post(
            '/api/repository/audit/upload-pit/',
            {'files': upload_file},
            format='multipart',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['created_count'], 1)
        entry = VaultEntry.objects.get(entry_type=VaultEntry.TYPE_PIT, team=self.pit_team)
        self.assertEqual(entry.pit_event_config_id, grade.pit_event_config_id)
        grade.refresh_from_db()
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)

    def test_upload_window_closed_for_other_year_only_event(self):
        panel = Rubric.objects.create(
            name='2nd Panel',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        peer = Rubric.objects.create(
            name='2nd Peer',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        RubricCriterion.objects.create(
            rubric=panel,
            name='Delivery',
            scale=Rubric.SCALE_100,
            max_score=100,
            display_order=0,
        )
        RubricCriterion.objects.create(
            rubric=peer,
            name='Teamwork',
            scale=Rubric.SCALE_5,
            max_score=5,
            display_order=0,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd yr expo',
            panel_rubric=panel,
            peer_rubric=peer,
            is_officially_complete=True,
        )

        self.client.force_authenticate(user=self.other_pit_lead)
        second_year = self.client.get('/api/repository/audit/')
        self.assertFalse(second_year.data['upload_window']['open'])

        self.client.force_authenticate(user=self.pit_lead)
        third_year = self.client.get('/api/repository/audit/')
        self.assertFalse(third_year.data['upload_window']['open'])
        self.assertFalse(third_year.data['scope']['can_upload_pit'])

    def test_pit_upload_requires_officially_complete_event(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.post(
            '/api/repository/audit/upload-pit/',
            {'file_names': ['3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf']},
            format='json',
        )

        self.assertIn(response.status_code, (400, 403))

    def test_pit_upload_validates_filename_and_matches_team(self):
        self._open_upload_window_for_pit_team()
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.post(
            '/api/repository/audit/upload-pit/',
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
        self.assertIn('bad-file.pdf', response.data['skipped'][0]['file_name'])
        self.assertIn('format', response.data['skipped'][0]['reason'].lower())
        entry = VaultEntry.objects.get(file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf')
        self.assertEqual(entry.team, self.pit_team)

    def test_pit_lead_assigns_repository_assistant_and_revokes_previous(self):
        self.client.force_authenticate(user=self.pit_lead)
        other_assistant = User.objects.create_user(
            username='old-assist',
            password='pass12345',
            role='faculty',
            is_repo_assistant=True,
            is_uploader=True,
            repo_assistant_year='3rd Year',
        )

        response = self.client.post(
            '/api/dashboards/pit-lead/repository-assistant/',
            {'faculty_id': self.repo_assistant_faculty.id},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['assigned']['id'], self.repo_assistant_faculty.id)
        self.repo_assistant_faculty.refresh_from_db()
        other_assistant.refresh_from_db()
        self.assertTrue(self.repo_assistant_faculty.is_repo_assistant)
        self.assertEqual(self.repo_assistant_faculty.repo_assistant_year, '3rd Year')
        self.assertFalse(other_assistant.is_repo_assistant)
        self.assertEqual(other_assistant.repo_assistant_year, '')

    def test_multipart_pit_upload_stores_file_on_vault_entry(self):
        self._open_upload_window_for_pit_team()
        pdf_bytes = b'%PDF-1.4 minimal test content'
        upload_file = SimpleUploadedFile(
            '3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            pdf_bytes,
            content_type='application/pdf',
        )
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.post(
            '/api/repository/audit/upload-pit/',
            {
                'files': upload_file,
                'year_level': '3rd Year',
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['created_count'], 1)
        entry = VaultEntry.objects.get(
            file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
        )
        self.assertTrue(entry.file)
        self.assertTrue(entry.file.name)
        self.assertTrue(
            entry.file.name.startswith('vault_entries/pit/3rd-Year/'),
            entry.file.name,
        )
        self.assertEqual(entry.status, VaultEntry.STATUS_APPROVED)

    def test_audit_search_matches_pdf_topics(self):
        VaultEntry.objects.filter(pk=self.pit_entry.pk).update(
            extracted_text='Smart campus navigation with flutter mobile sensors',
            topics=['flutter', 'campus', 'navigation'],
            category='Mobile Development',
            status=VaultEntry.STATUS_APPROVED,
        )
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/', {'search': 'flutter'})
        self.assertEqual(response.status_code, 200)
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertIn(self.pit_entry.file_name, file_names)

    def test_assigned_assistant_can_upload_when_window_open(self):
        self._open_upload_window_for_pit_team()
        self.client.force_authenticate(user=self.pit_lead)
        self.client.post(
            '/api/dashboards/pit-lead/repository-assistant/',
            {'faculty_id': self.repo_assistant_faculty.id},
            format='json',
        )

        self.repo_assistant_faculty.refresh_from_db()
        self.client.force_authenticate(user=self.repo_assistant_faculty)
        audit = self.client.get('/api/repository/audit/')
        self.assertEqual(audit.status_code, 200)
        self.assertTrue(audit.data['scope']['can_upload_pit'])
        self.assertEqual(audit.data['scope']['pit_year_level'], '3rd Year')
        self.assertEqual(audit.data['scope']['scope'], 'repo_assistant')
        self.assertEqual(audit.data['counts']['total'], 1)
        self.assertEqual(audit.data['entries'][0]['type'], 'pit')
        self.assertEqual(audit.data['entries'][0]['year_level'], '3rd Year')

        upload = self.client.post(
            '/api/repository/audit/upload-pit/',
            {'file_names': ['3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf']},
            format='json',
        )
        self.assertEqual(upload.status_code, 200)
        self.assertEqual(upload.data['created_count'], 1)

    def test_assigned_assistant_scope_excludes_other_year_queue_and_records(self):
        self._open_upload_window_for_pit_team()
        other_student = User.objects.create_user(
            username='2024-0002',
            password='pass12345',
            role='student',
        )
        other_team = StudentTeam.objects.create(
            name='Team Other PIT',
            project_title='OtherPITSystem',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.semester,
            leader=other_student,
            status=StudentTeam.STATUS_APPROVED,
        )
        config = PitEventGradingConfig.objects.get(event_name='3rd Year Expo')
        TeamGrade.objects.create(
            team=other_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_PIT,
            stage_label=config.event_name,
            pit_event_config=config,
            status=TeamGrade.STATUS_PENDING,
            final_grade=Decimal('88.00'),
            panel_score=Decimal('90.00'),
            peer_score=Decimal('80.00'),
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
        )
        self.client.force_authenticate(user=self.pit_lead)
        self.client.post(
            '/api/dashboards/pit-lead/repository-assistant/',
            {'faculty_id': self.repo_assistant_faculty.id},
            format='json',
        )

        self.repo_assistant_faculty.refresh_from_db()
        self.client.force_authenticate(user=self.repo_assistant_faculty)
        response = self.client.get('/api/repository/audit/', {'type': ''})
        file_names = [entry['file_name'] for entry in response.data['entries']]
        queue_team_ids = [
            item['team_id']
            for item in response.data['upload_window']['queue']
        ]

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['scope']['scope'], 'repo_assistant')
        self.assertEqual(response.data['scope']['pit_year_level'], '3rd Year')
        self.assertIn(self.pit_entry.file_name, file_names)
        self.assertNotIn('2ndYear.PIT201.CampusSocialNetwork.1stSemester.pdf', file_names)
        self.assertNotIn('Team_Cipher_D1.pdf', file_names)
        self.assertIn(self.pit_team.id, queue_team_ids)
        self.assertNotIn(other_team.id, queue_team_ids)

    def test_pit_lead_cannot_upload_when_assistant_assigned(self):
        self._open_upload_window_for_pit_team()
        self.client.force_authenticate(user=self.pit_lead)
        self.client.post(
            '/api/dashboards/pit-lead/repository-assistant/',
            {'faculty_id': self.repo_assistant_faculty.id},
            format='json',
        )

        audit = self.client.get('/api/repository/audit/')
        self.assertFalse(audit.data['scope']['can_upload_pit'])
        self.assertTrue(audit.data['scope']['has_assigned_assistant'])

    def test_admin_override_update_pit_status_and_logs(self):
        self.client.force_authenticate(user=self.pit_lead)
        forbidden = self.client.post(
            '/api/repository/audit/override-status/',
            {'entry_id': f'pit-{self.pit_entry.id}', 'status': VaultEntry.STATUS_NEEDS_REVISION},
            format='json',
        )
        self.assertEqual(forbidden.status_code, 403)

        self.client.force_authenticate(user=self.admin)
        override = self.client.post(
            '/api/repository/audit/override-status/',
            {'entry_id': f'pit-{self.pit_entry.id}', 'status': VaultEntry.STATUS_NEEDS_REVISION},
            format='json',
        )

        self.assertEqual(override.status_code, 200)
        self.pit_entry.refresh_from_db()
        self.assertEqual(self.pit_entry.status, VaultEntry.STATUS_NEEDS_REVISION)
        self.assertEqual(RepositoryAuditLog.objects.filter(source_id=self.pit_entry.id).count(), 1)

    def _open_capstone_upload_window(self, stage_label='Concept Proposal'):
        stage, _ = DefenseStage.objects.get_or_create(
            label=stage_label,
            defaults={'display_order': 1, 'is_active': True},
        )
        StageGradingConfig.objects.update_or_create(
            defense_stage=stage,
            semester=self.semester,
            defaults={
                'is_officially_complete': True,
                'panel_weight': 50,
                'adviser_weight': 30,
                'peer_weight': 20,
            },
        )
        self.capstone_team.status = StudentTeam.STATUS_APPROVED
        self.capstone_team.save(update_fields=['status', 'updated_at'])
        TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label=stage_label,
            defense_stage=stage,
            status=TeamGrade.STATUS_PENDING,
            final_grade=Decimal('97.16'),
            panel_score=Decimal('100.00'),
            adviser_score=Decimal('100.00'),
            peer_score=Decimal('85.80'),
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
        )

    def test_capstone_upload_window_closed_before_stage_complete(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/')
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['capstone_upload_window']['open'])
        self.assertFalse(response.data['scope']['can_upload_capstone'])

    def test_capstone_upload_window_open_with_passed_grade(self):
        self._open_capstone_upload_window()
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['capstone_upload_window']['open'])
        self.assertTrue(response.data['scope']['can_upload_capstone'])
        self.assertEqual(len(response.data['capstone_upload_window']['queue']), 1)
        self.assertIn(
            'SecureVaultSearch',
            response.data['capstone_upload_window']['queue'][0]['suggested_file_name'],
        )

    def test_capstone_upload_creates_vault_entry_without_publishing_grade(self):
        self._open_capstone_upload_window()
        self.client.force_authenticate(user=self.admin)
        file_name = '3rdYear.CAP301.SecureVaultSearch.1stSemester.pdf'
        upload = self.client.post(
            '/api/repository/audit/upload-capstone/',
            {'file_names': [file_name]},
            format='json',
        )
        self.assertEqual(upload.status_code, 200)
        self.assertEqual(upload.data['created_count'], 1)
        entry = VaultEntry.objects.get(
            entry_type=VaultEntry.TYPE_CAPSTONE,
            file_name=file_name,
        )
        self.assertEqual(entry.team_id, self.capstone_team.id)
        self.assertIsNotNone(entry.defense_stage_id)
        grade = TeamGrade.objects.get(team=self.capstone_team, scope=TeamGrade.SCOPE_CAPSTONE)
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)

    def test_submission_kind_pre_excludes_vault_and_archive(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(
            '/api/repository/audit/',
            {'submission_kind': 'pre'},
        )
        self.assertEqual(response.status_code, 200)
        kinds = {entry.get('submission_kind') for entry in response.data['entries']}
        self.assertTrue(kinds.issubset({'pre'}))
        self.assertGreater(response.data['counts']['pre_defense'], 0)

    def test_options_include_deliverable_and_team_counts(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/')
        self.assertEqual(response.status_code, 200)
        options = response.data['options']
        self.assertIn('deliverable_options', options)
        self.assertIn('team_counts', options)
        self.assertIn('submission_kind_options', options)
        self.assertIn('archive_pdf', response.data['counts'])

    def test_filter_deliverable_d1_returns_capstone_submissions(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(
            '/api/repository/audit/',
            {'deliverable_id': 'D1'},
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(
            all(entry.get('deliverable_id') == 'D1' for entry in response.data['entries'])
        )
        self.assertIn('Team_Cipher_D1.pdf', [e['file_name'] for e in response.data['entries']])
        self.assertEqual(response.data['deliverable_summary']['deliverable_id'], 'D1')

    def test_team_view_returns_grouped_by_stage(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(
            '/api/repository/audit/',
            {
                'type': 'capstone',
                'team_id': str(self.capstone_team.id),
                'view': 'team',
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['grouped_by_stage'])
        first = response.data['grouped_by_stage'][0]
        self.assertIn('pre_defense', first)
        self.assertIn('vault', first)
        self.assertIn('archive', first)

    def test_capstone_entries_include_submission_kind(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/', {'type': 'capstone'})
        capstone_rows = [
            entry
            for entry in response.data['entries']
            if entry.get('submission_kind') in ('pre', 'vault', 'archive')
        ]
        self.assertTrue(capstone_rows)
        self.assertIn(
            'pre',
            {entry['submission_kind'] for entry in capstone_rows},
        )

    def test_team_counts_capstone_excludes_pit_level_team_with_same_name(self):
        pit_team = StudentTeam.objects.create(
            name='Team CodeLearners',
            project_title='Cloud Navigator',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            status=StudentTeam.STATUS_APPROVED,
        )
        capstone_team = StudentTeam.objects.create(
            name='Team CodeLearners',
            project_title='Smart Campus Navigator',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            status=StudentTeam.STATUS_APPROVED,
        )
        VaultEntry.objects.create(
            entry_type=VaultEntry.TYPE_PIT,
            file_name='3rdYear.PIT301.SmartCampusNavigator.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            team=pit_team,
            team_name=pit_team.name,
            status=VaultEntry.STATUS_APPROVED,
            uploaded_by=self.pit_lead,
        )
        VaultEntry.objects.create(
            entry_type=VaultEntry.TYPE_CAPSTONE,
            file_name='3rdYear.CAP301.SmartCampusNavigator.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            team=capstone_team,
            team_name=capstone_team.name,
            stage_label='Concept Proposal',
            status=VaultEntry.STATUS_APPROVED,
            uploaded_by=self.admin,
        )
        DeliverableSubmission.objects.create(
            team=capstone_team,
            stage_label='Concept Proposal',
            deliverable_id='D1',
            label='D1 - Advisers Acceptance Form',
            deliverable_type=DeliverableSubmission.TYPE_PRE,
            required=True,
            file_name='codelearners_d1.pdf',
            uploaded_by=self.admin,
        )

        self.client.force_authenticate(user=self.admin)
        capstone_audit = self.client.get('/api/repository/audit/', {'type': 'capstone'})
        self.assertEqual(capstone_audit.status_code, 200)
        team_ids = [row['id'] for row in capstone_audit.data['options']['team_counts']]
        self.assertIn(capstone_team.id, team_ids)
        self.assertNotIn(pit_team.id, team_ids)
        levels = [row['level'] for row in capstone_audit.data['options']['team_counts']]
        self.assertTrue(any('Capstone' in level for level in levels))

        file_names = [entry['file_name'] for entry in capstone_audit.data['entries']]
        self.assertIn('codelearners_d1.pdf', file_names)
        self.assertIn('3rdYear.CAP301.SmartCampusNavigator.1stSemester.pdf', file_names)

    def test_grouped_by_stage_includes_pre_when_archive_exists(self):
        team = StudentTeam.objects.create(
            name='Archive Plus Pre',
            project_title='Archive Plus Pre',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=self.semester,
            leader=self.student,
            status=StudentTeam.STATUS_APPROVED,
        )
        DeliverableSubmission.objects.create(
            team=team,
            stage_label='Concept Proposal',
            deliverable_id='D1',
            label='D1 - Advisers Acceptance Form',
            deliverable_type=DeliverableSubmission.TYPE_PRE,
            required=True,
            file_name='archive_plus_pre_d1.pdf',
            uploaded_by=self.admin,
        )
        VaultEntry.objects.create(
            entry_type=VaultEntry.TYPE_CAPSTONE,
            file_name='3rdYear.CAP301.ArchivePlusPre.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            team=team,
            team_name=team.name,
            stage_label='Concept Proposal',
            status=VaultEntry.STATUS_APPROVED,
            uploaded_by=self.admin,
        )

        self.client.force_authenticate(user=self.admin)
        response = self.client.get(
            '/api/repository/audit/',
            {
                'type': 'capstone',
                'team_id': str(team.id),
                'view': 'team',
                'stage': 'Concept Proposal',
            },
        )
        self.assertEqual(response.status_code, 200)
        groups = response.data['grouped_by_stage']
        self.assertTrue(groups)
        concept = next(group for group in groups if group['stage'] == 'Concept Proposal')
        pre_names = [row['file_name'] for row in concept['pre_defense']]
        self.assertIn('archive_plus_pre_d1.pdf', pre_names)
        self.assertEqual(len(concept['archive']), 1)

    def test_options_teams_match_team_counts(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/', {'type': 'capstone'})
        self.assertEqual(response.status_code, 200)
        teams = response.data['options']['teams']
        team_counts = response.data['options']['team_counts']
        self.assertEqual(
            {row['id'] for row in teams},
            {row['id'] for row in team_counts},
        )
        for row in teams:
            self.assertIn('level', row)
            self.assertIn('label', row)

    def test_audit_list_paginates_entries(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(
            '/api/repository/audit/',
            {'type': 'capstone', 'limit': '1', 'offset': '0'},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['entries']), 1)
        self.assertIn('pagination', response.data)
        self.assertGreaterEqual(response.data['pagination']['total'], 1)

    def test_audit_trail_endpoint(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get(
            '/api/repository/audit/trail/',
            {
                'entry_type': VaultEntry.TYPE_PIT,
                'source_id': str(self.pit_entry.id),
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn('audit_trail', response.data)

    def test_audit_list_omits_ml_fields_by_default(self):
        self.client.force_authenticate(user=self.admin)
        VaultEntry.objects.filter(pk=self.pit_entry.pk).update(
            extracted_text='long indexed text for search only',
        )
        response = self.client.get('/api/repository/audit/', {'type': 'pit'})
        pit_rows = [e for e in response.data['entries'] if e.get('type') == VaultEntry.TYPE_PIT]
        self.assertTrue(pit_rows)
        self.assertEqual(pit_rows[0].get('extracted_text'), '')

    def test_admin_dashboard_reports_phase_fourteen_repository_counts(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['repository_files'], 4)
        self.assertEqual(response.data['stats']['pending_repository_files'], 0)
        self.assertEqual(response.data['stats']['approved_repository_files'], 3)
        self.assertEqual(response.data['migration']['phase'], 15)

    def test_validate_pit_file_name_accepts_mixed_case_semester(self):
        metadata = validate_pit_file_name(
            '3rdYear.PIT301.CloudFileSyncSystem.1stsemester.pdf',
        )
        self.assertEqual(metadata['semester_label'], '1st Semester')
        self.assertEqual(metadata['year_level'], '3rd Year')

    def test_upload_pit_django_validation_error_returns_400_not_500(self):
        from django.core.exceptions import ValidationError as DjangoValidationError

        self._open_upload_window_for_pit_team()
        self.client.force_authenticate(user=self.pit_lead)
        pdf_bytes = b'%PDF-1.4 test'
        upload_file = SimpleUploadedFile(
            '3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            pdf_bytes,
            content_type='application/pdf',
        )
        message = (
            'Repository uploads open after a PIT event is marked officially complete '
            'in Grade Center.'
        )
        with patch(
            'repository.audit.views.upload_pit_files',
            side_effect=DjangoValidationError(message),
        ):
            response = self.client.post(
                '/api/repository/audit/upload-pit/',
                {'files': upload_file},
                format='multipart',
            )
        self.assertEqual(response.status_code, 400)
        payload = response.data
        if isinstance(payload, dict):
            detail = payload.get('detail')
            if isinstance(detail, list):
                body = ' '.join(str(item) for item in detail)
            else:
                body = str(detail)
        elif isinstance(payload, list):
            body = ' '.join(str(item) for item in payload)
        else:
            body = str(payload)
        self.assertIn('upload', body.lower())
