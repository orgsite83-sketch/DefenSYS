"""Team Status distinguishes file progress without changing scheduling gates."""
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from repository.deliverables.models import DeliverableSubmission
from . import tests as fixtures
from .models import PitEventGradingConfig
from .serializers import ScheduleTeamSerializer


class TeamStatusDetailsTests(APITestCase):
    def setUp(self):
        fixtures.PitEventGradingConfigTests.setUp(self)
        payload = fixtures.PitEventGradingConfigTests.pit_payload(self)
        self.event = PitEventGradingConfig.objects.get(event_name=payload['event_name'])
        self.event.deliverables.create(deliverable_id='PAPER', label='Paper',
            deliverable_type='pre', required=True, file_format='pdf')

    def details(self):
        with CaptureQueriesContext(connection) as queries:
            data = ScheduleTeamSerializer(self.team).data
        writes = [query['sql'] for query in queries
                  if query['sql'].lstrip().split()[0].upper() in {'INSERT', 'UPDATE', 'DELETE'}]
        self.assertEqual(writes, [])
        return data['stage_status_details'][self.event.event_name]

    def submission(self, status):
        row = DeliverableSubmission.objects.create(team=self.team,
            stage_label=self.event.event_name, deliverable_id='PAPER',
            label='Paper', deliverable_type='pre', required=True,
            file_name='paper.pdf', status=status)
        # Only metadata is relevant; do not invoke PDF extraction on a fake file.
        DeliverableSubmission.objects.filter(pk=row.pk).update(file='test/paper.pdf')
        return row

    def test_missing_required_files_are_not_awaiting_endorsement(self):
        self.assertEqual(self.details()['requirements_status'], 'awaiting_files')

    def test_uploaded_files_need_review(self):
        self.submission('pending')
        self.assertEqual(self.details()['requirements_status'], 'needs_review')

    def test_accepted_files_await_endorsement(self):
        self.submission('accepted')
        self.assertEqual(self.details()['requirements_status'], 'awaiting_endorsement')

    def test_rejected_files_need_corrections(self):
        self.submission('rejected')
        self.assertEqual(self.details()['requirements_status'], 'changes_requested')

    def test_event_in_another_year_is_not_projected(self):
        self.team.year_level = '1st Year'
        self.assertNotIn(self.event.event_name, ScheduleTeamSerializer(self.team).data['stage_status_details'])


class CapstoneStatusAttemptTests(APITestCase):
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages

    def setUp(self):
        from grading.grades.services import GradeContextService
        fixtures.DefenseSchedulerApiTests.setUp(self)
        self.schedule = fixtures.DefenseSchedulerApiTests.create_scheduled_defense(self)
        self.grade, _, _ = GradeContextService.get_or_create_for_schedule(self.schedule)

    def test_repeat_attempt_number_is_available_without_a_prior_verdict(self):
        self.grade.attempt_count = 2
        self.grade.save(update_fields=['attempt_count'])
        data = ScheduleTeamSerializer(self.team).data
        self.assertEqual(data['stage_status_details'][self.stage.label]['attempt_count'], 2)
        self.assertNotIn(self.stage.label, data['stage_verdicts'])

    def test_another_project_version_cannot_supply_the_attempt_number(self):
        self.team.project_version += 1
        self.assertEqual(ScheduleTeamSerializer(self.team).data['stage_status_details'][self.stage.label]['attempt_count'], 1)
