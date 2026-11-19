from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester, SemesterTransitionLog
from student_teams.models import (
    StudentTeam, TeamMembership, TeamTermParticipation,
    StudentCapstoneParticipation, StudentCapstonePlacement,
)
from .enrollment import enrollment_summary
from .models import StudentAcademicRecord


User = get_user_model()


class UnifiedEnrollmentTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.admin = User.objects.create_user(username='enrollment-admin', role='admin')
        cls.student = User.objects.create_user(username='returning-001', role='student',
                                               first_name='Ana M.', last_name='Reyes')
        cls.source = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2030-2031'), label=Semester.SECOND)
        cls.target = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2031-2032'), label=Semester.FIRST, is_active=True)
        cls.previous = StudentAcademicRecord.objects.create(student=cls.student,
            semester=cls.source, year_level='3rd Year', section='BSIT-3A')

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def row(self, username=None, **values):
        return {'id_number': username or self.student.username, 'role': 'student',
                'first_name': 'Ana M.', 'last_name': 'Reyes', 'year_level': '3rd Year',
                'section': 'BSIT-3A', **values}

    def commit(self, rows, semester=None):
        return self.client.post('/api/users/bulk-import/', {'users': rows, 'student_context': {
            'unified_enrollment': True, 'semester_id': (semester or self.target).pk,
        }}, format='json')

    def preview(self, rows, semester=None):
        return self.client.post('/api/users/academic-records/section-preview/', {
            'unified_enrollment': True, 'semester_id': (semester or self.target).pk,
            'students': rows,
        }, format='json')

    def test_mixed_batch_enrolls_new_and_retained_students_and_preserves_accounts(self):
        password = self.student.password
        rows = [self.row(), self.row('new-001', first_name='Mikaela', last_name='Tan',
                                     year_level='1st Year', section='BSIT-1A')]
        preview = self.preview(rows)
        self.assertEqual(preview.status_code, 200)
        self.assertEqual([s['status_code'] for s in preview.data['sections']], ['existing_student', 'ready'])
        self.assertFalse(any(s['blocking'] for s in preview.data['sections']))
        response = self.commit(rows)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(response.data['records_created_count'], 2)
        record = StudentAcademicRecord.objects.get(student=self.student, semester=self.target)
        self.assertEqual((record.year_level, record.rolled_from_id, record.action),
                         ('3rd Year', self.previous.pk, 'retain'))
        self.student.refresh_from_db()
        self.assertEqual((self.student.first_name, self.student.last_name, self.student.password),
                         ('Ana M.', 'Reyes', password))
        self.assertEqual(StudentAcademicRecord.objects.get(pk=self.previous.pk).section, 'BSIT-3A')
        self.assertFalse(StudentCapstoneParticipation.objects.exists())
        self.assertFalse(StudentTeam.objects.exists())

    def test_retry_is_a_noop_and_an_absent_student_is_not_carried(self):
        absent = User.objects.create_user(username='absent-student', role='student')
        StudentAcademicRecord.objects.create(student=absent, semester=self.source, year_level='2nd Year')
        self.assertEqual(self.commit([self.row()]).status_code, 201)
        again = self.commit([self.row()])
        self.assertEqual(again.status_code, 200, again.data)
        self.assertEqual(again.data['records_created_count'], 0)
        self.assertEqual(again.data['skipped'][0]['reason'], 'already_enrolled')
        self.assertEqual(StudentAcademicRecord.objects.filter(semester=self.target).count(), 1)
        self.assertFalse(StudentAcademicRecord.objects.filter(student=absent, semester=self.target).exists())
        self.assertEqual(self.preview([self.row()]).data['sections'][0]['status_code'], 'already_enrolled')

    def test_later_blocker_rolls_back_new_account_and_earlier_section_update(self):
        other = User.objects.create_user(username='existing-002', role='student')
        current = StudentAcademicRecord.objects.create(student=other, semester=self.target,
                                                       year_level='1st Year', section='BSIT-1A')
        response = self.commit([
            self.row('new-rollback', year_level='1st Year', section='BSIT-1A'),
            self.row(other.username, year_level='1st Year', section='BSIT-1B'),
            self.row(year_level='2nd Year', section='BSIT-2A'),
        ])
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['errors'][0]['id_number'], self.student.username)
        self.assertFalse(User.objects.filter(username='new-rollback').exists())
        current.refresh_from_db()
        self.assertEqual(current.section, 'BSIT-1A')

    def test_identity_and_inactive_account_conflicts_match_preview_and_confirmation(self):
        for changes in ({'first_name': 'Different'},):
            with self.subTest(changes=changes):
                self.assertTrue(self.preview([self.row(**changes)]).data['sections'][0]['blocking'])
                self.assertEqual(self.commit([self.row(**changes)]).status_code, 400)
        self.student.is_active = False
        self.student.save(update_fields=['is_active'])
        self.assertTrue(self.preview([self.row()]).data['sections'][0]['blocking'])
        self.assertEqual(self.commit([self.row()]).status_code, 400)
        self.assertFalse(StudentAcademicRecord.objects.filter(semester=self.target).exists())

    def test_stale_semester_is_rejected_both_before_and_inside_confirmation(self):
        self.assertEqual(self.preview([self.row()], self.source).status_code, 400)
        self.assertEqual(self.commit([self.row()], self.source).status_code, 400)
        # Simulate activation after the view resolved its target, before it locks
        # and rechecks the semester. This is isolated test data only.
        Semester.objects.filter(pk=self.target.pk).update(is_active=False)
        with patch('user_management.views.BulkImportUsersMixin._resolve_context_semester', return_value=self.target):
            response = self.commit([self.row()])
        self.assertEqual(response.status_code, 400)
        self.assertFalse(StudentAcademicRecord.objects.filter(semester=self.target).exists())

    def test_client_conflicts_and_wrong_role_roll_back_the_whole_batch(self):
        faculty = User.objects.create_user(username='faculty-conflict', role='faculty')
        for bad in (self.row(_client_validation_error='Conflicting file rows'), self.row(faculty.username)):
            with self.subTest(bad=bad):
                response = self.commit([self.row('new-rollback'), bad])
                self.assertEqual(response.status_code, 400)
                self.assertFalse(User.objects.filter(username='new-rollback').exists())

    def test_duplicate_id_with_different_people_is_never_silently_deduplicated(self):
        rows = [self.row('new-conflict'), self.row('new-conflict', first_name='Someone')]
        self.assertTrue(self.preview(rows).data['sections'][1]['blocking'])
        self.assertEqual(self.commit(rows).status_code, 400)
        self.assertFalse(User.objects.filter(username='new-conflict').exists())

    def test_counts_are_independent_of_search_history_and_no_active_term(self):
        StudentAcademicRecord.objects.create(student=self.student, semester=self.target,
                                             year_level='4th Year', section='BSIT-4A')
        inactive = User.objects.create_user(username='inactive-count', role='student', is_active=False)
        StudentAcademicRecord.objects.create(student=inactive, semester=self.target, year_level='1st Year')
        for params in ({'term_context': 'current'}, {'search': 'no-such-student'}, {'school_year': '2030-2031'}):
            response = self.client.get('/api/users/academic-records/', params)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.data['counts']['enrollment']['enrolled'], 1)
            self.assertEqual(response.data['counts']['enrollment']['task_count'], 1)
        current = self.client.get('/api/users/academic-records/', {'term_context': 'current'})
        self.assertTrue(all(r['semester_id'] == self.target.pk for r in current.data['records']))
        Semester.objects.filter(pk=self.target.pk).update(is_active=False)
        no_active = self.client.get('/api/users/academic-records/', {'term_context': 'current'})
        self.assertEqual(no_active.data['records'], [])
        self.assertIsNone(no_active.data['counts']['enrollment']['enrolled'])
        self.assertEqual(no_active.data['counts']['enrollment']['task_count'], 0)

    def test_only_approved_live_continuation_placements_produce_pending_groups(self):
        team = StudentTeam.objects.create(name='Continued team', leader=self.student,
            semester=self.target, intake_semester=self.source, year_level='4th Year',
            level=StudentTeam.LEVEL_4_CAPSTONE)
        TeamMembership.objects.create(team=team, student=self.student, is_leader=True)
        participation = StudentCapstoneParticipation.objects.create(student=self.student,
            intake_semester=self.source, number=1)
        placement = StudentCapstonePlacement.objects.create(participation=participation, team=team)
        log = SemesterTransitionLog.objects.create(from_semester=self.source, to_semester=self.target,
            impact_snapshot={'applied_team_ids': [team.pk], 'capstone_review': {
                'teams': [{'team_id': team.pk, 'can_include': True}]}})
        TeamTermParticipation.objects.update_or_create(team=team, semester=self.target, defaults={'transition': log})
        unrelated = User.objects.create_user(username='other-enrolled', role='student')
        StudentAcademicRecord.objects.create(student=unrelated, semester=self.target, year_level='1st Year')
        summary = enrollment_summary(self.target)
        self.assertEqual((summary['enrolled'], summary['pending_continuations'], summary['task_count']), (1, 1, 1))
        StudentAcademicRecord.objects.create(student=self.student, semester=self.target,
                                             year_level='4th Year', section='BSIT-4A')
        resolved = enrollment_summary(self.target)
        self.assertEqual(resolved['pending_continuations'], 0)
        self.assertEqual(resolved['pending_groups'], [])
        self.assertEqual((resolved['task_count'], resolved['reason']), (1, 'empty_years'))
        StudentAcademicRecord.objects.filter(student=self.student, semester=self.target).delete()
        participation.state = 'failed'
        participation.save(update_fields=['state'])
        self.assertEqual(enrollment_summary(self.target)['pending_continuations'], 0)
        placement.delete()

    def test_importing_one_year_keeps_one_reminder_and_later_work_available(self):
        from dashboards.overview import admin_overview
        missing_year_messages = [
            '1st Year, 2nd Year, and 4th Year',
            '2nd Year and 4th Year',
            '4th Year',
            None,
        ]
        for index, year in enumerate(('3rd Year', '1st Year', '2nd Year', '4th Year')):
            with self.subTest(year=year):
                response = self.commit([self.row(f'import-year-{index}', year_level=year,
                                                  section=f'BSIT-{year[0]}A')])
                self.assertEqual(response.status_code, 201, response.data)
                summary = enrollment_summary(self.target)
                overview = admin_overview(self.target, [], [], 1)
                tasks = [task for task in overview['action_items']
                         if task['target_section'] == 'userManagement']
                needs_reminder = index < 3
                self.assertEqual(summary['enrolled'], index + 1)
                self.assertEqual(summary['pending_continuations'], 0)
                self.assertEqual(summary['task_count'], int(needs_reminder))
                self.assertEqual(overview['action_counts'].get('userManagement', 0), int(needs_reminder))
                self.assertEqual(overview['enrollment'], summary)
                self.assertEqual(len(tasks), int(needs_reminder))
                if needs_reminder:
                    self.assertEqual(tasks[0]['id'], f'enrollment:{self.target.pk}')
                    self.assertEqual(tasks[0]['description'],
                        f'No students are enrolled in {missing_year_messages[index]} this semester.')
                    self.assertIn('view=enrollment', tasks[0]['target_route'])
                    self.assertIn(f'semester_id={self.target.pk}', tasks[0]['target_route'])
                    self.assertNotIn('affected_count', tasks[0])
                    self.assertTrue(overview['workflow'][0]['action'])
                else:
                    self.assertEqual(summary['empty_years'], [])
                    self.assertIsNone(summary['reason'])
                    self.assertFalse(overview['workflow'][0]['action'])
                self.assertTrue(any(task['id'] == 'unscheduled_ready_teams'
                                    for task in overview['action_items']))
                self.assertTrue(overview['workflow'][3]['action'])

    def test_empty_term_has_one_shared_task_regardless_of_historical_accounts(self):
        summary = enrollment_summary(self.target)
        self.assertEqual((summary['enrolled'], summary['task_count']), (0, 1))
        from dashboards.overview import admin_overview
        overview = admin_overview(self.target, [], [], 0)
        tasks = [task for task in overview['action_items'] if task['target_section'] == 'userManagement']
        self.assertEqual(len(tasks), 1)
        self.assertEqual(tasks[0]['id'], f'enrollment:{self.target.pk}')
        self.assertEqual(overview['enrollment'], summary)
        self.assertEqual(overview['action_counts']['userManagement'], 1)
