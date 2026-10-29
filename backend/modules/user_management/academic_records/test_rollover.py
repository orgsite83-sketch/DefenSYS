from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam, TeamMembership

from .models import StudentAcademicRecord
from .rollover import latest_records_by_student


User = get_user_model()


class RolloverRegressionTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='rollover-admin', role='admin')
        self.student = User.objects.create_user(username='rollover-student', role='student')
        self.year = SchoolYear.objects.create(label='2026-2027')
        self.first = Semester.objects.create(school_year=self.year, label=Semester.FIRST, is_active=True)
        self.second = Semester.objects.create(school_year=self.year, label=Semester.SECOND)
        self.next_year = SchoolYear.objects.create(label='2027-2028')
        self.next_first = Semester.objects.create(school_year=self.next_year, label=Semester.FIRST)
        self.client.force_authenticate(self.admin)

    def record(self, student=None, semester=None, year='1st Year', section=None):
        if section is None:
            section = f'BSIT-{year[0]}A'
        return StudentAcademicRecord.objects.create(
            student=student or self.student, semester=semester or self.first,
            year_level=year, section=section)

    def confirm(self, *actions):
        return self.client.post('/api/users/academic-records/rollover/', {'actions': actions}, format='json')

    def team(self, name='Selected team', student=None, year='3rd Year'):
        student = student or self.student
        team = StudentTeam.objects.create(
            name=name, leader=student, semester=self.second, year_level=year,
            level=StudentTeam.LEVEL_3_CAPSTONE if year == '3rd Year' else StudentTeam.LEVEL_4_CAPSTONE)
        TeamMembership.objects.create(team=team, student=student, is_leader=True)
        return team

    def test_empty_and_drop_only_batches_preserve_teams(self):
        self.second.is_active = True
        self.second.save()
        team = self.team()
        source = self.record(semester=self.second, year='3rd Year')
        for actions in ([], [{'record_id': source.pk, 'action': 'drop'}]):
            response = self.confirm(*actions)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.data['team_updates'], 0)
            team.refresh_from_db()
            self.assertEqual(team.semester_id, self.second.pk)
            self.assertEqual(team.year_level, '3rd Year')

    def test_new_student_and_existing_student_without_history_can_be_created(self):
        existing_password = self.student.password
        response = self.confirm(
            {'username': 'new-enrollee', 'first_name': 'New', 'action': 'create',
             'year_level': '2nd Year', 'target_semester_id': self.second.pk},
            {'username': self.student.username, 'action': 'create', 'year_level': '1st Year',
             'target_semester_id': self.second.pk})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 2)
        new_student = User.objects.get(username='new-enrollee')
        record = StudentAcademicRecord.objects.get(student=new_student)
        self.assertEqual(record.year_level, '2nd Year')
        self.assertEqual(record.action, StudentAcademicRecord.ACTION_MANUAL)
        self.assertIsNone(record.rolled_from_id)
        self.student.refresh_from_db()
        self.assertEqual(self.student.password, existing_password)

    def test_legacy_new_student_retry_does_not_create_another_semester(self):
        action = {'username': 'legacy-new-enrollee', 'first_name': 'New', 'action': 'create'}
        first = self.confirm(action)
        repeat = self.confirm(action)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(repeat.status_code, 200)
        self.assertEqual(repeat.data['created_count'], 0)
        self.assertEqual(StudentAcademicRecord.objects.filter(student__username='legacy-new-enrollee').count(), 1)

    def test_invalid_later_row_rolls_back_accounts_and_earlier_records(self):
        source = self.record()
        response = self.confirm(
            {'username': 'rolled-back-account', 'first_name': 'New', 'action': 'create'},
            {'record_id': source.pk, 'action': 'promote', 'year_level': '12th Year',
             'target_semester_id': self.second.pk})
        self.assertEqual(response.status_code, 400)
        self.assertFalse(User.objects.filter(username='rolled-back-account').exists())
        self.assertEqual(StudentAcademicRecord.objects.count(), 1)

    def test_model_failure_rolls_back_batch(self):
        source = self.record()
        original_save = StudentAcademicRecord.save

        def fail_second_record(instance, *args, **kwargs):
            if instance.student.username == 'failed-new-student':
                raise ValidationError({'section': 'Enrollment changed.'})
            return original_save(instance, *args, **kwargs)

        with patch.object(StudentAcademicRecord, 'save', fail_second_record):
            response = self.confirm(
                {'record_id': source.pk, 'action': 'promote', 'target_semester_id': self.second.pk},
                {'username': 'failed-new-student', 'first_name': 'New', 'action': 'create'})
        self.assertEqual(response.status_code, 400)
        self.assertFalse(User.objects.filter(username='failed-new-student').exists())
        self.assertEqual(StudentAcademicRecord.objects.count(), 1)

    def test_retain_enforces_source_year_and_section_despite_promoted_payload(self):
        source = self.record()
        preview = self.client.post('/api/users/academic-records/rollover-preview/', {'students': [
            {'id_number': self.student.username, 'year_level': '2nd Year', 'section': 'BSIT-2B'},
        ]}, format='json')
        retained = preview.data['rows'][0]['retain_result']
        self.assertEqual(retained['target_semester_id'], self.first.pk)
        response = self.confirm({'record_id': source.pk, 'action': 'retain', 'year_level': '2nd Year',
                                 'section': 'BSIT-2B', 'target_semester_id': self.second.pk})
        self.assertEqual(response.status_code, 201)
        record = StudentAcademicRecord.objects.get(student=self.student, semester=self.second)
        self.assertEqual((record.year_level, record.section, record.action), ('1st Year', 'BSIT-1A', 'retain'))

    def test_get_preview_target_is_used_even_while_source_term_is_active(self):
        source = self.record()
        preview = self.client.get('/api/users/academic-records/rollover-preview/')
        result = preview.data['rows'][0]['promote_result']
        self.assertEqual(result['target_semester_id'], self.second.pk)
        response = self.confirm({'record_id': source.pk, 'action': 'promote', **result})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created'][0]['semester_id'], self.second.pk)

    def test_legacy_confirmation_without_explicit_target_uses_preview_target(self):
        source = self.record()
        response = self.confirm({'record_id': source.pk, 'action': 'promote'})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created'][0]['semester_id'], self.second.pk)

    def test_preview_crosses_school_year_and_retain_uses_the_same_target(self):
        self.record(semester=self.second, year='2nd Year')
        preview = self.client.get('/api/users/academic-records/rollover-preview/')
        row = preview.data['rows'][0]
        self.assertEqual(row['promote_result']['target_semester_id'], self.next_first.pk)
        self.assertEqual(row['promote_result']['year_level'], '3rd Year')
        self.assertEqual(row['retain_result']['target_semester_id'], self.next_first.pk)
        self.assertEqual(row['retain_result']['year_level'], '2nd Year')

    def test_missing_target_and_backwards_target_are_rejected(self):
        source = self.record(semester=self.second)
        self.next_first.delete()
        preview = self.client.get('/api/users/academic-records/rollover-preview/')
        self.assertIsNone(preview.data['rows'][0]['promote_result']['target_semester_id'])
        for target in (None, self.first.pk, 999999999):
            response = self.confirm({'record_id': source.pk, 'action': 'promote', 'target_semester_id': target})
            self.assertEqual(response.status_code, 400)
        self.assertEqual(StudentAcademicRecord.objects.count(), 1)

    def test_backfilled_history_does_not_become_latest_and_stale_source_is_rejected(self):
        current = self.record(semester=self.second, year='2nd Year')
        backfill = self.record()
        self.assertEqual(latest_records_by_student()[0].pk, current.pk)
        response = self.confirm({'record_id': backfill.pk, 'action': 'promote', 'year_level': '3rd Year',
                                 'target_semester_id': self.next_first.pk})
        self.assertEqual(response.status_code, 400)

    def test_term_order_does_not_depend_on_insert_order(self):
        year = SchoolYear.objects.create(label='2028-2029')
        summer = Semester.objects.create(school_year=year, label=Semester.SUMMER)
        second = Semester.objects.create(school_year=year, label=Semester.SECOND)
        first = Semester.objects.create(school_year=year, label=Semester.FIRST)
        current = self.record(semester=summer)
        self.record(semester=second)
        self.record(semester=first)
        self.assertEqual(latest_records_by_student()[0].pk, current.pk)

    def test_full_enrollment_never_migrates_either_team(self):
        self.next_first.is_active = True
        self.next_first.save()
        source = self.record(semester=self.second, year='3rd Year')
        selected = self.team()
        other = User.objects.create_user(username='unselected-student', role='student')
        unselected = self.team(name='Unselected team', student=other)
        self.record(student=other, semester=self.next_first, year='4th Year')
        action = {'record_id': source.pk, 'action': 'promote', 'target_semester_id': self.next_first.pk}
        response = self.confirm(action)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['team_updates'], 0)
        selected.refresh_from_db()
        unselected.refresh_from_db()
        self.assertEqual((selected.semester_id, selected.level), (self.second.pk, StudentTeam.LEVEL_3_CAPSTONE))
        self.assertEqual(unselected.semester_id, self.second.pk)
        repeat = self.confirm(action)
        self.assertEqual(repeat.status_code, 200)
        self.assertEqual(repeat.data['created_count'], 0)
        self.assertEqual(repeat.data['team_updates'], 0)

    def test_partial_and_full_enrollment_leave_team_migration_to_period_activation(self):
        self.next_first.is_active = True
        self.next_first.save()
        team = self.team()
        member = User.objects.create_user(username='pending-member', role='student')
        TeamMembership.objects.create(team=team, student=member)
        leader_record = self.record(semester=self.second, year='3rd Year')
        member_record = self.record(student=member, semester=self.second, year='3rd Year')
        first = self.confirm({'record_id': leader_record.pk, 'action': 'promote', 'target_semester_id': self.next_first.pk})
        self.assertEqual(first.data['team_updates'], 0)
        team.refresh_from_db()
        self.assertEqual(team.semester_id, self.second.pk)
        last = self.confirm({'record_id': member_record.pk, 'action': 'promote', 'target_semester_id': self.next_first.pk})
        self.assertEqual(last.data['team_updates'], 0)

    def test_enrollment_alone_never_creates_a_capstone_participation(self):
        source = self.record(semester=self.second, year='3rd Year')
        retained = self.team()
        response = self.confirm({'record_id': source.pk, 'action': 'retain', 'target_semester_id': self.next_first.pk})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['team_updates'], 0)
        retained.refresh_from_db()
        self.assertEqual(retained.semester_id, self.second.pk)
        fourth = User.objects.create_user(username='fourth-year-student', role='student')
        team = self.team(name='Extended team', student=fourth, year='4th Year')
        record = self.record(student=fourth, semester=self.second, year='4th Year')
        response = self.confirm({'record_id': record.pk, 'action': 'retain', 'target_semester_id': self.next_first.pk})
        self.assertEqual(response.data['team_updates'], 0)
        team.refresh_from_db()
        self.assertEqual(team.semester_id, self.second.pk)
        self.assertIsNone(team.capstone_phase)

    def test_duplicate_or_mismatched_student_selections_are_rejected_atomically(self):
        source = self.record()
        action = {'record_id': source.pk, 'action': 'promote', 'target_semester_id': self.second.pk}
        response = self.confirm(action, action)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(StudentAcademicRecord.objects.count(), 1)
        response = self.confirm({**action, 'username': 'wrong-student'})
        self.assertEqual(response.status_code, 400)

    def test_enrollment_does_not_call_team_migration(self):
        self.next_first.is_active = True
        self.next_first.save()
        source = self.record(semester=self.second, year='3rd Year')
        team = self.team()
        with patch.object(StudentTeam, 'save', side_effect=ValidationError('Conflicting team.')):
            response = self.confirm({'record_id': source.pk, 'action': 'promote', 'target_semester_id': self.next_first.pk})
        self.assertEqual(response.status_code, 201)
        self.assertTrue(StudentAcademicRecord.objects.filter(student=self.student, semester=self.next_first).exists())
        team.refresh_from_db()
        self.assertEqual(team.semester_id, self.second.pk)
