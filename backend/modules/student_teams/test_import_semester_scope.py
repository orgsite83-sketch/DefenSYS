from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from user_management.academic_records.models import StudentAcademicRecord
from .models import StudentCapstoneParticipation, SectionAssignment, StudentTeam


class ImportSemesterScopeTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.admin = User.objects.create_user(username='import-scope-admin', role='admin')
        self.student = User.objects.create_user(username='import-scope-student', role='student',
            first_name='Gabriel', last_name='Navarro')
        self.adviser = User.objects.create_user(username='import-scope-adviser', role='faculty',
            first_name='Eduardo', last_name='Padilla', is_adviser=True)
        year = SchoolYear.objects.create(label='2025-2026')
        self.first = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True,
            capstone_team_creation_enabled=True)
        self.second = Semester.objects.create(school_year=year, label=Semester.SECOND,
            capstone_team_creation_enabled=True)
        for term in (self.first, self.second):
            StudentAcademicRecord.objects.create(student=self.student, semester=term,
                year_level='3rd Year', section='BSIT-3A')
        self.client.force_authenticate(self.admin)
        self.row = {'team_name': 'Team AgriPulse', 'project_title': 'Soil Sensor',
            'year_level': '3rd Year', 'section': 'BSIT-3A', 'member_ids': ['Gabriel Navarro'],
            'leader_id': 'Gabriel Navarro', 'adviser_name': 'Eduardo Padilla',
            'instructor_name': '', 'group_key': 'file0/shared/team1',
            'system_name': 'Agro Platform', 'project_manager': 'Gabriel Navarro',
            'project_kind': 'module'}
        self.columns = ['team_name', 'project_title', 'level', 'year_level', 'member_ids',
            'leader_id', 'adviser_name', 'instructor_name', 'section', 'system_name',
            'project_manager', 'group_key', 'project_kind']

    def activate_second(self):
        self.second.is_active = True
        self.second.save(update_fields=['is_active'])

    def test_neutral_import_rows_use_active_semester_without_creating_history(self):
        for term, expected in ((self.first, '3rd Year PIT'), (self.second, '3rd Year Capstone')):
            if term == self.second:
                self.activate_second()
            response = self.client.post('/api/teams/bulk-import/preview/',
                {'teams': [self.row], 'csv_columns': self.columns}, format='json')
            self.assertEqual(response.status_code, 200, response.data)
            row = response.data['rows'][0]
            self.assertTrue(row['ready'], row['issues'])
            self.assertEqual(row['level'], expected)
        self.assertEqual(StudentTeam.objects.count(), 0)
        self.assertEqual(StudentCapstoneParticipation.objects.count(), 0)

    def test_explicit_pit_scope_is_not_silently_converted_to_capstone(self):
        self.activate_second()
        response = self.client.post('/api/teams/bulk-import/preview/',
            {'teams': [{**self.row, 'level': '3rd Year PIT'}], 'csv_columns': self.columns}, format='json')
        row = response.data['rows'][0]
        self.assertFalse(row['ready'])
        self.assertIn('Capstone intake scope', str(row['issues']))

    def test_full_module_payload_preview_and_commit_preserve_shared_details(self):
        self.activate_second()
        body = {'teams': [self.row], 'csv_columns': self.columns}
        preview = self.client.post('/api/teams/bulk-import/preview/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['rows'][0]['ready'], preview.data)
        self.assertEqual(preview.data['rows'][0]['group_key'], self.row['group_key'])
        self.assertEqual(preview.data['section_summaries'][0]['system_name'], 'Agro Platform')
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(SectionAssignment.objects.exists())
        imported = self.client.post('/api/teams/bulk-import/', body, format='json')
        self.assertEqual(imported.status_code, 201, imported.data)
        self.assertEqual(imported.data['created_count'], 1, imported.data)
        self.assertEqual(imported.data['error_count'], 0, imported.data)
        team = StudentTeam.objects.get()
        self.assertEqual(team.level, '3rd Year Capstone')
        self.assertEqual(team.project_title, 'Soil Sensor')
        self.assertEqual(team.adviser_id, self.adviser.pk)
        self.assertEqual(list(team.memberships.values_list('student_id', flat=True)), [self.student.pk])
        assignment = SectionAssignment.objects.get(semester=self.second, section='BSIT-3A')
        self.assertEqual(assignment.system_name, 'Agro Platform')
        self.assertEqual(assignment.project_manager_id, self.student.pk)

    def test_invalid_project_kind_and_unrecognized_columns_remain_blocked(self):
        self.activate_second()
        for extra in ({'project_kind': 'unsupported'}, {'unrecognized_column': 'value'}):
            with self.subTest(extra=extra):
                body = {'teams': [{**self.row, **extra}], 'csv_columns': self.columns}
                preview = self.client.post('/api/teams/bulk-import/preview/', body, format='json')
                self.assertFalse(preview.data['rows'][0]['ready'])
                issue = ' '.join(preview.data['rows'][0]['issues'])
                self.assertIn(next(iter(extra)), issue)
                self.assertNotIn('non_field_errors', issue)
                result = self.client.post('/api/teams/bulk-import/', body, format='json')
                self.assertEqual(result.data['created_count'], 0, result.data)
        self.assertFalse(StudentTeam.objects.exists())
