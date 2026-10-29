"""A sole current instructor can accept a section's ordinary shared paper."""
import tempfile

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from defense.scheduler import tests as fixtures
from defense.scheduler.models import PitEventGradingConfig
from defense.scheduler.serializers import ScheduleTeamSerializer
from student_teams.models import SectionAssignment
from user_management.models import SectionInstructorAssignment
from user_management.instructor_assignments import update_instructor_assignment
from .models import SharedDeliverableFile
from . import shared_deliverables as shared

URL = '/api/repository/section-concepts/shared-deliverables/'


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class InstructorSharedReviewTests(APITestCase):
    pit_payload = fixtures.PitEventGradingConfigTests.pit_payload

    def setUp(self):
        fixtures.PitEventGradingConfigTests.setUp(self)
        media = tempfile.TemporaryDirectory()
        self.addCleanup(media.cleanup)
        setting = self.settings(MEDIA_ROOT=media.name)
        setting.enable()
        self.addCleanup(setting.disable)
        payload = self.pit_payload()
        self.event = PitEventGradingConfig.objects.get(event_name=payload['event_name'])
        self.event.shared_deliverables = [{
            'deliverable_id': 'PAPER', 'label': 'Concept Paper', 'deliverable_type': 'pre',
            'required': True, 'file_format': 'pdf', 'file_policy': {'mode': 'single'},
        }]
        self.event.save(update_fields=['shared_deliverables'])
        self.team.section = 'BSIT-2B'
        self.team.ready_for_stage = self.event.label
        self.team.save(update_fields=['section', 'ready_for_stage'])
        SectionAssignment.objects.create(semester=self.semester, year_level=self.team.year_level,
            section=self.team.section, system_name='Shared System', project_manager=self.student)
        self.assignment = SectionInstructorAssignment.objects.create(faculty=self.panelist,
            semester=self.semester, year_level=self.team.year_level, section=self.team.section)
        self.retired = get_user_model().objects.create_user(username='retired-instructor', role='faculty')
        SectionInstructorAssignment.objects.create(faculty=self.retired, semester=self.semester,
            year_level=self.team.year_level, section=self.team.section, is_active=False)
        profile = shared.resolve(self.team, self.event)
        shared.upload(self.team, self.event, self.student, 'PAPER', 'primary',
            SimpleUploadedFile('concept.pdf', b'%PDF-1.4 evidence'), shared.review_token(profile))

    def state(self, actor):
        self.client.force_authenticate(actor)
        response = self.client.get(URL, {'team_id': self.team.pk, 'stage_label': self.event.label})
        self.assertEqual(response.status_code, 200, response.data)
        return response.data['shared_deliverables']

    def review(self, actor, state):
        self.client.force_authenticate(actor)
        document = state['requirements'][0]['documents'][0]
        return self.client.post(URL, {'team_id': self.team.pk, 'stage_label': self.event.label,
            'action': 'review', 'deliverable_id': 'PAPER', 'slot_key': 'primary',
            'file_id': document['file']['id'], 'legacy': False, 'status': 'accepted',
            'feedback': '', 'review_token': state['review_token']}, format='json')

    def test_instructor_acceptance_clears_shared_scheduling_blocker_and_records_actor(self):
        before = ScheduleTeamSerializer(self.team).data['shared_readiness'][self.event.label]
        self.assertFalse(before['complete'])
        state = self.state(self.panelist)
        self.assertTrue(state['requirements'][0]['documents'][0]['can_review'])
        response = self.review(self.panelist, state)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['shared_deliverables']['pre_complete'])
        row = SharedDeliverableFile.objects.get()
        self.assertEqual(row.status, 'accepted')
        self.assertEqual(row.reviewed_by, self.panelist)
        self.assertTrue(ScheduleTeamSerializer(self.team).data['shared_readiness'][self.event.label]['complete'])

    def test_retired_instructor_and_project_manager_cannot_review(self):
        state = self.state(self.panelist)
        for actor in (self.retired, self.student):
            response = self.review(actor, state)
            self.assertIn(response.status_code, (403, 404), response.data)
        self.assertEqual(SharedDeliverableFile.objects.get().status, 'pending')

    def test_atomic_replacement_changes_review_access_without_touching_the_upload(self):
        old = self.state(self.panelist)
        update_instructor_assignment(self.admin, self.assignment.pk, {'faculty_id': self.retired.pk})
        self.assertIn(self.review(self.panelist, old).status_code, (403, 404))
        current = self.state(self.retired)
        self.assertTrue(current['requirements'][0]['documents'][0]['can_review'])
        self.assertEqual(self.review(self.retired, current).status_code, 200)
        self.assertEqual(SharedDeliverableFile.objects.count(), 1)

    def test_stale_review_does_not_overwrite_the_accepted_paper(self):
        state = self.state(self.panelist)
        self.assertEqual(self.review(self.panelist, state).status_code, 200)
        response = self.review(self.panelist, state)
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(SharedDeliverableFile.objects.get().status, 'accepted')
