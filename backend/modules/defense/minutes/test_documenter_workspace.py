from datetime import date, time
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam
from user_management.models import FacultyRoleAssignment
from .models import DefenseMinutes, MinutesPanelistComment
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage


class DocumenterWorkspaceTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.admin = User.objects.create_user(username='workspace-pool-admin', role='admin')
        cls.doc = User.objects.create_user(username='workspace-doc', role='faculty', is_documenter=True)
        cls.faculty = User.objects.create_user(username='workspace-pool-faculty', role='faculty')
        cls.student = User.objects.create_user(username='workspace-pool-student', role='student')
        year = SchoolYear.objects.create(label='2027-2028')
        cls.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        cls.stage = DefenseStage.objects.create(label='Workspace stage', minutes_required=True)
        cls.team = StudentTeam.objects.create(name='Workspace team', project_title='Workspace project',
            semester=cls.semester, leader=cls.student, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        cls.schedule = DefenseSchedule.objects.create(scope='capstone', team=cls.team, semester=cls.semester,
            defense_stage=cls.stage, documenter=cls.doc, scheduled_date=date(2026, 10, 9),
            start_time=time(8), room='301', created_by=cls.admin)

    def create_minutes(self, status='draft'):
        return DefenseMinutes.objects.create(schedule=self.schedule, team_name=self.team.name,
            project_title=self.team.project_title, adviser_name='', documenter_name='Documenter',
            defense_stage_label=self.stage.label, defense_date=self.schedule.scheduled_date,
            defense_time=self.schedule.start_time, room=self.schedule.room, status=status)

    def test_admin_preview_does_not_create_minutes(self):
        self.client.force_authenticate(self.admin)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.pk}/preview/')
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.data['detail'], 'Minutes have not been prepared yet.')
        self.assertFalse(DefenseMinutes.objects.filter(schedule=self.schedule).exists())

    def test_preview_rejects_unassigned_faculty_without_creating_minutes(self):
        self.client.force_authenticate(self.faculty)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.pk}/preview/')
        self.assertEqual(response.status_code, 403)
        self.assertFalse(DefenseMinutes.objects.exists())

    def test_assignment_distinguishes_blank_draft_from_recorded_comments(self):
        minutes = self.create_minutes()
        comment = MinutesPanelistComment.objects.create(minutes=minutes, comments=' \n ', panelist_name_snapshot='Panelist')
        self.client.force_authenticate(self.doc)
        response = self.client.get('/api/defense/minutes/my-assignments/')
        self.assertFalse(response.data[0]['minutes_has_comments'])
        comment.comments = 'Calibrate the sensor.'
        comment.save(update_fields=['comments'])
        response = self.client.get('/api/defense/minutes/my-assignments/')
        self.assertTrue(response.data[0]['minutes_has_comments'])
        self.client.force_authenticate(self.faculty)
        self.assertEqual(self.client.get('/api/defense/minutes/my-assignments/').data, [])

    def test_pool_requires_administrator(self):
        for user in (self.doc, self.faculty, self.student):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get('/api/defense/minutes/documenter-pool/').status_code, 403)
            self.assertEqual(self.client.patch('/api/defense/minutes/documenter-pool/',
                {'changes': [{'id': self.faculty.pk, 'is_documenter': True}]}, format='json').status_code, 403)

    def test_pool_changes_only_documenter_flag_and_records_actor(self):
        self.client.force_authenticate(self.admin)
        response = self.client.patch('/api/defense/minutes/documenter-pool/',
            {'changes': [{'id': self.faculty.pk, 'is_documenter': True}]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.faculty.refresh_from_db()
        self.assertTrue(self.faculty.is_documenter)
        self.assertFalse(self.faculty.is_panelist)
        history = FacultyRoleAssignment.objects.get(user=self.faculty, role_key='documenter')
        self.assertEqual(history.changed_by, self.admin)

    def test_pool_lists_outstanding_assignments(self):
        self.client.force_authenticate(self.admin)
        people = self.client.get('/api/defense/minutes/documenter-pool/').data['people']
        doc = next(p for p in people if p['id'] == self.doc.pk)
        self.assertEqual(doc['pending_assignments'][0]['id'], self.schedule.pk)

    def test_pool_removal_blocks_unfinished_minutes_and_batch_is_atomic(self):
        self.client.force_authenticate(self.admin)
        response = self.client.patch('/api/defense/minutes/documenter-pool/', {'changes': [
            {'id': self.faculty.pk, 'is_documenter': True},
            {'id': self.doc.pk, 'is_documenter': False},
        ]}, format='json')
        self.assertEqual(response.status_code, 400)
        self.faculty.refresh_from_db()
        self.doc.refresh_from_db()
        self.assertFalse(self.faculty.is_documenter)
        self.assertTrue(self.doc.is_documenter)

    def test_finalized_assignments_allow_pool_removal_and_remain_assigned(self):
        self.create_minutes(status='completed')
        self.client.force_authenticate(self.admin)
        response = self.client.patch('/api/defense/minutes/documenter-pool/',
            {'changes': [{'id': self.doc.pk, 'is_documenter': False}]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.schedule.refresh_from_db()
        self.assertEqual(self.schedule.documenter_id, self.doc.pk)

    def test_pool_rejects_duplicate_and_non_staff_entries(self):
        self.client.force_authenticate(self.admin)
        for changes in ([{'id': self.student.pk, 'is_documenter': True}],
            [{'id': self.faculty.pk, 'is_documenter': True}, {'id': self.faculty.pk, 'is_documenter': False}]):
            self.assertEqual(self.client.patch('/api/defense/minutes/documenter-pool/',
                {'changes': changes}, format='json').status_code, 400)
