"""Concept selection relaxes rubric roles without changing normal scheduling."""
from uuid import uuid4

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from repository import title_workflow
from repository.deliverables import concepts
from student_teams.services import mark_stage_ready

from . import test_capstone_planning as fixtures
from .models import DefenseSchedule


class ConceptSchedulingTests(APITestCase):
    setUp = fixtures.CapstoneWorkspaceTests.setUp
    make_team = fixtures.CapstoneWorkspaceTests.make_team
    save_people = fixtures.CapstoneWorkspaceTests.save_people
    inputs = fixtures.CapstoneWorkspaceTests.inputs
    url = fixtures.CapstoneWorkspaceTests.url

    def configure_concept(self, *, clear_optional_rubrics=True):
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        if clear_optional_rubrics:
            self.config.adviser_rubric = self.config.peer_rubric = None
        self.config.save()
        current = concepts.get_round(self.team, self.stage)
        for item in current.concepts:
            title_workflow.team_action(self.team, self.stage, self.team.leader,
                'submit_title', item['key'], title=f'Candidate project {item["key"]}')
            title_workflow.team_action(self.team, self.stage, self.adviser,
                'accept_title', item['key'])
        concepts.endorse(self.team, self.stage, self.adviser)
        mark_stage_ready(self.team, self.stage, user=self.adviser)

    def preview(self):
        return self.client.post(self.url + 'generate-plan/', self.inputs(), format='json')

    def direct(self):
        return self.client.post(self.url, {
            'scope': 'capstone', 'semester_id': self.term.pk,
            'defense_stage_id': self.stage.pk, 'team_id': self.team.pk,
            'scheduled_date': '2026-11-16', 'start_time': '08:00',
            'slot_duration': 20, 'room': '301', **self.roster,
        }, format='json')

    def test_concept_preview_and_confirmation_accept_only_published_panel(self):
        self.configure_concept()
        self.assertEqual(self.save_people().status_code, 200)
        with CaptureQueriesContext(connection) as queries:
            preview = self.preview()
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertFalse(any(q['sql'].lstrip().split()[0].upper() in
            {'INSERT', 'UPDATE', 'DELETE'} for q in queries))
        self.assertFalse(DefenseSchedule.objects.exists())
        confirmed = self.client.post(self.url + 'confirm-plan/', {
            'planning_mode': 'adviser_auto', 'preview_token': preview.data['preview_token'],
            'idempotency_key': str(uuid4()),
        }, format='json')
        self.assertEqual(confirmed.status_code, 201, confirmed.data)
        policy = DefenseSchedule.objects.get().assessment_policy
        self.assertEqual(policy['evaluation_mode'], 'panel_only_concept')
        self.assertEqual(policy['weights'], {
            'panel_weight': 100, 'adviser_weight': 0, 'peer_weight': 0,
        })

    def test_direct_concept_schedule_uses_the_same_panel_only_policy(self):
        self.configure_concept()
        response = self.direct()
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(DefenseSchedule.objects.get().assessment_policy['evaluation_mode'],
            'panel_only_concept')

    def test_unused_adviser_and_peer_drafts_do_not_block_concept_preview(self):
        self.configure_concept(clear_optional_rubrics=False)
        self.config.adviser_rubric.status = self.config.peer_rubric.status = 'draft'
        self.config.adviser_rubric.save()
        self.config.peer_rubric.save()
        self.config.save()
        self.assertEqual(self.save_people().status_code, 200)
        preview = self.preview()
        self.assertEqual(preview.status_code, 200, preview.data)

    def test_concept_endorsement_is_still_required(self):
        self.configure_concept()
        concepts.invalidate_clearance(self.team, self.stage.label)
        self.assertEqual(self.save_people().status_code, 200)
        for schedule in (self.preview, self.direct):
            with self.subTest(path=schedule.__name__):
                response = schedule()
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('not endorsed', str(response.data))
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_normal_stage_still_requires_adviser_and_peer_rubrics(self):
        # A familiar label does not enable concept-selection policy.
        self.stage.label = 'Concept Proposal'
        self.stage.concept_config = {'enabled': False}
        self.stage.save()
        self.config.adviser_rubric = self.config.peer_rubric = None
        self.config.save()
        self.assertEqual(self.save_people().status_code, 200)
        for schedule in (self.preview, self.direct):
            with self.subTest(path=schedule.__name__):
                response = schedule()
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('adviser', str(response.data))
                self.assertIn('peer', str(response.data))
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_normal_preview_still_requires_all_configured_rubrics_published(self):
        self.assertEqual(self.save_people().status_code, 200)
        for rubric in (self.config.adviser_rubric, self.config.peer_rubric):
            with self.subTest(role=rubric.evaluation_type):
                rubric.status = 'draft'
                rubric.save()
                response = self.preview()
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('Publish all configured stage rubrics', str(response.data))
                rubric.status = 'published'
                rubric.save()

    def test_concept_still_requires_a_panel_rubric(self):
        self.configure_concept()
        self.config.panel_rubric = None
        self.config.save()
        self.assertEqual(self.save_people().status_code, 200)
        for schedule in (self.preview, self.direct):
            with self.subTest(path=schedule.__name__):
                response = schedule()
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('panel rubric', str(response.data))
                self.assertNotIn('adviser/peer', str(response.data))

    def test_concept_still_requires_a_published_panel_rubric_in_both_paths(self):
        self.configure_concept()
        self.config.panel_rubric.status = 'draft'
        self.config.panel_rubric.save()
        self.assertEqual(self.save_people().status_code, 200)
        for schedule in (self.preview, self.direct):
            with self.subTest(path=schedule.__name__):
                response = schedule()
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('publish', str(response.data).lower())

    def test_concept_still_requires_the_qualifying_score_in_both_paths(self):
        self.configure_concept()
        self.stage.qualifying_score = None
        self.stage.save()
        self.assertEqual(self.save_people().status_code, 200)
        for schedule in (self.preview, self.direct):
            with self.subTest(path=schedule.__name__):
                response = schedule()
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('qualifying', str(response.data))

    def test_confirmation_rechecks_a_changed_concept_flag(self):
        self.configure_concept()
        self.assertEqual(self.save_people().status_code, 200)
        preview = self.preview()
        self.assertEqual(preview.status_code, 200, preview.data)
        self.stage.concept_config = {'enabled': False}
        self.stage.save()
        response = self.client.post(self.url + 'confirm-plan/', {
            'planning_mode': 'adviser_auto', 'preview_token': preview.data['preview_token'],
            'idempotency_key': str(uuid4()),
        }, format='json')
        self.assertEqual(response.status_code, 409, response.data)
        self.assertFalse(DefenseSchedule.objects.exists())
