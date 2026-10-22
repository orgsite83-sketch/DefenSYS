from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from user_management.models import SectionInstructorAssignment
from user_management.academic_records.models import StudentAcademicRecord
from .models import StudentTeam, TeamAdviserAssignment

User = get_user_model()


class PitImportInstructorTests(APITestCase):
    def setUp(self):
        self.lead = User.objects.create_user(username='pit-lead', role='faculty', is_pit_lead=True, pit_lead_year='1st Year')
        self.instructor = User.objects.create_user(username='eduardo', role='faculty', first_name='Eduardo', last_name='Padilla')
        year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        for username in ('1065', '1066'):
            student = User.objects.create_user(username=username, role='student')
            StudentAcademicRecord.objects.create(student=student, semester=self.semester, year_level='1st Year', section='BSIT-1A')
        self.client.force_authenticate(self.lead)
        self.row = {
            'team_name': 'Team DevCraft', 'project_title': 'Campus Directory',
            'level': StudentTeam.LEVEL_1_PIT, 'year_level': '1st Year', 'section': 'BSIT-1A',
            'member_ids': ['1065', '1066'], 'leader_id': '1065', 'instructor_name': 'Eduardo Padilla',
        }

    def post_rows(self, preview=False, rows=None):
        return self.client.post('/api/teams/bulk-import/' + ('preview/' if preview else ''), {
            'teams': rows or [self.row], 'csv_columns': ['Team Name', 'PIT Project', 'Section', 'Instructor', 'Team Members'],
        }, format='json')

    def test_preview_preserves_instructor_without_warnings_or_writes(self):
        response = self.post_rows(preview=True)
        self.assertEqual(response.status_code, 200)
        row = response.data['rows'][0]
        self.assertTrue(row['ready'], row['issues'])
        self.assertEqual(row['instructor_name'], 'Eduardo Padilla')
        self.assertEqual(row['adviser_name'], '')
        self.assertEqual(row['warnings'], [])
        self.assertFalse(SectionInstructorAssignment.objects.exists())
        self.instructor.refresh_from_db()
        self.assertFalse(self.instructor.is_adviser)

    def test_normalized_file_headers_allow_pit_preview_and_import(self):
        body = {'teams': [self.row], 'csv_columns': [
            'team_name', 'project_title', 'level', 'year_level', 'member_ids', 'leader_id',
            'adviser_name', 'instructor_name', 'section', 'system_name', 'project_manager', 'group_key']}
        preview = self.client.post('/api/teams/bulk-import/preview/', body, format='json')
        self.assertTrue(preview.data['rows'][0]['ready'], preview.data)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(SectionInstructorAssignment.objects.exists())
        imported = self.client.post('/api/teams/bulk-import/', body, format='json')
        self.assertEqual(imported.data['created_count'], 1, imported.data)
        self.assertEqual(SectionInstructorAssignment.objects.get().faculty, self.instructor)
        self.assertIsNone(StudentTeam.objects.get().adviser)

    def test_import_saves_section_instructor_without_adviser(self):
        response = self.post_rows()
        self.assertEqual(response.data['created_count'], 1, response.data)
        self.assertEqual(response.data['created'][0]['instructor_name'], 'Eduardo Padilla')
        self.assertEqual(SectionInstructorAssignment.objects.get().faculty, self.instructor)
        self.assertIsNone(StudentTeam.objects.get().adviser)
        self.assertFalse(TeamAdviserAssignment.objects.exists())
        self.instructor.refresh_from_db()
        self.assertFalse(self.instructor.is_adviser)

    def test_existing_assignment_is_reused(self):
        SectionInstructorAssignment.objects.create(faculty=self.instructor, semester=self.semester, year_level='1st Year', section='BSIT-1A')
        response = self.post_rows()
        self.assertEqual(response.data['created_count'], 1, response.data)
        self.assertEqual(SectionInstructorAssignment.objects.count(), 1)

    def test_invalid_instructors_block_preview_and_commit(self):
        self.instructor.is_active = False
        self.instructor.save(update_fields=['is_active'])
        for reference in ('Unknown Faculty', '1065', 'Eduardo Padilla'):
            with self.subTest(reference=reference):
                self.row['instructor_name'] = reference
                preview = self.post_rows(preview=True)
                self.assertFalse(preview.data['rows'][0]['ready'])
                result = self.post_rows()
                self.assertEqual(result.data['created_count'], 0)
                self.assertTrue(result.data['errors'])
        self.assertFalse(SectionInstructorAssignment.objects.exists())
        self.assertFalse(StudentTeam.objects.exists())

    def test_real_adviser_input_still_warns_for_pit(self):
        self.row['adviser_name'] = 'Eduardo Padilla'
        response = self.post_rows(preview=True)
        self.assertTrue(response.data['rows'][0]['ready'])
        self.assertTrue(any('PIT teams do not have advisers' in warning for warning in response.data['rows'][0]['warnings']))
