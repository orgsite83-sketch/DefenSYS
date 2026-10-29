"""Section requirements are visible even when the team's own work is endorsed."""
from rest_framework.test import APITestCase

from repository.section_concepts import shared_deliverables as shared
from repository.section_concepts.models import SharedDeliverableSet, SharedDeliverableFile
from student_teams.models import SectionAssignment
from . import tests as fixtures
from .models import PitEventGradingConfig, DefenseSchedule
from .serializers import ScheduleTeamSerializer


class SharedSchedulingReadinessTests(APITestCase):
    pit_payload = fixtures.PitEventGradingConfigTests.pit_payload

    def setUp(self):
        fixtures.PitEventGradingConfigTests.setUp(self)
        self.payload = self.pit_payload()
        self.config = PitEventGradingConfig.objects.get(event_name=self.payload['event_name'])
        self.config.shared_deliverables = [{
            'deliverable_id': 'CONCEPT', 'label': 'Concept Paper', 'deliverable_type': 'pre',
            'required': True, 'file_format': 'pdf', 'file_policy': {'mode': 'single'},
        }]
        self.config.save(update_fields=['shared_deliverables'])
        self.team.section = 'BSIT-2B'
        self.team.ready_for_stage = self.config.event_name
        self.team.save(update_fields=['section', 'ready_for_stage'])
        self.section = SectionAssignment.objects.create(section=self.team.section,
            year_level=self.team.year_level, semester=self.semester,
            system_name='Shared System', project_manager=self.student)

    def readiness(self):
        return ScheduleTeamSerializer(self.team).data['shared_readiness'][self.config.event_name]

    def file(self, status):
        profile = shared.resolve(self.team, self.config)
        captured = SharedDeliverableSet.objects.create(**profile['binding'],
            project_manager=self.student, requirements=profile['definitions'],
            team_snapshot=profile['team_snapshot'], system_snapshot=profile['systems'])
        return SharedDeliverableFile.objects.create(submission_set=captured,
            deliverable_id='CONCEPT', slot_key='primary', file='test/concept.pdf',
            file_name='concept.pdf', file_size=100, status=status, uploaded_by=self.student)

    def test_endorsed_team_exposes_missing_section_file_and_save_remains_blocked(self):
        readiness = self.readiness()
        self.assertFalse(readiness['complete'])
        self.assertEqual(readiness['section'], 'BSIT-2B')
        self.assertEqual(readiness['project_manager_name'], self.student.username)
        self.assertEqual(readiness['requirements'], [
            {'id': 'CONCEPT', 'label': 'Concept Paper', 'status': 'awaiting_upload'}])
        response = self.client.get('/api/defense/schedules/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['teams'][0]['shared_readiness'][self.config.event_name], readiness)
        rejected = self.client.post('/api/defense/schedules/confirm-plan/?response=compact',
            {**self.payload, 'slots': [{'team_id': self.team.pk}]}, format='json')
        self.assertEqual(rejected.status_code, 400, rejected.data)
        self.assertIn('shared system deliverables', str(rejected.data))
        self.team.refresh_from_db()
        self.assertEqual(self.team.ready_for_stage, self.config.event_name)
        self.assertFalse(DefenseSchedule.objects.exists())
        self.assertFalse(SharedDeliverableSet.objects.exists())

    def test_pending_rejected_and_accepted_files_have_distinct_readiness(self):
        row = self.file('pending')
        self.assertEqual(self.readiness()['requirements'][0]['status'], 'awaiting_review')
        row.status = 'rejected'
        row.save(update_fields=['status'])
        self.assertEqual(self.readiness()['requirements'][0]['status'], 'changes_requested')
        row.status = 'accepted'
        row.save(update_fields=['status'])
        self.assertTrue(self.readiness()['complete'])
        self.assertEqual(self.readiness()['requirements'], [])

    def test_optional_post_and_unrelated_section_files_do_not_block(self):
        self.config.shared_deliverables[0]['required'] = False
        self.config.shared_deliverables.append({
            'deliverable_id': 'FINAL', 'label': 'Final Paper', 'deliverable_type': 'post',
            'required': True, 'file_format': 'pdf', 'file_policy': {'mode': 'single'},
        })
        self.config.save(update_fields=['shared_deliverables'])
        self.assertTrue(self.readiness()['complete'])
        self.team.section = 'BSIT-2A'
        self.team.save(update_fields=['section'])
        self.assertEqual(ScheduleTeamSerializer(self.team).data['shared_readiness'], {})


class CapstoneSharedSchedulingReadinessTests(APITestCase):
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages

    def test_capstone_stage_reports_its_own_section_requirements(self):
        fixtures.DefenseSchedulerApiTests.setUp(self)
        self.team.section = 'BSIT-3B'
        self.team.save(update_fields=['section'])
        SectionAssignment.objects.create(section=self.team.section, semester=self.semester,
            year_level=self.team.year_level, system_name='Capstone Shared System', project_manager=self.student)
        self.stage.shared_deliverables = [{
            'deliverable_id': 'DESIGN', 'label': 'System Design', 'deliverable_type': 'pre',
            'required': True, 'file_format': 'pdf', 'file_policy': {'mode': 'single'},
        }]
        self.stage.save(update_fields=['shared_deliverables'])
        status = ScheduleTeamSerializer(self.team).data['shared_readiness'][self.stage.label]
        self.assertFalse(status['complete'])
        self.assertEqual(status['requirements'][0]['label'], 'System Design')
        self.assertEqual(status['requirements'][0]['status'], 'awaiting_upload')
