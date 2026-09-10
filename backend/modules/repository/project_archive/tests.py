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
from repository.archive.models import ArchiveEntry
from student_teams.models import StudentTeam, TeamMembership
from .models import ProjectArchiveLog

RepositoryAuditLog = ProjectArchiveLog
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
            project_title='Secure Archive Search',
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
            deliverable_type=DeliverableSubmission.TYPE_POST,
            required=False,
            file_name='Team_Cipher_Source_Code.zip',
            uploaded_by=self.admin,
        )
        self.pit_entry = ArchiveEntry.objects.create(
            entry_type=ArchiveEntry.TYPE_PIT,
            file_name='3rdYear.PIT301.CloudFileSyncSystem.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            status=ArchiveEntry.STATUS_APPROVED,
            uploaded_by=self.pit_lead,
        )
        ArchiveEntry.objects.create(
            file_name='2ndYear.PIT201.CampusSocialNetwork.1stSemester.pdf',
            academic_year='2026-2027',
            status=ArchiveEntry.STATUS_APPROVED,
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

        pit_count_before = ArchiveEntry.objects.filter(entry_type=ArchiveEntry.TYPE_PIT).count()
        upload = self.client.post(
            '/api/repository/audit/upload-pit/',
            {'file_names': [self.pit_entry.file_name]},
            format='json',
        )
        self.assertEqual(upload.status_code, 403)
        self.assertEqual(
            ArchiveEntry.objects.filter(entry_type=ArchiveEntry.TYPE_PIT).count(),
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

    def test_pit_upload_does_not_publish_grade_after_archive(self):
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
        self.assertEqual(response.status_code, 403)

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

    def test_pit_upload_is_forbidden(self):
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

        self.assertEqual(response.status_code, 403)

    def test_multipart_pit_upload_is_forbidden(self):
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

        self.assertEqual(response.status_code, 403)

    def test_audit_search_matches_pdf_topics(self):
        ArchiveEntry.objects.filter(pk=self.pit_entry.pk).update(
            extracted_text='Smart campus navigation with flutter mobile sensors',
            topics=['flutter', 'campus', 'navigation'],
            category='Mobile Development',
            status=ArchiveEntry.STATUS_APPROVED,
        )
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/', {'search': 'flutter'})
        self.assertEqual(response.status_code, 200)
        file_names = [entry['file_name'] for entry in response.data['entries']]
        self.assertIn(self.pit_entry.file_name, file_names)

    def test_pit_lead_and_admin_override_update_pit_status_and_logs(self):
        # A non-PIT lead faculty is forbidden
        regular_faculty = User.objects.create_user(username='fac1', password='pass12345', role='faculty', is_pit_lead=False)
        self.client.force_authenticate(user=regular_faculty)
        forbidden = self.client.post(
            '/api/repository/audit/override-status/',
            {'entry_id': f'pit-{self.pit_entry.id}', 'status': ArchiveEntry.STATUS_NEEDS_REVISION},
            format='json',
        )
        self.assertEqual(forbidden.status_code, 403)

        # PIT lead for the entry's year level can override
        self.client.force_authenticate(user=self.pit_lead)
        pit_lead_override = self.client.post(
            '/api/repository/audit/override-status/',
            {'entry_id': f'pit-{self.pit_entry.id}', 'status': ArchiveEntry.STATUS_NEEDS_REVISION},
            format='json',
        )
        self.assertEqual(pit_lead_override.status_code, 200)

        # Admin can override
        self.client.force_authenticate(user=self.admin)
        override = self.client.post(
            '/api/repository/audit/override-status/',
            {'entry_id': f'pit-{self.pit_entry.id}', 'status': ArchiveEntry.STATUS_APPROVED},
            format='json',
        )
        self.assertEqual(override.status_code, 200)
        self.pit_entry.refresh_from_db()
        self.assertEqual(self.pit_entry.status, ArchiveEntry.STATUS_APPROVED)
        self.assertEqual(RepositoryAuditLog.objects.filter(source_id=self.pit_entry.id).count(), 2)

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
        self.assertFalse(response.data['scope']['can_upload_capstone'])
        self.assertEqual(len(response.data['capstone_upload_window']['queue']), 1)
        self.assertIn(
            'SecureArchiveSearch',
            response.data['capstone_upload_window']['queue'][0]['suggested_file_name'],
        )

    def test_capstone_upload_is_forbidden(self):
        self._open_capstone_upload_window()
        self.client.force_authenticate(user=self.admin)
        file_name = '3rdYear.CAP301.SecureArchiveSearch.1stSemester.pdf'
        upload = self.client.post(
            '/api/repository/audit/upload-capstone/',
            {'file_names': [file_name]},
            format='json',
        )
        self.assertEqual(upload.status_code, 403)

    def test_submission_kind_pre_excludes_archive(self):
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
        self.assertNotIn('archive_pdf', response.data['counts'])
        self.assertIn('archive_submissions', response.data['counts'])

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
        self.assertIn('post', first)
        self.assertNotIn('archive', first)

    def test_capstone_entries_include_submission_kind(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/audit/', {'type': 'capstone'})
        capstone_rows = [
            entry
            for entry in response.data['entries']
            if entry.get('submission_kind') in ('pre', 'post')
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
        ArchiveEntry.objects.create(
            entry_type=ArchiveEntry.TYPE_PIT,
            file_name='3rdYear.PIT301.SmartCampusNavigator.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            team=pit_team,
            team_name=pit_team.name,
            status=ArchiveEntry.STATUS_APPROVED,
            uploaded_by=self.pit_lead,
        )
        ArchiveEntry.objects.create(
            entry_type=ArchiveEntry.TYPE_CAPSTONE,
            file_name='3rdYear.CAP301.SmartCampusNavigator.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            team=capstone_team,
            team_name=capstone_team.name,
            stage_label='Concept Proposal',
            status=ArchiveEntry.STATUS_APPROVED,
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

    def test_grouped_by_stage_includes_pre_when_archive_entry_exists(self):
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
        ArchiveEntry.objects.create(
            entry_type=ArchiveEntry.TYPE_CAPSTONE,
            file_name='3rdYear.CAP301.ArchivePlusPre.1stSemester.pdf',
            year_level='3rd Year',
            academic_year='2026-2027',
            team=team,
            team_name=team.name,
            stage_label='Concept Proposal',
            status=ArchiveEntry.STATUS_APPROVED,
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
        self.assertEqual(len(concept['post']), 1)

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
                'entry_type': ArchiveEntry.TYPE_PIT,
                'source_id': str(self.pit_entry.id),
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn('audit_trail', response.data)

    def test_audit_list_omits_ml_fields_by_default(self):
        self.client.force_authenticate(user=self.admin)
        ArchiveEntry.objects.filter(pk=self.pit_entry.pk).update(
            extracted_text='long indexed text for search only',
        )
        response = self.client.get('/api/repository/audit/', {'type': 'pit'})
        pit_rows = [e for e in response.data['entries'] if e.get('type') == ArchiveEntry.TYPE_PIT]
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
            'repository.project_archive.views.upload_pit_files',
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

    def test_upload_pit_custom_template_filename_matches(self):
        # 1. Open upload window
        self._open_upload_window_for_pit_team(event_name='3rd Year Expo')
        
        # 2. Get the config and set a custom template
        config = PitEventGradingConfig.objects.get(event_name='3rd Year Expo')
        config.archive_file_template = '{year}{course}{project}{semester}{event}'
        config.save()

        # Configure the deliverable template for this PIT event
        from defense.scheduler.models import PitEventDeliverable
        PitEventDeliverable.objects.create(
            pit_event_config=config,
            deliverable_id='PIT_D1',
            label='PIT Project Poster',
            deliverable_type=PitEventDeliverable.TYPE_POST,
            required=True,
        )

        # Create student for the PIT team to resolve permissions
        pit_student = User.objects.create_user(
            username='pit-student-1',
            password='pass12345',
            role='student',
        )
        TeamMembership.objects.create(team=self.pit_team, student=pit_student, is_leader=True)

        # 3. Authenticate as the PIT Student
        self.client.force_authenticate(user=pit_student)

        # 4. Upload file with custom template filename format
        # Expected filename is 3rdYearPIT301CloudFileSyncSystem1stSemester3rdYearExpo.pdf
        pdf_bytes = b'%PDF-1.4 custom template test'
        upload_file = SimpleUploadedFile(
            '3rdYearPIT301CloudFileSyncSystem1stSemester3rdYearExpo.pdf',
            pdf_bytes,
            content_type='application/pdf',
        )

        response = self.client.post(
            '/api/repository/deliverables/upload/',
            {
                'team_id': self.pit_team.id,
                'stage_label': '3rd Year Expo',
                'deliverable_id': 'PIT_D1',
                'file_name': '3rdYearPIT301CloudFileSyncSystem1stSemester3rdYearExpo.pdf',
                'file': upload_file,
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, 200)
        submission = DeliverableSubmission.objects.get(deliverable_id='PIT_D1')
        self.assertEqual(submission.file_name, '3rdYearPIT301CloudFileSyncSystem1stSemester3rdYearExpo.pdf')

    def test_capstone_4th_year_template_and_regex_resolution(self):
        from .services import resolve_archive_file_template, validate_capstone_file_name

        team_4th = StudentTeam.objects.create(
            name='Team Titan',
            project_title='AI Core Platform',
            level=StudentTeam.LEVEL_4_CAPSTONE,
            year_level='4th Year',
            semester=self.semester,
            leader=self.student,
        )

        resolved = resolve_archive_file_template(
            '{year}.{course}.{project}.{semester}.pdf',
            team_4th,
            stage_label='Final Defense',
            semester_label='1st Semester',
        )
        self.assertEqual(resolved, '4thYear.CAP401.AICorePlatform.1stSemester.pdf')

        validated = validate_capstone_file_name(resolved)
        self.assertEqual(validated['prefix'], '4thYear')
        self.assertEqual(validated['year_level'], '4th Year')
        self.assertEqual(validated['course_code'], 'CAP401')
        self.assertEqual(validated['project_slug'], 'AICorePlatform')

    def test_replace_archive_file_endpoint(self):
        entry = ArchiveEntry.objects.create(
            file_name='old_file.pdf',
            entry_type=ArchiveEntry.TYPE_PIT,
            status='Approved',
        )
        self.client.force_authenticate(user=self.admin)
        new_file = SimpleUploadedFile('new_replacement.pdf', b'PDF content here', content_type='application/pdf')
        response = self.client.post(
            '/api/repository/audit/replace-file/',
            {
                'entry_id': f'pit-{entry.id}',
                'file': new_file,
            },
            format='multipart',
        )
        self.assertEqual(response.status_code, 200)
        entry.refresh_from_db()
        self.assertEqual(entry.file_name, 'new_replacement.pdf')
        self.assertEqual(entry.status, 'Approved')

    def test_request_resubmission_endpoint(self):
        entry = ArchiveEntry.objects.create(
            file_name='test_submission.pdf',
            entry_type=ArchiveEntry.TYPE_PIT,
            status='Approved',
        )
        self.client.force_authenticate(user=self.admin)
        response = self.client.post(
            '/api/repository/audit/request-resubmission/',
            {
                'entry_id': f'pit-{entry.id}',
                'status': 'Needs Revision',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        entry.refresh_from_db()
        self.assertEqual(entry.status, 'Needs Revision')

    def test_request_resubmission_deliverable_submission_file_target(self):
        from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
        submission, _ = DeliverableSubmission.objects.get_or_create(
            team=self.capstone_team,
            stage_label='Concept Proposal',
            deliverable_id='D99',
            defaults={
                'label': 'Adviser Acceptance Form',
                'deliverable_type': 'pre',
                'status': 'accepted',
            },
        )
        sub_file = DeliverableSubmissionFile.objects.create(
            submission=submission,
            file_name='acceptance.pdf',
        )
        self.client.force_authenticate(user=self.admin)
        response = self.client.post(
            '/api/repository/audit/request-resubmission/',
            {
                'entry_id': f'capstone-{submission.id}-{sub_file.id}',
                'status': 'Needs Revision',
                'feedback': 'Fix Chapter 3',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        submission.refresh_from_db()
        self.assertEqual(submission.status, DeliverableSubmission.STATUS_REJECTED)
        self.assertIn('Fix Chapter 3', submission.feedback)

    def test_pit_lead_can_resubmit_and_replace_file_for_assigned_year(self):
        # 3rd Year PIT entry managed by self.pit_lead (whose pit_lead_year is '3rd Year')
        entry_3rd = ArchiveEntry.objects.create(
            file_name='3rd_year_project.pdf',
            entry_type=ArchiveEntry.TYPE_PIT,
            year_level='3rd Year',
            status='Approved',
        )
        self.client.force_authenticate(user=self.pit_lead)

        # 1. Request resubmission for 3rd year entry
        response = self.client.post(
            '/api/repository/audit/request-resubmission/',
            {
                'entry_id': f'pit-{entry_3rd.id}',
                'status': 'Needs Revision',
                'feedback': 'Please fix title page formatting',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        entry_3rd.refresh_from_db()
        self.assertEqual(entry_3rd.status, 'Needs Revision')

        # 2. Replace file for 3rd year entry
        replacement = SimpleUploadedFile('3rd_year_fixed.pdf', b'PDF 3rd year content', content_type='application/pdf')
        replace_resp = self.client.post(
            '/api/repository/audit/replace-file/',
            {
                'entry_id': f'pit-{entry_3rd.id}',
                'file': replacement,
            },
            format='multipart',
        )
        self.assertEqual(replace_resp.status_code, 200)
        entry_3rd.refresh_from_db()
        self.assertEqual(entry_3rd.file_name, '3rd_year_fixed.pdf')

    def test_pit_lead_forbidden_from_overriding_capstone_or_other_year_entries(self):
        # 2nd Year PIT entry (outside self.pit_lead's '3rd Year' scope)
        entry_2nd = ArchiveEntry.objects.create(
            file_name='2nd_year_project.pdf',
            entry_type=ArchiveEntry.TYPE_PIT,
            year_level='2nd Year',
            status='Approved',
        )
        # Capstone submission
        capstone_sub = DeliverableSubmission.objects.create(
            team=self.capstone_team,
            stage_label='Concept Proposal',
            deliverable_id='D100',
            label='Capstone Document',
            deliverable_type='pre',
            status='accepted',
        )

        self.client.force_authenticate(user=self.pit_lead)

        # Attempt override on 2nd year entry -> PermissionDenied
        resub_2nd = self.client.post(
            '/api/repository/audit/request-resubmission/',
            {
                'entry_id': f'pit-{entry_2nd.id}',
                'status': 'Needs Revision',
            },
            format='json',
        )
        self.assertEqual(resub_2nd.status_code, 403)

        # Attempt override on Capstone submission -> PermissionDenied
        resub_cap = self.client.post(
            '/api/repository/audit/request-resubmission/',
            {
                'entry_id': f'capstone-{capstone_sub.id}',
                'status': 'Needs Revision',
            },
            format='json',
        )
        self.assertEqual(resub_cap.status_code, 403)

    def test_export_csv_admin(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/repository/project-archive/export/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['Content-Type'], 'text/csv; charset=utf-8')
        content = response.content.decode('utf-8')
        self.assertIn('Type,File Name,Team,Year Level,Academic Year,Semester,Stage,Status,Uploaded By,Uploaded At', content)

    def test_export_csv_pit_lead_restricted(self):
        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.get('/api/repository/project-archive/export/?type=capstone')
        self.assertEqual(response.status_code, 200)
        content = response.content.decode('utf-8')
        # PIT lead should not get capstone records
        self.assertNotIn('Capstone,', content)



