from datetime import time

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from defense.stages.models import StageDeliverable
from defense.stages.serializers import DefenseStageWriteSerializer
from defense.scheduler.models import DefenseSchedule
from student_teams.concept_policy import context_key, resolve_policy
from student_teams.models import SectionAssignment
from . import concepts
from .models import ConceptRound
from .services import upsert_submission, required_complete, review_submission, stage_payload, endorse_team
from . import test_submission_timing as fixtures


class AssignedConceptTests(APITestCase):
    setUp = fixtures.faculty_review_setup

    def configure(self, *, assigned=True):
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        self.paper.file_policy = {'mode': 'concepts'}
        self.paper.save()
        self.team.section = 'BSIT-3A'
        self.team.concept_assignment = {'mode': 'assigned' if assigned else 'proposals',
            'assigned_title': 'School assigned module' if assigned else '', 'project_version': 1}
        self.team.save()
        if assigned:
            # Captured legacy hearings keep their one-concept policy until an
            # explicit reviewed conversion. New imports use stage counts.
            ConceptRound.objects.create(team=self.team, defense_stage=self.stage, project_version=1,
                number=1, concepts=[{'key': 'c1', 'title': 'School assigned module', 'decision': '', 'remarks': ''}],
                policy_snapshot={**self.stage.concept_config, 'mode': 'assigned', 'required_count': 1,
                    'assigned_title': 'School assigned module', 'source': 'import'})

    def upload(self, key='c1:paper'):
        return upsert_submission(self.team, self.stage.label, 'PAPER', 'paper.pdf', '10 B', self.student,
            file=SimpleUploadedFile('paper.pdf', b'assigned concept test'), slot_key=key)

    def update_policy(self, policy, *, team_policy=None, confirm=False):
        self.client.force_authenticate(self.admin)
        change = {'context_key': context_key(self.stage), 'section_policy': policy}
        if team_policy:
            change['team_policies'] = [{'team_id': self.team.pk, 'policy': team_policy}]
        return self.client.patch(f'/api/teams/{self.team.pk}/section/', {
            'expected_section': self.team.section, 'section': self.team.section,
            'concept_policy_changes': [change], 'confirm_concept_changes': confirm}, format='json')

    def test_assigned_team_needs_one_accepted_paper_and_still_needs_endorsement(self):
        self.configure()
        payload = stage_payload(self.team, self.stage.label)
        self.assertEqual(payload['concept_workflow']['concepts'][0]['title'], 'School assigned module')
        self.assertEqual(len(next(d for d in payload['pre'] if d['id'] == 'PAPER')['document_slots']), 1)
        self.assertFalse(payload['concept_workflow']['can_edit_titles'])
        submission = self.upload()
        self.assertFalse(required_complete(self.team, self.stage.label))
        row = submission.files.get(is_current=True)
        review_submission(self.team, self.stage.label, 'PAPER', 'accepted', '', self.adviser, file_id=row.pk)
        self.assertTrue(required_complete(self.team, self.stage.label))
        self.assertFalse(concepts.clearance_valid(self.team, self.stage))
        endorse_team(self.team, self.stage.label, self.adviser)
        self.assertEqual(stage_payload(self.team, self.stage.label)['concept_workflow']['status'], 'ready_to_schedule')

    def test_unassigned_title_changes_do_not_turn_three_proposals_into_one(self):
        self.configure(assigned=False)
        self.team.project_title = 'Later selected official project'
        self.team.save()
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 3)
        self.upload()
        self.assertFalse(required_complete(self.team, self.stage.label))

    def test_extra_paper_and_assignment_title_changes_are_rejected(self):
        self.configure()
        with self.assertRaises(ValueError):
            self.upload('c2:paper')
        with self.assertRaises(PermissionError):
            concepts.save_titles(self.team, self.stage, [{'key': 'c1', 'title': 'Unauthorized title'}])

    def test_shared_system_name_alone_does_not_assign_a_module(self):
        self.configure(assigned=False)
        SectionAssignment.objects.create(section=self.team.section, semester=self.semester,
            year_level=self.team.year_level, system_name='School shared system')
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 3)

    def test_section_and_team_overrides_take_precedence_and_require_assignment(self):
        self.configure(assigned=False)
        response = self.update_policy({'mode': 'assigned'})
        self.assertEqual(response.status_code, 200, response.data)
        response = self.update_policy({'mode': 'proposals', 'required_count': 2},
            team_policy={'mode': 'assigned', 'assigned_title': 'Admin assigned project'})
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        policy = resolve_policy(self.team, self.stage)
        self.assertEqual((policy['required_count'], policy['seed_title']), (3, 'Admin assigned project'))
        self.assertEqual(response.data['concept_contexts'][0]['teams'][0]['effective_policy'], policy)

    def test_submitted_papers_require_review_and_are_preserved_after_policy_change(self):
        self.configure()
        submission = self.upload()
        file = submission.files.get(is_current=True)
        original_round = concepts.latest_round(self.team, self.stage)
        response = self.update_policy({'mode': 'proposals', 'required_count': 3})
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(ConceptRound.objects.filter(team=self.team).count(), 1)
        response = self.update_policy({'mode': 'proposals', 'required_count': 3}, confirm=True)
        self.assertEqual(response.status_code, 200, response.data)
        original_round.refresh_from_db()
        file.refresh_from_db()
        self.assertEqual(original_round.verdict, 'policy_changed')
        self.assertEqual(len(original_round.documents_snapshot[0]['files']), 1)
        self.assertFalse(file.is_current)
        self.assertTrue(file.file.storage.exists(file.file.name))
        self.team.refresh_from_db()
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 3)
        self.assertFalse(required_complete(self.team, self.stage.label))

    def test_scheduled_hearing_cannot_be_reconfigured_even_with_confirmation(self):
        self.configure()
        current = concepts.get_round(self.team, self.stage)
        current.schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, scheduled_date=self.date, start_time=time(9), room='Room 201', created_by=self.admin)
        current.save()
        response = self.update_policy({'mode': 'proposals', 'required_count': 3}, confirm=True)
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 1)

    def test_pinned_count_survives_stage_changes_and_new_project_ignores_old_assignment(self):
        self.configure()
        concepts.get_round(self.team, self.stage)
        self.stage.concept_config['required_count'] = 5
        self.stage.save()
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 1)
        self.team.project_version = 2
        self.team.save()
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 5)

    def test_import_assignment_applies_only_to_its_concept_context(self):
        from defense.stages.models import DefenseStage
        self.configure()
        self.team.concept_assignment['context_key'] = context_key(self.stage)
        self.team.save()
        another = DefenseStage.objects.create(label='Separate Concept Hearing', display_order=99,
            concept_config={'enabled': True, 'required_count': 2})
        self.assertEqual(resolve_policy(self.team, another)['required_count'], 2)

    def test_assignment_changes_in_a_different_term_do_not_affect_this_team(self):
        from academic_period_management.models import Semester
        self.configure(assigned=False)
        historical = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        SectionAssignment.objects.create(section=self.team.section, semester=historical,
            year_level=self.team.year_level, concept_policies={context_key(self.stage): {'mode': 'assigned'}})
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 3)

    def test_legacy_team_with_title_keeps_stage_default(self):
        self.configure(assigned=False)
        self.team.concept_assignment = {}
        self.team.save()
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 3)

    def test_enabling_automatically_adds_one_paper_definition_and_reuses_it(self):
        self.stage.deliverables.all().delete()
        self.stage.concept_config = {}
        self.stage.save()
        serializer = DefenseStageWriteSerializer(self.stage, data={'concept_config': {'enabled': True}}, partial=True)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        serializer.save()
        paper = self.stage.deliverables.get(file_policy__mode='concepts')
        self.assertEqual((paper.label, paper.file_format, paper.required, paper.is_defense_material),
                         ('Concept Papers', 'pdf', True, True))
        serializer = DefenseStageWriteSerializer(self.stage, data={'concept_config': {'enabled': True}}, partial=True)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        serializer.save()
        self.assertEqual(self.stage.deliverables.get(file_policy__mode='concepts').pk, paper.pk)
        serializer = DefenseStageWriteSerializer(self.stage, data={'concept_config': {'enabled': False}}, partial=True)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        serializer.save()
        self.assertFalse(StageDeliverable.objects.filter(pk=paper.pk).exists())
        self.assertFalse(self.stage.deliverables.exists())

    def test_disabling_keeps_manually_authored_concept_requirements(self):
        self.configure()
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'/api/defense/stages/{self.stage.pk}/',
            {'concept_config': {'enabled': False}}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(StageDeliverable.objects.filter(pk=self.paper.pk).exists())

    def test_disabling_cannot_remove_automatic_papers_with_submissions(self):
        self.configure()
        self.paper.file_policy = {'mode': 'concepts', 'auto_added_for': 'concept_selection'}
        self.paper.save()
        self.upload()
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'/api/defense/stages/{self.stage.pk}/',
            {'concept_config': {'enabled': False}}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.stage.refresh_from_db()
        self.assertTrue(self.stage.concept_config['enabled'])
        self.assertTrue(StageDeliverable.objects.filter(pk=self.paper.pk).exists())
        self.assertTrue(self.team.deliverable_submissions.filter(deliverable_id='PAPER').exists())
