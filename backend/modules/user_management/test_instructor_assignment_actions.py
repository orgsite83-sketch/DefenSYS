"""Assignment changes preserve accounts/history and cannot leave a half replacement."""
from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from .models import SectionInstructorAssignment


class InstructorAssignmentActionTests(APITestCase):
    def setUp(self):
        user = get_user_model()
        self.lead = user.objects.create_user(username='third-year-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='3rd Year')
        self.instructor = user.objects.create_user(username='FAC-2041', first_name='Florencia', last_name='Dela Torre', role='faculty')
        self.replacement = user.objects.create_user(username='FAC-2042', first_name='Eduardo', last_name='Padilla', role='faculty')
        self.semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2097-2098'),
            label=Semester.FIRST, is_active=True)
        self.assignment = SectionInstructorAssignment.objects.create(faculty=self.instructor,
            semester=self.semester, year_level='3rd Year', section='BSIT-3A', assigned_by=self.lead)
        self.client.force_authenticate(self.lead)
        self.url = f'/api/users/pit-instructors/{self.assignment.pk}/'

    def test_list_supplies_the_real_id_number_and_matching_faculty_identity(self):
        response = self.client.get('/api/users/pit-instructors/')
        self.assertEqual(response.status_code, 200)
        row = response.data['assignments'][0]
        self.assertEqual(row['faculty_id'], self.instructor.pk)
        self.assertEqual(row['faculty'], self.instructor.pk)
        self.assertEqual(row['faculty_username'], 'FAC-2041')

    def test_remove_is_scoped_soft_removal_with_history_and_account_intact(self):
        other = SectionInstructorAssignment.objects.create(faculty=self.instructor,
            semester=self.semester, year_level='3rd Year', section='BSIT-3B')
        password = self.instructor.password
        response = self.client.patch(self.url, {'is_active': False}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assignment.refresh_from_db()
        self.instructor.refresh_from_db()
        other.refresh_from_db()
        self.assertFalse(self.assignment.is_active)
        self.assertTrue(other.is_active)
        self.assertTrue(self.instructor.is_active)
        self.assertEqual(self.instructor.password, password)
        self.assertTrue(SystemAuditLog.objects.filter(action='pit_instructor.remove', actor=self.lead,
            old_values__is_active=True, new_values__is_active=False).exists())
        self.assertEqual(self.client.patch(self.url, {'is_active': True}, format='json').status_code, 200)
        self.assignment.refresh_from_db()
        self.assertTrue(self.assignment.is_active)

    def test_replacement_deactivates_only_the_source_and_preserves_its_record(self):
        response = self.client.patch(self.url, {'faculty_id': self.replacement.pk}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assignment.refresh_from_db()
        self.assertFalse(self.assignment.is_active)
        self.assertEqual(self.assignment.faculty, self.instructor)
        self.assertEqual(response.data['replaced_assignment']['id'], self.assignment.pk)
        current = SectionInstructorAssignment.objects.get(is_active=True)
        self.assertEqual(current.faculty, self.replacement)
        self.assertEqual(current.section, 'BSIT-3A')
        self.assertTrue(SystemAuditLog.objects.filter(action='pit_instructor.replace',
            new_values__previous_faculty_id=self.instructor.pk, new_values__faculty_id=self.replacement.pk).exists())

    def test_replacement_reuses_an_existing_assignment_instead_of_duplicating_it(self):
        for active in (False, True):
            with self.subTest(active=active):
                self.assignment.is_active = True
                self.assignment.save(update_fields=['is_active'])
                target, _ = SectionInstructorAssignment.objects.update_or_create(faculty=self.replacement,
                    semester=self.semester, year_level='3rd Year', section='BSIT-3A', defaults={'is_active': active})
                response = self.client.patch(self.url, {'faculty_id': self.replacement.pk}, format='json')
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.data['assignment']['id'], target.pk)
                self.assertEqual(SectionInstructorAssignment.objects.filter(is_active=True).count(), 1)

    def test_invalid_replacement_and_stale_source_do_not_remove_the_current_instructor(self):
        for faculty in ('unknown', True, 999999):
            response = self.client.patch(self.url, {'faculty_id': faculty}, format='json')
            self.assertEqual(response.status_code, 400)
            self.assignment.refresh_from_db()
            self.assertTrue(self.assignment.is_active)
        self.assertEqual(self.client.patch(self.url, {'faculty_id': self.replacement.pk}, format='json').status_code, 200)
        self.assertEqual(self.client.patch(self.url, {'faculty_id': self.instructor.pk}, format='json').status_code, 409)
        self.assertEqual(SectionInstructorAssignment.objects.filter(is_active=True).count(), 1)

    def test_failed_audit_rolls_back_removal_and_replacement(self):
        with patch('user_management.instructor_assignments.log_high_impact_action', side_effect=RuntimeError('audit unavailable')):
            # Match the service's strict audit boundary: a failed audit must abort
            # the transaction before either endpoint can return success.
            for payload in ({'is_active': False}, {'faculty_id': self.replacement.pk}):
                with self.assertRaises(RuntimeError):
                    self.client.patch(self.url, payload, format='json')
                self.assignment.refresh_from_db()
                self.assertTrue(self.assignment.is_active)
                self.assertEqual(SectionInstructorAssignment.objects.count(), 1)

    def test_other_year_and_non_management_accounts_cannot_modify_the_assignment(self):
        user = get_user_model()
        for actor in (self.instructor,
                user.objects.create_user(username='second-lead', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year'),
                user.objects.create_user(username='missing-year', role='faculty', is_pit_lead=True),
                user.objects.create_user(username='student', role='student')):
            self.client.force_authenticate(actor)
            self.assertEqual(self.client.patch(self.url, {'is_active': False}, format='json').status_code, 403)
            self.assertEqual(self.client.patch(self.url, {'faculty_id': self.replacement.pk}, format='json').status_code, 403)
        self.assignment.refresh_from_db()
        self.assertTrue(self.assignment.is_active)

    def test_historical_and_capstone_term_assignments_are_read_only(self):
        previous = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        self.assignment.semester = previous
        self.assignment.save(update_fields=['semester'])
        self.assertEqual(self.client.patch(self.url, {'is_active': False}, format='json').status_code, 403)
        self.assignment.semester = self.semester
        self.assignment.save(update_fields=['semester'])
        self.semester.label = Semester.SECOND
        previous.delete()
        self.semester.save(update_fields=['label'])
        self.assertEqual(self.client.patch(self.url, {'is_active': False}, format='json').status_code, 400)

    def test_status_validation_and_section_scope_fail_without_changes(self):
        self.assertEqual(self.client.patch(self.url, {'is_active': 'false'}, format='json').status_code, 400)
        self.assertEqual(self.client.patch(self.url, {'section': 'BSIT-3B'}, format='json').status_code, 403)
        self.assignment.refresh_from_db()
        self.assertTrue(self.assignment.is_active)
        self.assertEqual(self.assignment.section, 'BSIT-3A')

    def test_removal_revokes_only_the_section_instructor_access(self):
        from authentication_access_control.workspaces import workspace_teams_for
        from student_teams.models import StudentTeam
        student = get_user_model().objects.create_user(username='module-leader', role='student')
        team = StudentTeam.objects.create(name='Module team', leader=student, semester=self.semester,
            section='BSIT-3A', year_level='3rd Year', level=StudentTeam.LEVEL_3_PIT)
        self.instructor.is_panelist = True
        self.instructor.save(update_fields=['is_panelist'])
        self.assertTrue(workspace_teams_for(self.instructor, 'instructor').filter(pk=team.pk).exists())
        self.assertEqual(self.client.patch(self.url, {'is_active': False}, format='json').status_code, 200)
        self.assertFalse(workspace_teams_for(self.instructor, 'instructor').filter(pk=team.pk).exists())
        self.instructor.refresh_from_db()
        self.assertTrue(self.instructor.is_panelist)
