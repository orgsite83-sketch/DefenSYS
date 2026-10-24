"""Preview/commit parity for shared sheet headers, in the isolated test DB."""
from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.exceptions import ValidationError
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from user_management.academic_records.models import StudentAcademicRecord
from .bulk_import import format_bulk_import_errors
from .models import SectionAssignment, StudentTeam, TeamMembership

User = get_user_model()


class ImportSectionMetadataTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='metadata-admin', role='admin')
        school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(school_year=school_year, label=Semester.FIRST,
            is_active=True, capstone_team_creation_enabled=True,
            capstone_program_phase=Semester.PHASE_CAPSTONE_2)
        self.students = []
        for index in range(8):
            student = User.objects.create_user(username=f'member-{index}', role='student')
            StudentAcademicRecord.objects.create(student=student, semester=self.semester,
                year_level='4th Year', section='BSIT-4A')
            self.students.append(student)
        self.manager = User.objects.create_user(username='manager', role='student',
            first_name='Gabriel', last_name='Navarro')
        StudentAcademicRecord.objects.create(student=self.manager, semester=self.semester,
            year_level='3rd Year', section='')
        self.rows = [{'team_name': f'Team {index + 1}', 'project_title': f'Module {index + 1}',
            'level': StudentTeam.LEVEL_4_CAPSTONE, 'year_level': '4th Year', 'section': 'BSIT-4A',
            'member_ids': [student.username], 'leader_id': student.username,
            'system_name': 'Shared agricultural platform', 'project_manager': self.manager.username}
            for index, student in enumerate(self.students)]
        self.client.force_authenticate(self.admin)

    def post(self, preview=False, rows=None, **extra):
        return self.client.post('/api/teams/bulk-import/' + ('preview/' if preview else ''),
            {'teams': self.rows if rows is None else rows, **extra}, format='json')

    def assert_no_import_writes(self):
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(TeamMembership.objects.exists())
        self.assertFalse(SectionAssignment.objects.exists())

    def enroll_manager(self, **changes):
        StudentAcademicRecord.objects.filter(student=self.manager).update(
            **{'year_level': '4th Year', 'section': 'BSIT-4A', **changes})

    def test_wrong_year_manager_blocks_all_eight_rows_in_preview_and_commit(self):
        preview = self.post(preview=True)
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertEqual(preview.data['summary']['ready'], 0)
        for row in preview.data['rows']:
            self.assertFalse(row['ready'], row)
            self.assertIn('Gabriel Navarro', ' '.join(row['issues']))
            self.assertIn('BSIT-4A, 4th Year', ' '.join(row['issues']))
        self.assert_no_import_writes()
        imported = self.post()
        self.assertEqual(imported.data['created_count'], 0, imported.data)
        self.assertEqual(imported.data['error_count'], 8)
        self.assertNotIn('ErrorDetail', str(imported.data['errors']))
        self.assert_no_import_writes()
        self.assertEqual(StudentAcademicRecord.objects.get(student=self.manager).year_level, '3rd Year')

    def test_top_level_headers_use_the_same_enrollment_validation(self):
        rows = [{key: value for key, value in row.items() if key not in ('section', 'system_name', 'project_manager')}
            for row in self.rows]
        extra = {'section': 'BSIT-4A', 'system_name': 'Shared platform', 'project_manager': 'Gabriel Navarro'}
        preview = self.post(preview=True, rows=rows, **extra)
        self.assertEqual(preview.data['summary']['ready'], 0, preview.data)
        assignment = preview.data['section_assignment']
        self.assertFalse(assignment['project_manager_valid'])
        self.assertIn('BSIT-4A', assignment['project_manager_error'])
        self.assertEqual(self.post(rows=rows, **extra).data['created_count'], 0)
        self.assert_no_import_writes()

    def test_valid_manager_need_not_belong_to_one_of_the_uploaded_teams(self):
        self.enroll_manager()
        preview = self.post(preview=True)
        self.assertEqual(preview.data['summary']['ready'], 8, preview.data)
        self.assert_no_import_writes()
        imported = self.post()
        self.assertEqual(imported.data['created_count'], 8, imported.data)
        self.assertEqual(SectionAssignment.objects.get().project_manager, self.manager)

    def test_manager_joining_in_the_last_row_does_not_depend_on_import_order(self):
        self.enroll_manager(section='')
        self.rows[-1]['member_ids'].append(self.manager.username)
        preview = self.post(preview=True)
        self.assertEqual(preview.data['summary']['ready'], 8, preview.data)
        self.assert_no_import_writes()
        imported = self.post()
        self.assertEqual(imported.data['created_count'], 8, imported.data)
        self.assertEqual(imported.data['imported_rows'], list(range(1, 9)))
        self.assertEqual([team['name'] for team in imported.data['created']],
            [row['team_name'] for row in self.rows])
        self.assertEqual(StudentAcademicRecord.objects.get(student=self.manager).section, 'BSIT-4A')

    def test_inactive_other_section_and_historical_only_managers_are_blocked(self):
        for state in ('inactive', 'other_section', 'historical_only', 'unknown'):
            with self.subTest(state=state):
                self.enroll_manager(section='BSIT-4B' if state == 'other_section' else 'BSIT-4A')
                self.manager.is_active = state != 'inactive'
                self.manager.save(update_fields=['is_active'])
                if state == 'historical_only':
                    historical = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
                    StudentAcademicRecord.objects.filter(student=self.manager).update(semester=historical)
                rows = [{**self.rows[0], 'project_manager': 'Missing Student' if state == 'unknown' else self.manager.username}]
                preview = self.post(preview=True, rows=rows)
                self.assertFalse(preview.data['rows'][0]['ready'], preview.data)
                self.assertEqual(self.post(rows=rows).data['created_count'], 0)
                self.assert_no_import_writes()

    def test_only_the_affected_section_is_blocked(self):
        StudentAcademicRecord.objects.filter(student=self.students[1]).update(section='BSIT-4B')
        independent = {key: value for key, value in self.rows[1].items() if key not in ('system_name', 'project_manager')}
        independent['section'] = 'BSIT-4B'
        rows = [self.rows[0], independent]
        preview = self.post(preview=True, rows=rows, section='BSIT-4A, BSIT-4B')
        self.assertEqual([row['ready'] for row in preview.data['rows']], [False, True], preview.data)
        imported = self.post(rows=rows, section='BSIT-4A, BSIT-4B')
        self.assertEqual(imported.data['imported_rows'], [2], imported.data)
        self.assertEqual(StudentTeam.objects.get().section, 'BSIT-4B')

    def test_headers_on_one_row_apply_to_every_team_in_the_section(self):
        rows = [self.rows[0], {key: value for key, value in self.rows[1].items()
            if key not in ('system_name', 'project_manager')}]
        preview = self.post(preview=True, rows=rows)
        self.assertEqual(preview.data['summary']['ready'], 0, preview.data)
        self.assertEqual(self.post(rows=rows).data['created_count'], 0)
        self.assert_no_import_writes()

    def test_conflicting_section_headers_are_blocked(self):
        self.enroll_manager()
        for field, value in (('project_manager', self.students[0].username), ('system_name', 'Other system')):
            with self.subTest(field=field):
                rows = [self.rows[0], {**self.rows[1], field: value}]
                preview = self.post(preview=True, rows=rows)
                self.assertEqual(preview.data['summary']['ready'], 0, preview.data)
                self.assertIn('Use one', ' '.join(preview.data['rows'][0]['issues']))
                self.assertEqual(self.post(rows=rows).data['created_count'], 0)
                self.assert_no_import_writes()

    def test_inherited_manager_is_checked_when_updating_only_the_system(self):
        SectionAssignment.objects.create(semester=self.semester, year_level='4th Year', section='BSIT-4A',
            project_manager=self.manager, system_name='Old system')
        row = {**self.rows[0], 'project_manager': ''}
        preview = self.post(preview=True, rows=[row])
        self.assertFalse(preview.data['rows'][0]['ready'], preview.data)
        self.assertEqual(self.post(rows=[row]).data['created_count'], 0)
        self.assertEqual(SectionAssignment.objects.get().system_name, 'Old system')
        self.assertFalse(StudentTeam.objects.exists())

    def test_commit_rechecks_a_manager_deactivated_after_preview(self):
        self.enroll_manager()
        self.assertEqual(self.post(preview=True).data['summary']['ready'], 8)
        self.manager.is_active = False
        self.manager.save(update_fields=['is_active'])
        self.assertEqual(self.post().data['created_count'], 0)
        self.assert_no_import_writes()

    def test_transaction_errors_are_readable_and_roll_back_the_team(self):
        self.enroll_manager()
        initial_audits = SystemAuditLog.objects.count()
        with patch('student_teams.views.audit_section', side_effect=ValidationError({
                'project_manager_id': 'Choose an active student enrolled in this section.'})):
            imported = self.post(rows=[self.rows[0]])
        self.assertEqual(imported.data['created_count'], 0, imported.data)
        self.assertEqual(imported.data['errors'][0]['errors'],
            ['project_manager_id: Choose an active student enrolled in this section.'])
        self.assertEqual(SystemAuditLog.objects.count(), initial_audits)
        self.assert_no_import_writes()

    def test_nested_validation_errors_do_not_expose_python_representations(self):
        errors = ValidationError([{'project_manager_id': ['Choose an active student.']}]).detail
        self.assertEqual(format_bulk_import_errors(errors), ['project_manager_id: Choose an active student.'])
