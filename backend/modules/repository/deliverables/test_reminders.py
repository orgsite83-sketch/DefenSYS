from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable
from notifications.models import Notification
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from student_teams.models import StudentTeam, TeamMembership


class RequirementReminderTests(APITestCase):
    def setUp(self):
        users = get_user_model()
        self.admin = users.objects.create_user(username='matrix-admin', role='admin')
        self.student = users.objects.create_user(username='matrix-student', role='student')
        semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2026-2027'), label=Semester.FIRST, is_active=True)
        self.team = StudentTeam.objects.create(
            name='Matrix Team', level=StudentTeam.LEVEL_3_CAPSTONE, semester=semester,
            year_level='3rd Year', leader=self.student)
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        self.stage = DefenseStage.objects.get_or_create(label='Project Proposal')[0]
        for key, label, timing in [('DECK', 'Pitch Deck', 'pre'), ('FINAL', 'Approved Concept Paper', 'post')]:
            StageDeliverable.objects.create(
                defense_stage=self.stage, deliverable_id=key, label=label, required=True,
                deliverable_type=timing, file_policy={'mode': 'named', 'slots': [
                    {'key': 'one', 'label': 'First file', 'required': True},
                    {'key': 'two', 'label': 'Second file', 'required': True},
                ]})
        self.client.force_authenticate(self.admin)

    def remind(self, deliverable_id):
        return self.client.post(f'/api/teams/{self.team.pk}/remind/',
                                {'stage_label': self.stage.label, 'deliverable_id': deliverable_id}, format='json')

    def file(self, submission, slot, **extra):
        return DeliverableSubmissionFile.objects.create(
            submission=submission, slot_key=slot, file=f'deliverables/{slot}.pdf',
            file_name=f'{slot}.pdf', extracted_text='Isolated test fixture', **extra)

    def test_partial_group_reminds_for_its_requirement_and_resolves_when_all_files_arrive(self):
        submission = DeliverableSubmission.objects.create(
            team=self.team, stage_label=self.stage.label, deliverable_id='DECK',
            label='Pitch Deck', deliverable_type='pre', status='pending')
        self.file(submission, 'one')
        response = self.remind('DECK')
        self.assertEqual(response.status_code, 200, response.data)
        alert = Notification.objects.get(recipient=self.student)
        self.assertIn('Pitch Deck', alert.message)
        self.assertNotIn('Approved Concept Paper', alert.message)
        self.assertEqual(alert.action_payload['deliverable_id'], 'DECK')
        self.client.force_authenticate(self.student)
        url = f'/api/notifications/{alert.pk}/?workspace=student'
        self.assertFalse(self.client.get(url).data['notification']['action']['is_complete'])
        self.file(submission, 'two')
        self.assertTrue(self.client.get(url).data['notification']['action']['is_complete'])
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.remind('DECK').status_code, 409)
        self.assertEqual(Notification.objects.filter(recipient=self.student).count(), 1)

    def test_post_defense_reminder_names_the_selected_archive_requirement(self):
        response = self.remind('FINAL')
        self.assertEqual(response.status_code, 200, response.data)
        alert = Notification.objects.get(recipient=self.student)
        self.assertIn('Approved Concept Paper', alert.message)
        self.assertNotIn('Pitch Deck', alert.message)
        self.assertNotIn('Pending overall stage endorsement', alert.message)
        self.client.force_authenticate(self.student)
        self.assertFalse(self.client.get(f'/api/notifications/{alert.pk}/?workspace=student')
                         .data['notification']['action']['is_complete'])

    def test_invalid_requirement_and_unauthorized_sender_create_no_notifications(self):
        self.assertEqual(self.remind('unknown').status_code, 404)
        self.assertEqual(self.remind('').status_code, 400)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.remind('DECK').status_code, 403)
        self.assertFalse(Notification.objects.exists())
