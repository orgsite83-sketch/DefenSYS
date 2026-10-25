"""Configured totals, retained input and reviewed expansion of legacy sets."""
from copy import deepcopy
from datetime import time

from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule
from student_teams.concept_policy import resolve_policy, context_key
from repository.section_concepts import tests as shared_fixtures, services as shared
from . import concepts
from . import test_assigned_concepts as fixtures
from .services import required_complete, upsert_submission


class ConfiguredConceptTests(APITestCase):
    setUp = fixtures.AssignedConceptTests.setUp
    configure = fixtures.AssignedConceptTests.configure
    upload = fixtures.AssignedConceptTests.upload
    update_policy = fixtures.AssignedConceptTests.update_policy

    def test_supplied_title_uses_stage_count_despite_old_overrides(self):
        self.configure(assigned=False)
        self.stage.concept_config['required_count'] = 4
        self.stage.save()
        self.team.concept_assignment = {'project_version': 1, 'context_key': context_key(self.stage),
            'mode': 'assigned', 'assigned_title': 'Imported first concept'}
        self.team.concept_policies = {f'{context_key(self.stage)}:v1': {'mode': 'proposals', 'required_count': 2}}
        self.team.save()
        current = concepts.get_round(self.team, self.stage)
        self.assertEqual([c['title'] for c in current.concepts], ['Imported first concept', '', '', ''])
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 4)
        self.upload()
        self.assertFalse(required_complete(self.team, self.stage.label))
        self.assertIn('every concept', concepts.clearance_blocker(self.team, self.stage))

    def test_reviewed_expansion_preserves_title_and_current_file(self):
        self.configure()
        submission = self.upload()
        file = submission.files.get(is_current=True)
        original = concepts.latest_round(self.team, self.stage)
        self.client.force_authenticate(self.admin)
        body = {'expected_section': self.team.section, 'section': self.team.section,
            'concept_policy_changes': [{'context_key': context_key(self.stage), 'expected_required_count': 3, 'reconcile_team_ids': [self.team.pk]}]}
        url = f'/api/teams/{self.team.pk}/section/'
        self.assertEqual(self.client.patch(url, body, format='json').status_code, 400)
        original.refresh_from_db()
        self.assertEqual(len(original.concepts), 1)
        response = self.client.patch(url, {**body, 'confirm_concept_changes': True}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        original.refresh_from_db()
        file.refresh_from_db()
        self.assertEqual([c['title'] for c in original.concepts], ['School assigned module', '', ''])
        self.assertTrue(file.is_current)
        self.assertTrue(file.file.storage.exists(file.file.name))
        self.assertEqual(concepts.latest_round(self.team, self.stage).pk, original.pk)
        self.assertFalse(concepts.clearance_valid(self.team, self.stage))

    def test_scheduled_and_panel_requested_sets_cannot_expand(self):
        self.configure()
        current = concepts.latest_round(self.team, self.stage)
        current.schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, scheduled_date=self.date, start_time=time(9), room='Room', created_by=self.admin)
        current.save()
        with self.assertRaises(ValidationError):
            concepts.reconcile_initial_requirements(self.team, self.stage, self.admin)
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 1)
        current.schedule = None
        current.number = 2
        current.save()
        with self.assertRaises(ValidationError):
            concepts.reconcile_initial_requirements(self.team, self.stage, self.admin)

    def test_reconciliation_does_not_remove_existing_concepts(self):
        self.configure(assigned=False)
        current = concepts.get_round(self.team, self.stage)
        before = deepcopy(current.concepts)
        self.stage.concept_config['required_count'] = 2
        self.stage.save()
        with self.assertRaises(ValidationError):
            concepts.reconcile_initial_requirements(self.team, self.stage, self.admin)
        current.refresh_from_db()
        self.assertEqual(current.concepts, before)

    def test_stale_review_cannot_apply_a_different_count(self):
        self.configure()
        self.stage.concept_config['required_count'] = 4
        self.stage.save()
        with self.assertRaisesMessage(ValidationError, 'count changed'):
            concepts.reconcile_initial_requirements(self.team, self.stage, self.admin, expected_count=3)
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 1)


class ConfiguredSharedConceptTests(APITestCase):
    setUp = shared_fixtures.SharedSystemConceptTests.setUp
    rubric = shared_fixtures.SharedSystemConceptTests.rubric
    configure = shared_fixtures.SharedSystemConceptTests.configure
    data = shared_fixtures.SharedSystemConceptTests.data
    slot = shared_fixtures.SharedSystemConceptTests.slot

    def test_initial_shared_set_uses_four_configured_alternatives_and_seeded_titles(self):
        # Existing section remains captured at three; a different enabled event
        # starts with four matching system/module slots.
        from defense.scheduler.models import PitEventGradingConfig
        event = PitEventGradingConfig.objects.create(semester=self.semester,
            year_level=self.team.year_level, event_name='Four concept event',
            concept_config={'enabled': True, 'required_count': 4})
        self.project.section.system_name = 'Imported shared system'
        self.project.section.save()
        self.team.concept_assignment = {'mode': 'proposals', 'project_version': 1,
            'context_key': context_key(event), 'seed_title': 'Imported module'}
        self.team.save()
        project = shared.configure(self.first, [self.team, self.module_team], event,
            {'project_manager_id': self.pm.pk, 'reviewer_id': self.first.pk})
        current = concepts.get_round(self.team, event)
        self.assertEqual([c['title'] for c in current.concepts], ['Imported module', '', '', ''])
        self.assertEqual(list(shared.latest(project).systems.values_list('title', flat=True)), ['Imported shared system', '', '', ''])
        self.assertEqual(shared.payload(project, self.pm)['review_progress']['required'], 4)
        titles = [{'key': f'c{i}', 'title': f'Alternative {i}'} for i in range(1, 5)]
        self.client.force_authenticate(self.pm)
        state = shared.payload(project, self.pm)
        response = self.client.post(f'/api/repository/section-concepts/{project.pk}/', {
            'action': 'save_titles', 'round_id': state['round_id'], 'review_token': state['review_token'],
            'concepts': titles}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        shared.save_system_titles(project, self.first, titles)
        for i in range(1, 5):
            paper = shared.upload(project, self.pm, f'c{i}', SimpleUploadedFile('shared.pdf', b'%PDF-1.4 test'))
            shared.review(project, self.first, paper.pk, 'accepted')
            self.assertEqual(shared.shared_clearance(shared.latest(project)), i == 4)
        self.assertEqual(resolve_policy(self.module_team, event)['required_count'], 4)

    def test_shared_expansion_keeps_rows_and_module_file_versions(self):
        current = concepts.get_round(self.team, self.event)
        submission = upsert_submission(self.team, self.event.label, 'CONCEPTS', 'module.pdf', '10 B', self.pm,
            file=SimpleUploadedFile('module.pdf', b'%PDF-1.4 retained module'), slot_key='c1:paper')
        original_file = submission.files.get(is_current=True)
        first_system_id = shared.latest(self.project).systems.get(key='c1').pk
        self.event.concept_config['required_count'] = 4
        self.event.save()
        shared.reconcile_requirements(self.project, self.first)
        current.refresh_from_db()
        self.assertEqual(len(current.concepts), 4)
        self.assertEqual(shared.latest(self.project).systems.get(key='c1').pk, first_system_id)
        original_file.refresh_from_db()
        self.assertTrue(original_file.is_current)
        self.assertEqual(submission.files.count(), 1)
        self.assertEqual(resolve_policy(self.module_team, self.event)['required_count'], 4)

    def test_shared_api_rejects_a_stale_count_and_supports_ten_slots(self):
        self.event.concept_config['required_count'] = 10
        self.event.save()
        self.client.force_authenticate(self.first)
        state = shared.payload(self.project, self.first)
        body = {'action': 'reconcile_requirements', 'round_id': state['round_id'],
            'review_token': state['review_token'], 'expected_required_count': 4}
        url = f'/api/repository/section-concepts/{self.project.pk}/'
        self.assertEqual(self.client.post(url, body, format='json').status_code, 400)
        response = self.client.post(url, {**body, 'expected_required_count': 10}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([s['key'] for s in response.data['systems']], [f'c{i}' for i in range(1, 11)])
        self.assertEqual(response.data['review_progress']['required'], 10)

    def test_confirmed_first_module_does_not_lock_remaining_proposals(self):
        current = concepts.get_round(self.team, self.event)
        current.concepts[0].update(title='Faculty supplied module', faculty_confirmed=True)
        current.save()
        titles = [{'key': f'c{i}', 'title': 'Faculty supplied module' if i == 1 else f'Additional module {i}'} for i in range(1, 4)]
        concepts.save_titles(self.team, self.event, titles, actor=self.pm)
        current.refresh_from_db()
        self.assertTrue(current.concepts[0]['faculty_confirmed'])
        self.assertFalse(current.concepts[1]['faculty_confirmed'])
        titles[0]['title'] = 'Changed confirmed name'
        with self.assertRaises(PermissionError):
            concepts.save_titles(self.team, self.event, titles, actor=self.pm)
