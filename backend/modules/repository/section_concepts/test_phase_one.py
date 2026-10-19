"""Independent team approval, shared awareness and version-bound scheduling."""
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from defense.stages.models import StageDeliverable
from repository.deliverables import concepts
from repository.deliverables.services import stage_payload, endorse_team, upsert_submission, review_submission
from . import services, acknowledgments
from . import tests as fixtures


class EndorsementPhaseOneTests(APITestCase):
    setUp = fixtures.SharedSystemConceptTests.setUp
    rubric = fixtures.SharedSystemConceptTests.rubric
    data = fixtures.SharedSystemConceptTests.data
    slot = fixtures.SharedSystemConceptTests.slot
    configure = fixtures.SharedSystemConceptTests.configure
    titles = fixtures.SharedSystemConceptTests.titles
    action = fixtures.SharedSystemConceptTests.action
    prepare_shared = fixtures.SharedSystemConceptTests.prepare_shared
    prepare_team = fixtures.SharedSystemConceptTests.prepare_team

    def capstone(self):
        self.first.is_adviser = True
        self.first.save(update_fields=['is_adviser'])
        self.other = get_user_model().objects.create_user(username='other-shared-adviser',
            role='faculty', is_adviser=True)
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save(update_fields=['concept_config'])
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='CONCEPTS',
            label='Module papers', required=True, file_policy={'mode': 'concepts'})
        self.project.section.year_level = '3rd Year'
        self.project.section.save(update_fields=['year_level'])
        self.project.pit_event_config = None
        self.project.defense_stage = self.stage
        self.project.save(update_fields=['pit_event_config', 'defense_stage'])
        for team, adviser in ((self.team, self.first), (self.module_team, self.other)):
            team.level, team.year_level, team.adviser = '3rd Year Capstone', '3rd Year', adviser
            team.save(update_fields=['level', 'year_level', 'adviser'])
            team._section_concept_projects = {}
        # Fixture helpers use event.label; use the Capstone context from here onward.
        self.event = self.stage

    def test_team_can_endorse_before_shared_upload_but_cannot_schedule(self):
        self.prepare_team(self.team)
        state = stage_payload(self.team, self.event.label, evaluator=self.first)
        self.assertTrue(state['endorsed'])
        self.assertEqual(state['concept_workflow']['status'], 'shared_clearance_pending')
        self.assertIn('shared system titles', concepts.clearance_blocker(self.team, self.event))
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/defense/schedules/', self.slot(self.team), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.prepare_shared()
        self.assertTrue(concepts.clearance_valid(self.team, self.event))
        self.assertEqual(concepts.payload(self.team, self.event)['status'], 'ready_to_schedule')

    def test_shared_paper_corrections_preserve_team_endorsement(self):
        self.prepare_shared()
        self.prepare_team(self.team)
        round = services.latest(self.project)
        paper = round.systems.get(key='c1').papers.get(is_current=True)
        services.review(self.project, self.first, paper.pk, 'rejected', 'Clarify system context.')
        services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('revision.pdf', b'%PDF-1.4 revised'))
        self.assertTrue(concepts.clearance_valid(self.team, self.event))
        self.assertEqual(concepts.payload(self.team, self.event)['status'], 'shared_clearance_pending')

    def test_module_confirmation_is_a_separate_task_and_blocks_endorsement(self):
        concepts.save_titles(self.team, self.event, self.titles('Module'), actor=self.pm)
        state = stage_payload(self.team, self.event.label)
        self.assertEqual(state['concept_workflow']['status'], 'module_confirmation_pending')
        self.assertFalse(state['endorsement_review']['can_review_and_endorse'])
        self.assertIn('confirm all three', state['endorsement_review']['reason'])
        for key in services.KEYS:
            sub = upsert_submission(self.team, self.event.label, 'CONCEPTS', f'{key}.pdf', '10 B',
                self.pm, file=SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 module'), slot_key=f'{key}:paper')
            review_submission(self.team, self.event.label, 'CONCEPTS', 'accepted', '', self.first,
                file_id=sub.files.get(is_current=True, slot_key=f'{key}:paper').pk)
        with self.assertRaisesMessage(ValueError, 'confirm all three'):
            endorse_team(self.team, self.event.label, self.first)

    def test_sole_instructor_is_resolved_without_reviewer_input(self):
        configured = services.configure(self.first, [self.team], self.event,
            {'project_manager_id': self.pm.pk})
        self.assertEqual(configured.reviewer_id, self.first.pk)
        self.project.reviewer = self.second
        self.project.save(update_fields=['reviewer'])
        self.assertTrue(services.is_reviewer(self.first, self.project))
        self.assertFalse(services.is_reviewer(self.second, self.project))

    def test_each_capstone_adviser_acknowledges_shared_context_independently(self):
        self.capstone()
        self.prepare_shared()
        concepts.save_titles(self.module_team, self.event, self.titles('Module'), actor=self.other)
        round = services.latest(self.project)
        self.assertTrue(acknowledgments.acknowledged(round, self.first.pk))
        self.assertFalse(acknowledgments.acknowledged(round, self.other.pk))
        self.assertIn('acknowledge', services.scheduling_blocker(self.module_team, self.event,
            concepts.latest_round(self.module_team, self.event)))
        self.assertTrue(services.payload(self.project, self.other)['shared_review']['can_acknowledge'])
        self.assertFalse(services.payload(self.project, self.other)['can_review'])
        self.assertEqual(services.task_payload(self.other)[0]['status'], 'awaiting_shared_acknowledgment')
        response = self.action('acknowledge', self.other)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['shared_review']['acknowledged'])
        self.assertEqual(services.task_payload(self.other), [])
        self.assertFalse(services.scheduling_blocker(self.module_team, self.event,
            concepts.latest_round(self.module_team, self.event)))
        self.assertFalse(concepts.clearance_valid(self.module_team, self.event))

    def test_acknowledgment_is_reusable_and_new_paper_versions_require_new_review(self):
        self.capstone()
        self.prepare_shared()
        round = services.latest(self.project)
        acknowledgments.acknowledge(self.project, self.other)
        acknowledgments.acknowledge(self.project, self.other)
        self.assertEqual(round.acknowledgments.filter(faculty=self.other).count(), 1)
        state = acknowledgments.summary(round, team=self.module_team)
        self.assertTrue(state['acknowledged'])
        paper = round.systems.get(key='c1').papers.get(is_current=True)
        services.review(self.project, self.first, paper.pk, 'rejected', 'Clarify scope.')
        services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('new.pdf', b'%PDF-1.4 new'))
        self.assertFalse(acknowledgments.acknowledged(round, self.other.pk))
        acknowledgments.acknowledge(self.project, self.other)
        self.assertEqual(round.acknowledgments.filter(faculty=self.other).count(), 2)

    def test_missing_shared_files_and_unassigned_users_cannot_acknowledge(self):
        self.capstone()
        self.assertEqual(self.action('acknowledge', self.other).status_code, 400)
        self.prepare_shared()
        for actor in (self.pm, self.second):
            self.assertIn(self.action('acknowledge', actor).status_code, (403, 404))

    def test_stale_shared_acknowledgment_is_rejected(self):
        self.capstone()
        self.prepare_shared()
        state = services.payload(self.project, self.other)
        services.save_system_titles(self.project, self.first, self.titles('Changed system'))
        self.client.force_authenticate(self.other)
        response = self.client.post(f'{fixtures.URL}{self.project.pk}/', {
            'action': 'acknowledge', 'round_id': state['round_id'],
            'review_token': state['review_token']}, format='json')
        self.assertEqual(response.status_code, 409)

    def test_stale_module_confirmation_cannot_overwrite_updated_names(self):
        concepts.save_titles(self.team, self.event, self.titles('Initial module'), actor=self.pm)
        token = concepts.module_review_token(self.team, self.event)
        concepts.save_titles(self.team, self.event, self.titles('Updated module'), actor=self.pm)
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/repository/deliverables/concepts/', {
            'team_id': self.team.pk, 'stage_label': self.event.label, 'action': 'save_titles',
            'concepts': self.titles('Stale confirmation'), 'review_token': token}, format='json')
        self.assertEqual(response.status_code, 409, response.data)
