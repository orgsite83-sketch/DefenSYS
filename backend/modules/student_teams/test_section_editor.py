from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.models import SystemAuditLog
from user_management.academic_records.models import StudentAcademicRecord
from user_management.models import SectionInstructorAssignment
from .models import SectionAssignment, StudentTeam, TeamMembership


User = get_user_model()


class SectionEditorTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='section-admin', role='admin')
        self.instructor = User.objects.create_user(username='section-instructor', role='faculty')
        self.lead = User.objects.create_user(
            username='section-lead', role='faculty', is_pit_lead=True, pit_lead_year='2nd Year',
        )
        year = SchoolYear.objects.create(label='2026-2027')
        self.term = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        self.history = Semester.objects.create(school_year=year, label=Semester.SECOND)
        self.students = [User.objects.create_user(username=f'section-student-{i}', role='student') for i in range(3)]
        for student in self.students:
            StudentAcademicRecord.objects.create(
                student=student, semester=self.term, year_level='2nd Year', section='BSIT-2b',
            )
        self.teams = []
        for index, student in enumerate(self.students[:2]):
            team = StudentTeam.objects.create(
                name=f'Section team {index}', project_title=f'Module {index}',
                semester=self.term, leader=student, level=StudentTeam.LEVEL_2_PIT,
                year_level='2nd Year', section='BSIT-2b', current_defense_stage=f'Event {index}',
            )
            TeamMembership.objects.create(team=team, student=student, is_leader=True)
            self.teams.append(team)
        self.assignment = SectionAssignment.objects.create(
            semester=self.term, section='BSIT-2b', year_level='2nd Year',
            system_name='Original system', project_manager=self.students[0],
        )
        self.instructor_assignment = SectionInstructorAssignment.objects.create(
            faculty=self.instructor, semester=self.term, year_level='2nd Year', section='BSIT-2b',
        )
        self.url = f'/api/teams/{self.teams[0].pk}/section/'
        self.client.force_authenticate(self.admin)

    def save(self, **changes):
        return self.client.patch(self.url, {
            'expected_section': 'BSIT-2b', 'section': 'BSIT-2B', **changes,
        }, format='json')

    def test_load_includes_whole_section_and_unteamed_manager_candidates(self):
        response = self.client.get(self.url + '?search=Module%200&event_name=Event%200')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['team_count'], 2)
        self.assertEqual(response.data['system_name'], 'Original system')
        self.assertEqual({student['id'] for student in response.data['students']}, {s.pk for s in self.students})

    def test_rename_updates_whole_current_section_and_preserves_history(self):
        historic_record = StudentAcademicRecord.objects.create(
            student=self.students[0], semester=self.history, year_level='2nd Year', section='BSIT-2b',
        )
        historic_assignment = SectionAssignment.objects.create(
            semester=self.history, year_level='2nd Year', section='BSIT-2b', system_name='Historic system',
        )
        response = self.save(system_name='Updated shared system', project_manager_id=self.students[2].pk)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['section'], 'BSIT-2B')
        self.assertEqual(response.data['project_manager_id'], self.students[2].pk)
        self.assertEqual(len(response.data['students']), 3)
        for team in self.teams:
            team.refresh_from_db()
            self.assertEqual(team.section, 'BSIT-2B')
            self.assertEqual(team.project_title, f'Module {self.teams.index(team)}')
        self.assertEqual(StudentAcademicRecord.objects.filter(semester=self.term, section='BSIT-2B').count(), 3)
        self.instructor_assignment.refresh_from_db()
        self.assertEqual(self.instructor_assignment.section, 'BSIT-2B')
        historic_record.refresh_from_db()
        historic_assignment.refresh_from_db()
        self.assertEqual(historic_record.section, 'BSIT-2b')
        self.assertEqual(historic_assignment.system_name, 'Historic system')
        log = SystemAuditLog.objects.get(action='section.update')
        self.assertEqual(log.old_values['section'], 'BSIT-2b')
        self.assertEqual(log.new_values['project_manager_id'], self.students[2].pk)

    def test_manager_and_shared_system_can_be_cleared_without_renaming(self):
        response = self.save(section='BSIT-2b', system_name='', project_manager_id=None)
        self.assertEqual(response.status_code, 200)
        self.assignment.refresh_from_db()
        self.assertIsNone(self.assignment.project_manager_id)
        self.assertEqual(self.assignment.system_name, '')

    def test_ordinary_section_can_gain_shared_details(self):
        self.assignment.delete()
        response = self.save(section='BSIT-2b', system_name='Shared system', project_manager_id=self.students[1].pk)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['system_name'], 'Shared system')

    def test_invalid_manager_and_duplicate_section_leave_all_data_unchanged(self):
        outsider = User.objects.create_user(username='section-outsider', role='student')
        response = self.save(project_manager_id=outsider.pk, system_name='Wrong system')
        self.assertEqual(response.status_code, 400)
        self.assertIn('project_manager_id', response.data)
        StudentAcademicRecord.objects.create(
            student=outsider, semester=self.term, year_level='2nd Year', section='BSIT-2C',
        )
        response = self.save(section='bsit-2c')
        self.assertEqual(response.status_code, 400)
        self.assertIn('section', response.data)
        self.assignment.refresh_from_db()
        self.assertEqual(self.assignment.section, 'BSIT-2b')
        self.assertEqual(self.assignment.system_name, 'Original system')
        self.assertEqual(StudentTeam.objects.filter(section='BSIT-2b').count(), 2)
        self.assertFalse(SystemAuditLog.objects.filter(action='section.update').exists())

    def test_assigned_instructor_and_pit_lead_keep_access_after_rename(self):
        for user in (self.instructor, self.lead):
            with self.subTest(user=user.username):
                self.client.force_authenticate(user)
                self.assertEqual(self.client.get(self.url).status_code, 200)
                response = self.save(section='BSIT-2b', system_name=user.username)
                self.assertEqual(response.status_code, 200, response.data)
        self.client.force_authenticate(self.instructor)
        response = self.save()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.client.get(self.url).status_code, 200)

    def test_students_wrong_year_leads_and_history_cannot_edit(self):
        self.client.force_authenticate(self.students[0])
        self.assertEqual(self.save().status_code, 403)
        self.lead.pit_lead_year = '1st Year'
        self.lead.save()
        self.client.force_authenticate(self.lead)
        self.assertEqual(self.save().status_code, 404)
        self.client.force_authenticate(self.admin)
        StudentTeam.objects.filter(pk__in=[team.pk for team in self.teams]).update(semester=self.history)
        self.assertEqual(self.save().status_code, 403)
        self.assertEqual(self.client.get(self.url).status_code, 403)

    def test_stale_and_invalid_requests_do_not_rename(self):
        for changes in ({'expected_section': 'Old section'}, {'section': ' '}, {'section': 'x' * 81}):
            with self.subTest(changes=changes):
                self.assertEqual(self.save(**changes).status_code, 400)
        self.teams[0].refresh_from_db()
        self.assertEqual(self.teams[0].section, 'BSIT-2b')

    def test_audit_failure_rolls_back_section_changes(self):
        with patch('authentication_access_control.audit_references.capture_audit_references', side_effect=RuntimeError('audit unavailable')):
            response = self.save(system_name='New system')
        self.assertEqual(response.status_code, 500)
        self.assignment.refresh_from_db()
        self.assertEqual(self.assignment.section, 'BSIT-2b')
        self.assertEqual(self.assignment.system_name, 'Original system')
        self.assertEqual(StudentAcademicRecord.objects.filter(section='BSIT-2b').count(), 3)
