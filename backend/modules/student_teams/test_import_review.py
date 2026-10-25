"""Import projections use the isolated test DB and never establish enrollment."""
from rest_framework.test import APITestCase
from user_management.academic_records.models import StudentAcademicRecord
from . import test_formation as fixtures
from .models import SectionAssignment, StudentTeam


class ImportReviewTests(APITestCase):
    setUp = fixtures.TeamFormationTests.setUp

    def rows(self):
        return [{'group_key': f'source/{i}', 'team_name': f'Team {i}',
            'project_title': '', 'member_ids': [student.username],
            'leader_id': student.username, 'section': 'BSIT-2A',
            'level': '2nd Year PIT', 'year_level': '2nd Year'}
            for i, student in enumerate(self.students[:8])]

    def review(self, rows, **extra):
        response = self.client.post('/api/teams/rosters/preview/', {
            'workspace': 'instructor', 'year_level': '2nd Year', 'section': 'BSIT-2A',
            'operation': 'import', 'validation_only': True, 'teams': rows, **extra}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def test_all_team_issues_are_returned_with_stable_keys_without_writes_or_token(self):
        rows = self.rows()
        rows[0]['member_ids'] = ['Unknown Student']
        rows[1]['leader_id'] = self.students[2].username
        rows[2]['member_ids'] = [self.students[3].username]
        rows[2]['leader_id'] = self.students[3].username
        before = list(StudentAcademicRecord.objects.values_list('id', 'section'))
        result = self.review(rows)
        self.assertFalse(result['ready'])
        self.assertEqual([r['group_key'] for r in result['rows']], [r['group_key'] for r in rows])
        self.assertTrue(all(result['rows'][i]['issues'] for i in range(4)))
        self.assertTrue(result['rows'][4]['ready'])
        self.assertNotIn('preview_token', result)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(SectionAssignment.objects.exists())
        self.assertEqual(list(StudentAcademicRecord.objects.values_list('id', 'section')), before)

    def test_shared_manager_failure_blocks_section_and_has_visible_summary(self):
        rows = self.rows()
        for row in rows:
            row.update(system_name='Societree', project_manager=self.students[12].username)
        result = self.review(rows)
        self.assertTrue(all(not row['ready'] for row in result['rows']))
        summary = result['section_summaries'][0]
        self.assertEqual(summary['system_name'], 'Societree')
        self.assertEqual(summary['project_manager_username'], self.students[12].username)
        self.assertTrue(summary['issues'])
        self.assertEqual(summary['team_count'], 8)

    def test_ready_shared_details_are_returned_in_both_validation_and_confirmation(self):
        rows = self.rows()
        rows[0].update(system_name='Societree', project_manager=self.students[0].username)
        result = self.review(rows)
        self.assertTrue(result['ready'], result)
        self.assertEqual(result['section_summaries'][0]['project_manager_username'], self.students[0].username)
        response = self.client.post('/api/teams/rosters/preview/', {
            'workspace': 'instructor', 'year_level': '2nd Year', 'section': 'BSIT-2A',
            'operation': 'import', 'teams': rows}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIn('preview_token', response.data)
        self.assertEqual(response.data['section_summaries'], result['section_summaries'])

    def test_legacy_instructor_assignment_is_not_silently_dropped(self):
        rows = self.rows()
        rows[3]['instructor_name'] = self.admin.username
        result = self.review(rows)
        self.assertFalse(result['rows'][3]['ready'])
        self.assertIn('another instructor', ' '.join(result['rows'][3]['issues']))
        self.assertTrue(result['rows'][0]['ready'])

    def test_unsectioned_student_is_ready_with_a_note_without_warnings_or_enrollment_writes(self):
        for section in ('', 'BSIT', 'bsit'):
            with self.subTest(section=section):
                StudentAcademicRecord.objects.filter(student=self.students[0]).update(section=section)
                result = self.review(self.rows())
                self.assertTrue(result['ready'])
                self.assertTrue(result['rows'][0]['ready'])
                self.assertEqual(result['rows'][0]['warnings'], [])
                self.assertEqual(result['rows'][0]['notes'], [
                    '1 student will be assigned to BSIT-2A when this roster is applied.'])
                self.assertEqual(result['summary'], {'ready': 8, 'warnings': 0, 'issues': 0})
                self.assertEqual(StudentAcademicRecord.objects.get(student=self.students[0]).section, section)
                self.assertFalse(StudentTeam.objects.exists())

    def test_already_assigned_students_need_no_section_assignment_note(self):
        result = self.review(self.rows())
        self.assertTrue(result['ready'])
        self.assertTrue(all(not row['notes'] and not row['warnings'] for row in result['rows']))

    def test_other_section_or_year_remains_blocked(self):
        for changes in ({'section': 'BSIT-2B'}, {'year_level': '1st Year'}):
            with self.subTest(changes=changes):
                record = StudentAcademicRecord.objects.filter(student=self.students[0])
                record.update(section='BSIT-2A', year_level='2nd Year')
                record.update(**changes)
                result = self.review(self.rows())
                self.assertFalse(result['ready'])
                self.assertFalse(result['rows'][0]['ready'])
                self.assertTrue(result['rows'][0]['issues'])
                self.assertTrue(result['rows'][1]['ready'])

    def test_ignored_adviser_input_still_has_a_real_warning(self):
        rows = self.rows()
        rows[0]['adviser_name'] = self.admin.username
        result = self.review(rows)
        self.assertTrue(result['ready'])
        self.assertTrue(result['rows'][0]['warnings'])
        self.assertEqual(result['summary']['warnings'], 1)

    def test_management_multisection_summary_preserves_section_metadata(self):
        self.client.force_authenticate(self.admin)
        rows = self.rows()[:2]
        rows[0].update(system_name='Societree', project_manager=self.students[0].username)
        rows[1].update(section='BSIT-2B', member_ids=[self.students[12].username],
            leader_id=self.students[12].username, system_name='Campus Services',
            project_manager=self.students[12].username)
        response = self.client.post('/api/teams/bulk-import/preview/', {
            'teams': rows, 'event_name': self.event.event_name}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNone(response.data['section_assignment'])
        summaries = {s['section']: s for s in response.data['section_summaries']}
        self.assertEqual(summaries['BSIT-2A']['system_name'], 'Societree')
        self.assertEqual(summaries['BSIT-2B']['system_name'], 'Campus Services')
        self.assertEqual(summaries['BSIT-2B']['project_manager_username'], self.students[12].username)
        self.assertFalse(SectionAssignment.objects.exists())

    def test_conflicting_headers_are_not_accepted_as_a_ready_system(self):
        rows = self.rows()
        rows[0]['system_name'] = 'Societree'
        rows[1]['system_name'] = 'Another system'
        result = self.review(rows)
        self.assertFalse(result['ready'])
        self.assertFalse(result['section_summaries'][0]['ready'])
        self.assertIn('one System Name', ' '.join(result['section_summaries'][0]['issues']))

    def test_validation_cannot_bypass_scope_authorization(self):
        response = self.client.post('/api/teams/rosters/preview/', {
            'workspace': 'instructor', 'year_level': '1st Year', 'section': 'BSIT-1A',
            'operation': 'import', 'validation_only': True, 'teams': self.rows()}, format='json')
        self.assertEqual(response.status_code, 403)
