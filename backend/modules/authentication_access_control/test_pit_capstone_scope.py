"""PIT/Capstone isolation regressions. All fixtures use Django's test database."""
from datetime import date

from django.contrib.auth import get_user_model
from django.db import connection
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.scopes import visible_teams_for
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from repository.deliverables.services import team_queryset_for_user
from student_teams.models import SectionAssignment, StudentTeam, TeamMembership
from student_teams.documents.models import TeamDocument
from student_teams.weekly_progress.models import WeeklyProgressReport
from user_management.academic_records.models import StudentAcademicRecord

User = get_user_model()


class PitCapstoneScopeTests(APITestCase):
    @classmethod
    def setUpClass(cls):
        if not str(connection.settings_dict['NAME']).startswith('test_'):
            raise RuntimeError('Audit probes require the isolated Django test database.')
        super().setUpClass()

    def setUp(self):
        school_year = SchoolYear.objects.create(label='2096-2097')
        self.old = Semester.objects.create(school_year=school_year, label=Semester.FIRST)
        self.active = Semester.objects.create(school_year=school_year, label=Semester.SECOND,
            is_active=True, capstone_program_phase=Semester.PHASE_CAPSTONE_1)
        self.lead = User.objects.create_user(username='audit-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='1st Year')
        self.adviser = User.objects.create_user(username='audit-adviser', role='faculty', is_adviser=True)
        self.student = User.objects.create_user(username='audit-student', role='student')
        self.team = self.make_team('B Current Capstone', StudentTeam.LEVEL_3_CAPSTONE,
            self.active, self.student, self.adviser)
        self.record = StudentAcademicRecord.objects.create(student=self.student, semester=self.active,
            year_level='3rd Year', section='BSIT 3A')
        self.report = WeeklyProgressReport.objects.create(student=self.student, team=self.team,
            week_number=1, report_date=date(2097, 2, 1), issues=['Private capstone issue'])
        self.section = SectionAssignment.objects.create(section='BSIT 3A', semester=self.active,
            year_level='3rd Year', system_name='Capstone System')
        self.client.force_authenticate(self.lead)

    def make_team(self, name, level, semester, student, adviser=None):
        team = StudentTeam.objects.create(name=name, level=level,
            year_level=level.split(' PIT')[0].split(' Capstone')[0], semester=semester,
            leader=student, adviser=adviser, section='BSIT 3A')
        TeamMembership.objects.create(team=team, student=student, is_leader=True)
        return team

    def test_pit_lead_cannot_edit_capstone_section_assignment(self):
        response = self.client.patch(f'/api/teams/section-assignments/{self.section.pk}/',
            {'system_name': 'Changed from PIT'}, format='json')
        self.section.refresh_from_db()
        self.assertEqual(self.section.system_name, 'Capstone System',
            f'PIT Lead changed Capstone section: HTTP {response.status_code}')

    def test_pit_lead_cannot_create_other_year_section_assignment(self):
        response = self.client.post('/api/teams/section-assignments/',
            {'section': 'BSIT 2B', 'year_level': '2nd Year', 'system_name': 'Other cohort'}, format='json')
        self.assertFalse(SectionAssignment.objects.filter(section='BSIT 2B', semester=self.active).exists(),
            f'1st Year lead created 2nd Year assignment: HTTP {response.status_code}')

    def test_pit_lead_cannot_list_capstone_weekly_progress(self):
        response = self.client.get('/api/teams/weekly-progress/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['reports'], [], 'PIT Lead can list private Capstone report content')

    def test_pit_lead_cannot_read_capstone_weekly_progress_by_id(self):
        response = self.client.get(f'/api/teams/weekly-progress/{self.report.pk}/')
        self.assertIn(response.status_code, (403, 404), 'PIT Lead can read private Capstone report by ID')

    def test_pit_lead_cannot_download_private_capstone_team_document(self):
        document = TeamDocument.objects.create(team=self.team, uploaded_by=self.adviser,
            file_name='private.txt', file_data=b'private capstone content', file_size=24,
            mime_type='text/plain', document_type='documentation')
        response = self.client.get(f'/api/teams/documents/{document.pk}/download/')
        self.assertIn(response.status_code, (403, 404),
            f'PIT Lead downloaded private Capstone bytes: HTTP {response.status_code}; {response.content}')

    def test_pit_lead_cannot_list_another_pit_year_team_documents(self):
        other_student = User.objects.create_user(username='audit-other-student', role='student')
        team = self.make_team('Other PIT Year', StudentTeam.LEVEL_2_PIT, self.active, other_student)
        document = TeamDocument.objects.create(team=team, uploaded_by=self.adviser,
            file_name='other-year.txt', file_data=b'private', file_size=7, mime_type='text/plain')
        response = self.client.get('/api/teams/documents/', {'team_id': team.pk})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['documents'], [],
            f'1st Year PIT Lead can list 2nd Year document {document.pk}')

    def test_pit_import_cannot_reassign_existing_capstone_student(self):
        response = self.client.post('/api/users/pit-lead/student-import/',
            {'users': [{'id_number': self.student.username, 'role': 'student'}],
             'student_context': {'section': 'BSIT 1A'}}, format='json')
        self.record.refresh_from_db()
        self.assertEqual(self.record.year_level, '3rd Year',
            f'PIT import changed Capstone enrollment: HTTP {response.status_code}; {response.data}')

    def test_pit_audit_mode_blocks_legacy_student_import(self):
        self.lead.pit_lead_year = '3rd Year'
        self.lead.save(update_fields=['pit_lead_year'])
        self.client.force_authenticate(self.lead)
        response = self.client.post('/api/users/pit-lead/student-import/',
            {'users': [{'id_number': self.student.username, 'role': 'student'}],
             'student_context': {'section': 'Changed in audit mode'}}, format='json')
        self.record.refresh_from_db()
        self.assertEqual(self.record.section, 'BSIT 3A',
            f'Legacy PIT import remained writable in audit mode: HTTP {response.status_code}')

    def test_adviser_retains_grade_read_when_also_pit_lead(self):
        stage = DefenseStage.objects.create(label='Audit Capstone Stage')
        grade = TeamGrade.objects.create(team=self.team, semester=self.active, scope='capstone',
            defense_stage=stage, stage_label=stage.label)
        self.client.force_authenticate(self.adviser)
        self.assertEqual(self.client.get(f'/api/grading/grades/{grade.pk}/').status_code, 200)
        self.assertTrue(visible_teams_for(self.adviser).filter(pk=self.team.pk).exists())
        self.adviser.is_pit_lead = True
        self.adviser.pit_lead_year = '1st Year'
        self.adviser.save(update_fields=['is_pit_lead', 'pit_lead_year'])
        self.client.force_authenticate(self.adviser)
        self.assertTrue(team_queryset_for_user(self.adviser).filter(pk=self.team.pk).exists())
        response = self.client.get(f'/api/grading/grades/{grade.pk}/')
        self.assertEqual(response.status_code, 200, 'Adding PIT Lead removed assigned Capstone adviser grade access')

    def test_capstone_wpr_uses_selected_active_team_after_pit_transition(self):
        old_pit = self.make_team('A Historical PIT', StudentTeam.LEVEL_3_PIT, self.old, self.student)
        self.client.force_authenticate(self.student)
        response = self.client.post('/api/teams/weekly-progress/',
            {'team': self.team.pk, 'team_id': self.team.pk, 'week_number': 2,
             'report_date': '2097-02-08'}, format='multipart')
        self.assertEqual(response.status_code, 201,
            f'Active Capstone team rejected due to historical PIT {old_pit.pk}: {response.data}')
        self.assertEqual(response.data['team'], self.team.pk)

    def test_capstone_wpr_does_not_write_to_historical_team(self):
        old_capstone = self.make_team('A Historical Capstone', StudentTeam.LEVEL_3_CAPSTONE,
            self.old, self.student)
        self.client.force_authenticate(self.student)
        response = self.client.post('/api/teams/weekly-progress/',
            {'team': self.team.pk, 'team_id': self.team.pk, 'week_number': 2,
             'report_date': '2097-02-08'}, format='multipart')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['team'], self.team.pk,
            f'Selected active team ignored; report saved to historical Capstone {old_capstone.pk}')

    def test_missing_year_fails_closed_on_management_and_private_reads(self):
        self.lead.pit_lead_year = ''
        self.lead.save()
        self.client.force_authenticate(self.lead)
        self.assertFalse(visible_teams_for(self.lead).exists())
        self.assertEqual(self.client.get('/api/teams/weekly-progress/').data['reports'], [])
        response = self.client.post('/api/teams/section-assignments/',
            {'section': 'BSIT 1B', 'year_level': '1st Year'}, format='json')
        self.assertEqual(response.status_code, 403)

    def test_own_year_section_writes_are_audited_and_historical_writes_denied(self):
        from authentication_access_control.models import SystemAuditLog
        response = self.client.post('/api/teams/section-assignments/',
            {'section': 'BSIT 1B', 'year_level': '1st Year', 'system_name': 'PIT system'}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        section_id = response.data['id']
        self.assertTrue(SystemAuditLog.objects.filter(action='section_assignment.create', actor=self.lead).exists())
        historical = SectionAssignment.objects.create(section='BSIT 1C', year_level='1st Year', semester=self.old)
        self.assertEqual(self.client.patch(f'/api/teams/section-assignments/{historical.pk}/',
            {'system_name': 'No'}, format='json').status_code, 403)
        self.assertEqual(self.client.delete(f'/api/teams/section-assignments/{historical.pk}/').status_code, 403)
        self.assertEqual(self.client.delete(f'/api/teams/section-assignments/{section_id}/').status_code, 204)

    def test_pm_must_belong_to_the_target_section(self):
        admin = User.objects.create_user(username='scope-admin', role='admin')
        self.client.force_authenticate(admin)
        result = self.client.post('/api/teams/section-assignments/',
            {'section': 'BSIT 1B', 'year_level': '1st Year', 'project_manager_id': self.student.pk}, format='json')
        self.assertEqual(result.status_code, 400)
        self.assertFalse(SectionAssignment.objects.filter(section='BSIT 1B').exists())

    def test_adviser_with_lead_role_can_read_but_not_publish_or_edit_capstone_roster(self):
        self.adviser.is_pit_lead, self.adviser.pit_lead_year = True, '1st Year'
        self.adviser.save()
        stage = DefenseStage.objects.create(label='Mixed role concept')
        grade = TeamGrade.objects.create(team=self.team, semester=self.active, scope='capstone', defense_stage=stage, stage_label=stage.label)
        self.client.force_authenticate(self.adviser)
        self.assertEqual(self.client.get(f'/api/grading/grades/{grade.pk}/').status_code, 200)
        self.assertIn(self.client.post(f'/api/grading/grades/{grade.pk}/publish/', {}, format='json').status_code, (403, 404))
        self.assertIn(self.client.patch(f'/api/teams/{self.team.pk}/', {'name': 'Changed'}, format='json').status_code, (403, 404))
        self.team.refresh_from_db()
        self.assertEqual(self.team.name, 'B Current Capstone')

    def test_direct_media_uses_same_private_document_and_wpr_scopes(self):
        from defensys_backend.media_access import can_read_media
        document = TeamDocument.objects.create(team=self.team, uploaded_by=self.adviser, file='scope/private.pdf',
            file_name='private.pdf', file_size=3, mime_type='application/pdf')
        self.report.report_file = 'scope/private-weekly.pdf'
        self.report.save()
        self.assertFalse(can_read_media(self.lead, document.file.name))
        self.assertFalse(can_read_media(self.lead, self.report.report_file.name))
        self.assertTrue(can_read_media(self.adviser, document.file.name))
        self.assertTrue(can_read_media(self.adviser, self.report.report_file.name))
        self.assertTrue(can_read_media(self.student, document.file.name))

    def test_document_upload_and_delete_cannot_bypass_scope_or_history(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        document = TeamDocument.objects.create(team=self.team, uploaded_by=self.lead,
            file_name='private.txt', file_data=b'private', file_size=7)
        self.assertEqual(self.client.delete(f'/api/teams/documents/{document.pk}/').status_code, 403)
        result = self.client.post('/api/teams/documents/upload/', {'team_id': self.team.pk,
            'file': SimpleUploadedFile('probe.txt', b'probe'), 'document_type': 'other'}, format='multipart')
        self.assertEqual(result.status_code, 403)
        self.client.force_authenticate(self.student)
        self.team.semester = self.old
        self.team.save()
        self.assertEqual(self.client.delete(f'/api/teams/documents/{document.pk}/').status_code, 403)

    def test_wpr_cannot_move_to_pit_or_write_a_historical_report(self):
        self.client.force_authenticate(self.student)
        pit = self.make_team('PIT', StudentTeam.LEVEL_1_PIT, self.active, self.student)
        response = self.client.put(f'/api/teams/weekly-progress/{self.report.pk}/',
            {'team': pit.pk, 'report_date': '2097-02-01', 'week_number': 1}, format='json')
        self.assertEqual(response.status_code, 400)
        self.report.refresh_from_db()
        self.assertEqual(self.report.team_id, self.team.pk)
        self.team.semester = self.old
        self.team.save()
        self.assertEqual(self.client.delete(f'/api/teams/weekly-progress/{self.report.pk}/').status_code, 403)

    def test_wpr_rejects_conflicting_or_ambiguous_team_identity(self):
        self.client.force_authenticate(self.student)
        other = self.make_team('C Second Capstone', StudentTeam.LEVEL_3_CAPSTONE, self.active, self.student)
        for data in ({'team_id': self.team.pk, 'team': other.pk}, {}):
            response = self.client.post('/api/teams/weekly-progress/',
                {**data, 'week_number': 2, 'report_date': '2097-02-08'}, format='multipart')
            self.assertEqual(response.status_code, 400)

    def test_official_import_does_not_change_out_of_scope_profile_or_assign_instructor(self):
        from user_management.models import SectionInstructorAssignment
        self.adviser.first_name, self.adviser.last_name = 'Scope', 'Instructor'
        self.adviser.save()
        self.student.first_name = 'Original'
        self.student.save()
        response = self.client.post('/api/users/pit-lead/official-class-list-import/',
            {'metadata': {'section': 'BSIT 1B', 'year_level': '1st Year', 'instructor': 'Scope Instructor'},
             'students': [{'id_number': self.student.username, 'full_name': 'Changed, Student', 'email': 'changed@example.com'}]}, format='json')
        self.assertIn(response.status_code, (200, 201), response.data)
        self.student.refresh_from_db()
        self.record.refresh_from_db()
        self.assertEqual(self.student.first_name, 'Original')
        self.assertEqual(self.record.year_level, '3rd Year')
        self.assertFalse(SectionInstructorAssignment.objects.filter(section='BSIT 1B').exists())

    def test_own_year_pit_lead_and_assigned_adviser_keep_private_document_reads(self):
        student = User.objects.create_user(username='own-year-student', role='student')
        team = self.make_team('Own PIT', StudentTeam.LEVEL_1_PIT, self.active, student, self.adviser)
        document = TeamDocument.objects.create(team=team, uploaded_by=student,
            file_name='own.txt', file_data=b'own', file_size=3)
        self.assertEqual(self.client.get(f'/api/teams/documents/{document.pk}/download/').status_code, 200)
        self.client.force_authenticate(self.adviser)
        self.assertEqual(self.client.get(f'/api/teams/documents/{document.pk}/download/').status_code, 200)

    def test_integrity_audit_reports_candidates_without_repairing_records(self):
        import importlib.util
        from pathlib import Path
        script = Path(__file__).resolve().parents[3] / 'execution' / 'audit_pit_capstone_integrity.py'
        spec = importlib.util.spec_from_file_location('integrity_audit', script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.record.year_level = '1st Year'
        self.record.save()
        findings = module.collect_findings()
        self.assertIn('enrollment_membership_mismatch', findings['counts'])
        self.assertFalse(findings['automatic_repairs'])
        self.record.refresh_from_db()
        self.assertEqual(self.record.year_level, '1st Year')

    def test_rejected_bulk_team_rows_cannot_rewrite_capstone_section_metadata(self):
        response = self.client.post('/api/teams/bulk-import/',
            {'section': self.section.section, 'system_name': 'Cross-scope change',
             'project_manager': self.student.username,
             'teams': [{'team_name': 'Invalid PIT import', 'member_ids': [self.student.username], 'leader_id': self.student.username}]}, format='json')
        self.section.refresh_from_db()
        self.assertEqual(response.data['created_count'], 0, response.data)
        self.assertEqual(self.section.year_level, '3rd Year')
        self.assertEqual(self.section.system_name, 'Capstone System')

    def test_pit_import_checks_capstone_leadership_when_legacy_membership_is_missing(self):
        self.record.delete()
        TeamMembership.objects.filter(team=self.team, student=self.student).delete()
        self.client.post('/api/users/pit-lead/student-import/',
            {'users': [{'id_number': self.student.username, 'role': 'student'}],
             'student_context': {'section': 'BSIT 1A'}}, format='json')
        self.assertFalse(StudentAcademicRecord.objects.filter(student=self.student, semester=self.active).exists())
