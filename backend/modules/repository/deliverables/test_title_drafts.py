"""Leader title drafts retain fixed slots, permissions and hearing clearance."""
from datetime import time
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from defense.scheduler.models import DefenseSchedule
from student_teams.models import TeamMembership
from student_teams.concept_policy import context_key
from . import concepts
from . import test_assigned_concepts as fixtures
from .models import ConceptRound
from repository.section_concepts import tests as shared_fixtures

URL = '/api/repository/deliverables/concepts/'


class TitleDraftTests(APITestCase):
    setUp = fixtures.AssignedConceptTests.setUp
    configure = fixtures.AssignedConceptTests.configure

    def setup_draft(self):
        self.configure(assigned=False)
        self.team.concept_assignment = {'mode': 'proposals', 'project_version': 1,
            'context_key': context_key(self.stage), 'seed_title': 'Imported soil sensor concept'}
        self.team.save()
        self.client.force_authenticate(self.student)

    def load(self):
        return self.client.get(URL, {'team_id': self.team.pk, 'stage_label': self.stage.label})

    def save(self, workflow, titles, **extra):
        return self.client.post(f'{URL}?response_mode=concept_titles', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'action': 'save_draft_titles',
            'review_token': workflow['module_review_token'],
            'concepts': [{'key': f'c{i}', 'title': title} for i, title in enumerate(titles, 1)], **extra}, format='json')

    def test_loading_is_read_only_and_partial_save_preserves_imported_title(self):
        self.setup_draft()
        response = self.load()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(ConceptRound.objects.filter(team=self.team).exists())
        workflow = response.data['concept_workflow']
        self.assertTrue(workflow['can_edit_titles'])
        saved = self.save(workflow, ['Imported soil sensor concept', 'Second draft', ''])
        self.assertEqual(saved.status_code, 200, saved.data)
        self.assertEqual(saved.data['team_id'], self.team.pk)
        self.assertEqual(saved.data['concept_workflow']['title_progress']['remaining_count'], 1)
        current = concepts.latest_round(self.team, self.stage)
        self.assertEqual(len(current.concepts), 3)
        self.assertEqual(current.concepts[0]['title'], 'Imported soil sensor concept')
        self.assertFalse(concepts.titles_complete(current))
        self.assertIn('every concept', concepts.clearance_blocker(self.team, self.stage))
        with self.assertRaises(ValueError):
            concepts.endorse(self.team, self.stage, self.adviser)

    def test_stale_draft_cannot_overwrite_newer_titles(self):
        self.setup_draft()
        workflow = self.load().data['concept_workflow']
        self.assertEqual(self.save(workflow, ['Imported soil sensor concept', 'New version', '']).status_code, 200)
        self.assertEqual(self.save(workflow, ['Old version', '', '']).status_code, 409)
        self.assertEqual(concepts.latest_round(self.team, self.stage).concepts[1]['title'], 'New version')

    def test_member_can_read_but_only_leader_can_save(self):
        self.setup_draft()
        member = get_user_model().objects.create_user(username='title-draft-member', role='student')
        TeamMembership.objects.create(team=self.team, student=member)
        self.client.force_authenticate(member)
        response = self.load()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['concept_workflow']['can_edit_titles'])
        self.assertEqual(self.save(response.data['concept_workflow'], ['Changed', '', '']).status_code, 403)

    def test_fixed_slot_count_token_and_title_limits_are_enforced(self):
        self.setup_draft()
        workflow = self.load().data['concept_workflow']
        for titles, extra in ((['Only one'], {}), (['A', 'B', 'C'], {'review_token': ''}),
                              (['X' * 256, '', ''], {})):
            result = self.save(workflow, titles, **extra)
            self.assertIn(result.status_code, (400, 409), result.data)
        self.assertFalse(ConceptRound.objects.filter(team=self.team).exists())

    def test_scheduled_titles_are_read_only_and_cannot_be_saved(self):
        self.setup_draft()
        current = concepts.get_round(self.team, self.stage)
        current.schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, scheduled_date=self.date, start_time=time(9), room='Room', created_by=self.admin)
        current.save()
        workflow = self.load().data['concept_workflow']
        self.assertFalse(workflow['can_edit_titles'])
        self.assertIn(self.save(workflow, ['Changed', '', '']).status_code, (400, 403))

    def test_completed_stage_or_historical_semester_cannot_accept_drafts(self):
        from defense.stages.models import StageGradingConfig
        self.setup_draft()
        config, _ = StageGradingConfig.objects.get_or_create(defense_stage=self.stage, semester=self.semester)
        config.is_officially_complete = True
        config.save()
        workflow = self.load().data['concept_workflow']
        self.assertFalse(workflow['can_edit_titles'])
        self.assertIn(self.save(workflow, ['Changed', '', '']).status_code, (400, 403))
        config.is_officially_complete = False
        config.save()
        self.semester.is_active = False
        self.semester.save()
        historical = self.load()
        self.assertEqual(historical.status_code, 200, historical.data)
        self.assertFalse(historical.data['concept_workflow']['can_edit_titles'])
        self.assertEqual(self.save(historical.data['concept_workflow'], ['Changed', '', '']).status_code, 403)
        self.assertFalse(ConceptRound.objects.filter(team=self.team).exists())


class SharedTitleDraftTests(APITestCase):
    setUp = shared_fixtures.SharedSystemConceptTests.setUp
    configure = shared_fixtures.SharedSystemConceptTests.configure
    rubric = shared_fixtures.SharedSystemConceptTests.rubric
    data = shared_fixtures.SharedSystemConceptTests.data
    slot = shared_fixtures.SharedSystemConceptTests.slot

    def load(self):
        self.client.force_authenticate(self.pm)
        return self.client.get(URL, {'team_id': self.team.pk, 'stage_label': self.event.label})

    def save(self, workflow, titles):
        return self.client.post(f'{URL}?response_mode=concept_titles', {
            'team_id': self.team.pk, 'stage_label': self.event.label, 'action': 'save_draft_titles',
            'review_token': workflow['module_review_token'],
            'concepts': [{'key': f'c{i}', 'title': title} for i, title in enumerate(titles, 1)]}, format='json')

    def test_partial_shared_draft_preserves_confirmed_name_and_system_connections(self):
        current = concepts.get_round(self.team, self.event)
        current.concepts[0].update(title='Confirmed imported module', faculty_confirmed=True)
        current.save()
        workflow = self.load().data['concept_workflow']
        saved = self.save(workflow, ['Confirmed imported module', 'Alternative module draft', ''])
        self.assertEqual(saved.status_code, 200, saved.data)
        current.refresh_from_db()
        self.assertTrue(current.concepts[0]['faculty_confirmed'])
        self.assertFalse(current.concepts[1]['faculty_confirmed'])
        self.assertEqual(current.concepts[1]['title'], 'Alternative module draft')
        self.assertEqual(current.section_round_id, self.project.rounds.get().pk)
        self.assertEqual(saved.data['concept_workflow']['title_progress']['remaining_count'], 1)
        workflow = saved.data['concept_workflow']
        self.assertIn(self.save(workflow, ['Changed confirmed name', 'Other draft', '']).status_code, (400, 403))
        current.refresh_from_db()
        self.assertEqual(current.concepts[0]['title'], 'Confirmed imported module')
        self.assertEqual(current.concepts[1]['title'], 'Alternative module draft')

    def test_completed_shared_event_is_read_only(self):
        self.event.is_officially_complete = True
        self.event.save()
        workflow = self.load().data['concept_workflow']
        self.assertFalse(workflow['can_edit_titles'])
        self.assertIn(self.save(workflow, ['Changed', '', '']).status_code, (400, 403))
