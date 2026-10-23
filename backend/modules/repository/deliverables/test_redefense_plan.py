"""Panel-directed repeat requirements use fresh evidence and existing review gates."""
from pathlib import Path

from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule
from defense.stages.models import StageDeliverable
from grading.grades.models import TeamGrade
from student_teams.concept_policy import resolve_policy
from . import concepts
from .documents import current_files, slots_for
from .models import ConceptRound
from .services import (upsert_submission, review_submission, endorse_team, stage_payload,
                       get_deliverable_definitions_for_team, remove_submission)
from . import test_concept_documents as document_fixtures


class ReDefensePlanTests(APITestCase):
    configure = document_fixtures.ConceptDocumentTests.configure
    upload = document_fixtures.ConceptDocumentTests.upload
    accept = document_fixtures.ConceptDocumentTests.accept

    def setUp(self):
        document_fixtures.ConceptDocumentTests.setUp(self)
        self.configure(slots=[{'key': 'paper', 'label': 'Paper', 'required': True},
                              {'key': 'scope', 'label': 'Scope sheet', 'required': True}])
        self.deck.file_policy = {'mode': 'multiple', 'min_files': 1, 'max_files': 3}
        self.deck.requirement_timing = 'scheduling'
        self.deck.required = True
        self.deck.save()
        self.general = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='CONSENT',
            label='Consent form', required=True, file_policy={'mode': 'single'})
        for i in range(1, 4):
            for slot in ('paper', 'scope'):
                submission = self.upload(f'c{i}:{slot}', f'concept{i}_{slot}.pdf')
                self.accept(submission, f'c{i}:{slot}')
        self.deck_submission = self.other_upload('DECK', 'slides.pptx')
        review_submission(self.team, self.stage.label, 'DECK', 'accepted', '', self.adviser)
        self.consent = self.other_upload('CONSENT', 'consent.pdf')
        review_submission(self.team, self.stage.label, 'CONSENT', 'accepted', '', self.adviser)
        self.consent.refresh_from_db()
        endorse_team(self.team, self.stage.label, self.adviser)
        self.schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, scheduled_date=self.date, start_time='09:00', room='First hearing')
        concepts.bind_schedule(self.schedule)
        self.grade = TeamGrade(team=self.team, semester=self.semester, defense_stage=self.stage,
            scope='capstone', schedule=self.schedule, verdict='for_redefense',
            verdict_remarks='Follow the concept-specific panel instructions.', verdict_by=self.admin)

    def other_upload(self, deliverable, name):
        return upsert_submission(self.team, self.stage.label, deliverable, name, '20 B', self.student,
            file=SimpleUploadedFile(name, b'file content'))

    def decide(self, requested):
        concepts.record_outcome(self.grade, [
            {'key': f'c{i}', 'decision': 'rejected', 'remarks': f'Panel feedback for concept {i}',
             'next_action': requested.get(f'c{i}', 'omit')} for i in range(1, 4)])
        self.grade.save()
        self.schedule.status = 'done'
        self.schedule.save(update_fields=['status'])
        return concepts.latest_round(self.team, self.stage)

    def definition(self):
        return next(d for d in get_deliverable_definitions_for_team(self.team, self.stage.label) if d['id'] == 'PAPER')

    def test_one_requested_concept_uses_its_original_key_and_both_documents(self):
        current = self.decide({'c2': 'revise'})
        self.assertEqual([c['key'] for c in current.concepts], ['c2'])
        self.assertEqual([s['key'] for s in slots_for(self.definition(), stage=self.stage)], ['c2:paper', 'c2:scope'])
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 1)
        self.stage.refresh_from_db()
        self.assertEqual(self.stage.concept_config['required_count'], 3)
        self.assertEqual(current.concepts[0]['title'], 'Candidate project 2')
        self.assertEqual(current.concepts[0]['panel_feedback'], 'Panel feedback for concept 2')
        self.assertFalse(ConceptRound.objects.get(schedule=self.schedule).replacement_required)

    def test_two_requests_can_mix_revision_and_replacement(self):
        current = self.decide({'c1': 'revise', 'c3': 'replace'})
        self.assertEqual([c['key'] for c in current.concepts], ['c1', 'c3'])
        self.assertEqual(current.concepts[0]['title'], 'Candidate project 1')
        self.assertEqual(current.concepts[1]['title'], '')
        self.assertEqual(current.concepts[1]['previous_title'], 'Candidate project 3')
        self.assertEqual(len(slots_for(self.definition(), stage=self.stage)), 4)
        self.assertTrue(ConceptRound.objects.get(schedule=self.schedule).replacement_required)

    def test_all_three_may_be_revised_without_forcing_replacements(self):
        current = self.decide({f'c{i}': 'revise' for i in range(1, 4)})
        self.assertEqual(len(current.concepts), 3)
        self.assertTrue(all(c['title'] for c in current.concepts))
        self.assertFalse(ConceptRound.objects.get(schedule=self.schedule).replacement_required)

    def test_empty_or_partial_plans_are_rejected_without_starting_another_round(self):
        with self.assertRaises(ValidationError):
            self.decide({})
        self.assertEqual(ConceptRound.objects.filter(team=self.team).count(), 1)
        decisions = [{'key': f'c{i}', 'decision': 'revise', 'remarks': 'Revise scope'} for i in range(1, 4)]
        decisions[0]['next_action'] = 'revise'
        with self.assertRaises(ValidationError):
            concepts.record_outcome(self.grade, decisions)
        self.assertEqual(ConceptRound.objects.filter(team=self.team).count(), 1)

    def test_old_evidence_is_historical_and_general_accepted_file_remains_current(self):
        paper = self.team.deliverable_submissions.get(deliverable_id='PAPER')
        originals = list(paper.files.all())
        self.decide({'c2': 'revise'})
        paper.refresh_from_db()
        self.deck_submission.refresh_from_db()
        self.consent.refresh_from_db()
        self.assertEqual(current_files(paper), [])
        self.assertEqual(paper.files.count(), 6)
        self.assertEqual(self.deck_submission.status, 'pending')
        self.assertFalse(self.deck_submission.file)
        self.assertEqual(self.consent.status, 'accepted')
        self.assertEqual(len(current_files(self.consent)), 1)
        for file in originals:
            file.refresh_from_db()
            self.assertEqual(file.status, 'accepted')
            self.assertTrue(Path(file.file.path).exists())
        self.schedule.refresh_from_db()
        self.assertTrue(self.schedule.documents_snapshot)
        payload = stage_payload(self.team, self.stage.label)
        consent = next(d for d in payload['pre'] if d['id'] == 'CONSENT')
        self.assertFalse(consent['can_upload'])
        self.assertTrue(consent['uploaded'])
        self.assertFalse(payload['vault_unlocked'])
        with self.assertRaises(PermissionError):
            self.other_upload('CONSENT', 'changed_consent.pdf')

    def test_new_versions_require_acceptance_and_fresh_endorsement_relocks_files(self):
        self.decide({'c2': 'revise'})
        with self.assertRaises(ValueError):
            endorse_team(self.team, self.stage.label, self.adviser)
        with self.assertRaises(ValueError):
            self.upload('c1:paper')
        for slot in ('paper', 'scope'):
            submission = self.upload(f'c2:{slot}', f'new_{slot}.pdf')
            self.assertEqual(next(f for f in current_files(submission) if f.slot_key == f'c2:{slot}').revision, 2)
            self.accept(submission, f'c2:{slot}')
        self.other_upload('DECK', 'revised_slides.pptx')
        with self.assertRaises(ValueError):
            endorse_team(self.team, self.stage.label, self.adviser)
        review_submission(self.team, self.stage.label, 'DECK', 'accepted', '', self.adviser)
        endorse_team(self.team, self.stage.label, self.adviser)
        with self.assertRaises(PermissionError):
            self.upload('c2:paper', 'after_endorsement.pdf')
        payload = stage_payload(self.team, self.stage.label)
        self.assertTrue(payload['endorsed'])
        self.assertTrue(all(not item['can_upload'] for item in payload['pre']))
        self.assertTrue(all(not item['can_faculty_review'] for item in payload['pre']))

    def test_removing_a_new_upload_preserves_previously_presented_files(self):
        self.decide({'c2': 'revise'})
        self.other_upload('DECK', 'new_slides.pptx')
        remove_submission(self.team, self.stage.label, 'DECK')
        self.deck_submission.refresh_from_db()
        self.assertTrue(self.deck_submission.files.exists())
        old = self.deck_submission.files.get(file_name='slides.pptx')
        self.assertTrue(Path(old.file.path).exists())

    def test_section_defaults_cannot_reset_a_chair_requested_set(self):
        from student_teams.models import SectionAssignment
        from student_teams.concept_policy import context_key
        from student_teams.section_concept_policies import apply_policy_changes
        self.decide({'c2': 'revise'})
        self.team.section = 'BSIT-3A'
        self.team.save()
        assignment = SectionAssignment.objects.create(section=self.team.section,
            semester=self.semester, year_level=self.team.year_level)
        apply_policy_changes(self.team, [self.team], assignment, [{'context_key': context_key(self.stage),
            'section_policy': {'mode': 'proposals', 'required_count': 3}}], confirmed=True)
        self.assertEqual([c['key'] for c in concepts.latest_round(self.team, self.stage).concepts], ['c2'])
        self.assertEqual(ConceptRound.objects.filter(team=self.team).count(), 2)


class AssignedReplacementPlanTests(APITestCase):
    def setUp(self):
        from . import test_assigned_concepts as assigned_fixtures
        assigned_fixtures.AssignedConceptTests.setUp(self)
        assigned_fixtures.AssignedConceptTests.configure(self)
        sub = assigned_fixtures.AssignedConceptTests.upload(self)
        review_submission(self.team, self.stage.label, 'PAPER', 'accepted', '', self.adviser, file_id=current_files(sub)[0].pk)
        endorse_team(self.team, self.stage.label, self.adviser)

    def test_admin_assigns_replacement_without_losing_the_chairs_plan(self):
        from student_teams.models import SectionAssignment
        from student_teams.concept_policy import context_key
        from student_teams.section_concept_policies import apply_policy_changes
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=self.date, start_time='09:00', room='Assigned concept')
        concepts.bind_schedule(schedule)
        grade = TeamGrade(team=self.team, semester=self.semester, defense_stage=self.stage, scope='capstone',
            schedule=schedule, verdict='for_redefense', verdict_by=self.admin, verdict_remarks='Replace this assignment.')
        concepts.record_outcome(grade, [{'key': 'c1', 'decision': 'rejected', 'remarks': 'Use a different problem domain.',
                                        'next_action': 'replace'}])
        assignment = SectionAssignment.objects.create(section=self.team.section,
            semester=self.semester, year_level=self.team.year_level)
        apply_policy_changes(self.team, [self.team], assignment, [{'context_key': context_key(self.stage),
            'team_policies': [{'team_id': self.team.pk,
                              'policy': {'mode': 'assigned', 'assigned_title': 'New assigned module'}}]}], confirmed=True)
        current = concepts.latest_round(self.team, self.stage)
        self.assertEqual(current.concepts[0]['title'], 'New assigned module')
        self.assertEqual(current.concepts[0]['panel_feedback'], 'Use a different problem domain.')
        self.assertEqual(current.number, 2)
        self.assertEqual(current.policy_snapshot['concept_keys'], ['c1'])
        # A subsequent assignment edit cannot reuse an accepted paper for a
        # different assigned title or discard its previous uploaded version.
        submitted = upsert_submission(self.team, self.stage.label, 'PAPER', 'replacement.pdf', '10 B', self.student,
            file=SimpleUploadedFile('replacement.pdf', b'replacement paper'), slot_key='c1:paper')
        old_file = current_files(submitted)[0]
        from rest_framework.exceptions import ValidationError as ApiValidationError
        changes = [{'context_key': context_key(self.stage), 'team_policies': [{'team_id': self.team.pk,
            'policy': {'mode': 'assigned', 'assigned_title': 'Corrected assigned module'}}]}]
        with self.assertRaises(ApiValidationError):
            apply_policy_changes(self.team, [self.team], assignment, changes)
        apply_policy_changes(self.team, [self.team], assignment, changes, confirmed=True)
        submitted.refresh_from_db()
        old_file.refresh_from_db()
        self.assertEqual(current_files(submitted), [])
        self.assertFalse(old_file.is_current)
        self.assertTrue(Path(old_file.file.path).exists())
