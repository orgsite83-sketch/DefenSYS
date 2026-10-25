"""Selected-concept attachment groups, final clearance, and verdict isolation."""
from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase
from django.utils import timezone
from rest_framework.test import APITestCase

from defense.document_policy import validate_file_policy, with_concept_papers
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import StageDeliverable, StageGradingConfig
from defense.stages.serializers import DefenseStageWriteSerializer, StageDeliverableSerializer
from grading.grades.defense_workflow import apply_workflow_action, record_verdict
from grading.grades.services import GradeContextService, submit_panelist_grade
from grading.rubrics.models import Rubric, RubricCriterion
from . import concepts, test_submission_timing as fixtures
from .concept_completion import final_paper_complete
from .documents import current_files
from .services import (archive_unlocked, endorse_team, post_deliverables_complete,
                       review_submission, stage_payload, upsert_submission)


class ApprovedConceptPolicyTests(SimpleTestCase):
    def test_disabling_removes_saved_automatic_defaults_but_keeps_manual_papers(self):
        manual = [{'deliverable_id': 'D1', 'label': 'Concept Papers',
                   'deliverable_type': 'pre', 'file_policy': {'mode': 'single'}}]
        generated = with_concept_papers(manual, {'enabled': True})
        self.assertEqual(len(generated), 3)
        for item in generated[1:]:
            item['id'] = 10
            item['label'] = 'Custom ' + item['label']
        self.assertEqual(with_concept_papers(generated, {'enabled': False}), manual)
        self.assertEqual(len(generated), 3)

    def test_disabling_removes_legacy_automatic_defaults(self):
        generated = with_concept_papers([], {'enabled': True})
        for item in generated:
            item['file_policy'].pop('auto_added_for')
            item['deliverable_id'] += '_2'
        self.assertEqual(with_concept_papers(generated, {'enabled': False}), [])

    def test_setup_preserves_authored_attachment_limits_and_identifier(self):
        policy = {'mode': 'multiple', 'min_files': 2, 'max_files': 4}
        items = [{'deliverable_id': 'AUTHORED_FINAL', 'label': 'Approved Concept Paper',
                  'deliverable_type': 'post', 'file_policy': policy}]
        generated = with_concept_papers(items, {'enabled': True})
        final = next(d for d in generated if d['deliverable_id'] == 'AUTHORED_FINAL')
        self.assertEqual(final['file_policy'], {**policy, 'purpose': 'approved_concept'})
        self.assertEqual(generated, with_concept_papers(generated, {'enabled': True}))
        self.assertEqual(items[0]['file_policy'], policy)

    def test_selected_concept_accepts_single_or_multiple_but_not_per_proposal_slots(self):
        for mode in ('single', 'multiple'):
            self.assertEqual(validate_file_policy({'mode': mode, 'purpose': 'approved_concept'})['mode'], mode)
        for mode in ('concepts', 'named'):
            with self.assertRaises(ValidationError):
                validate_file_policy({'mode': mode, 'purpose': 'approved_concept'})
        with self.assertRaises(ValidationError):
            validate_file_policy({'mode': 'multiple', 'purpose': 'approved_concept', 'min_files': 3, 'max_files': 2})


class PostConceptAttachmentTests(APITestCase):
    setUp = fixtures.faculty_review_setup

    def prepare(self, verdict='approved_with_revisions', *, minimum=2, mode='multiple'):
        self.stage.concept_config = {'enabled': True, 'required_count': 1}
        self.stage.save()
        self.paper.file_policy = {'mode': 'concepts'}
        self.paper.file_format = 'pdf'
        self.paper.save()
        self.final = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='FINAL',
            label='Selected concept documents', deliverable_type='post', required=True, file_format='pdf',
            file_policy=({'mode': 'multiple', 'min_files': minimum, 'max_files': 3, 'purpose': 'approved_concept'}
                         if mode == 'multiple' else {'mode': mode, 'purpose': 'approved_concept'}))
        concepts.save_titles(self.team, self.stage, [{'key': 'c1', 'title': 'Selected project'}])
        initial = upsert_submission(self.team, self.stage.label, 'PAPER', 'proposal.pdf', '10 B', self.student,
            file=SimpleUploadedFile('proposal.pdf', b'%PDF-1.4 proposal'), slot_key='c1:paper')
        review_submission(self.team, self.stage.label, 'PAPER', 'accepted', '', self.adviser,
                          file_id=initial.files.get(is_current=True).pk)
        endorse_team(self.team, self.stage.label, self.adviser)
        self.chair = get_user_model().objects.create_user(username='attachment-chair', role='faculty')
        rubric = Rubric.objects.create(name='Attachment panel', scope='capstone', semester=self.semester,
            defense_stage=self.stage, evaluation_type='panel', status='published', created_by=self.admin)
        criterion = RubricCriterion.objects.create(rubric=rubric, name='Presentation', scale=Rubric.SCALE_10, max_score=10)
        StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.semester, panel_rubric=rubric,
            panel_weight=100, adviser_weight=0, peer_weight=0)
        self.schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, rubric=rubric, scheduled_date=timezone.localdate(), start_time='09:00', room='Attachments')
        SchedulePanelist.objects.create(schedule=self.schedule, panelist=self.chair, is_chair=True)
        self.grade, _, _ = GradeContextService.get_or_create_for_schedule(self.schedule)
        submit_panelist_grade(self.schedule, self.grade, [{'criterion_id': criterion.pk, 'score': 8}], panelist=self.chair)
        decision = verdict if verdict in ('approved', 'approved_with_revisions') else 'rejected'
        record_verdict(self.grade, actor=self.chair, verdict=verdict, remarks='Recorded panel feedback.',
            concept_decisions=[{'key': 'c1', 'decision': decision, 'remarks': 'Recorded panel feedback.',
                                'next_action': 'revise' if verdict == 'for_redefense' else 'omit'}])

    def upload_final(self, name='final.pdf', *, file_id=None):
        return upsert_submission(self.team, self.stage.label, 'FINAL', name, '10 B', self.student,
            file=SimpleUploadedFile(name, b'%PDF-1.4 final attachment'), file_id=file_id)

    def accept(self, submission, *, clear=False):
        file = max(current_files(submission), key=lambda f: f.pk)
        review_submission(self.team, self.stage.label, 'FINAL', 'accepted', '', self.adviser,
                          file_id=file.pk, clear_defense_revisions=clear)
        submission.refresh_from_db()
        return file

    def test_partial_review_cannot_clear_revisions_and_corrections_keep_history(self):
        self.prepare()
        sub = self.upload_final()
        first = self.accept(sub)
        with self.assertRaises(PermissionError):
            self.upload_final('unreviewed-replacement.pdf', file_id=first.pk)
        self.assertFalse(final_paper_complete(self.team, self.stage, required=True))
        with self.assertRaises(ValidationError):
            apply_workflow_action(self.grade, actor=self.adviser, action='clear_revisions', reason='Checked files.')
        sub = self.upload_final('appendix.pdf')
        second = max(current_files(sub), key=lambda f: f.pk)
        review_submission(self.team, self.stage.label, 'FINAL', 'rejected', 'Correct the appendix.', self.adviser,
                          file_id=second.pk)
        self.assertFalse(post_deliverables_complete(self.team, self.stage.label))
        sub = self.upload_final('corrected.pdf', file_id=second.pk)
        replacement = self.accept(sub, clear=True)
        hearing = concepts.latest_round(self.team, self.stage)
        self.assertEqual((replacement.concept_round_id, replacement.selected_concept_key), (hearing.pk, 'c1'))
        self.assertEqual(sub.files.count(), 3)
        self.assertEqual(len(current_files(sub)), 2)
        first.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(first.status, 'accepted')
        self.assertFalse(second.is_current)
        self.assertTrue(final_paper_complete(self.team, self.stage, required=True))
        self.assertTrue(post_deliverables_complete(self.team, self.stage.label))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved_with_revisions')
        self.assertIsNotNone(self.grade.revisions_cleared_at)

    def test_minimum_one_still_requires_review_of_other_current_attachments(self):
        self.prepare(minimum=1)
        sub = self.upload_final()
        first = current_files(sub)[0]
        sub = self.upload_final('support.pdf')
        review_submission(self.team, self.stage.label, 'FINAL', 'accepted', '', self.adviser, file_id=first.pk)
        sub.refresh_from_db()
        self.assertEqual(sub.status, 'pending')
        self.assertFalse(final_paper_complete(self.team, self.stage))
        self.assertFalse(post_deliverables_complete(self.team, self.stage.label))
        self.accept(sub)
        self.assertTrue(final_paper_complete(self.team, self.stage))

    def test_plain_approval_requires_other_post_groups_and_preserves_captured_limits(self):
        matrix = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='MATRIX',
            label='Revision Matrix', deliverable_type='post', required=True, file_format='pdf',
            file_policy={'mode': 'multiple', 'min_files': 2, 'max_files': 3})
        self.prepare('approved')
        sub = self.upload_final()
        self.accept(sub)
        sub = self.upload_final('support.pdf')
        self.accept(sub)
        self.assertFalse(post_deliverables_complete(self.team, self.stage.label))
        for number in range(2):
            row = upsert_submission(self.team, self.stage.label, 'MATRIX', f'matrix{number}.pdf', '10 B', self.student,
                file=SimpleUploadedFile(f'matrix{number}.pdf', b'%PDF-1.4 matrix'))
            review_submission(self.team, self.stage.label, 'MATRIX', 'accepted', '', self.adviser,
                              file_id=max(current_files(row), key=lambda f: f.pk).pk)
        self.assertTrue(post_deliverables_complete(self.team, self.stage.label))
        matrix.file_policy['min_files'] = 3
        matrix.save()
        self.assertTrue(post_deliverables_complete(self.team, self.stage.label))
        self.assertTrue(stage_payload(self.team, self.stage.label)['archive_complete'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')

    def test_wrong_hearing_or_selected_concept_never_counts_as_final_evidence(self):
        self.prepare()
        sub = self.upload_final()
        first = self.accept(sub)
        sub = self.upload_final('support.pdf')
        self.accept(sub)
        for values in ({'concept_round_id': None}, {'selected_concept_key': 'c2'}):
            sub.files.filter(pk=first.pk).update(**values)
            self.assertFalse(final_paper_complete(self.team, self.stage))
            self.assertFalse(post_deliverables_complete(self.team, self.stage.label))
            sub.files.filter(pk=first.pk).update(concept_round=concepts.latest_round(self.team, self.stage),
                                               selected_concept_key='c1')

    def test_both_stage_settings_endpoints_save_multiple_attachment_configuration(self):
        policy = {'mode': 'multiple', 'min_files': 2, 'max_files': 3, 'purpose': 'approved_concept'}
        serializer = DefenseStageWriteSerializer(self.stage, data={
            'concept_config': {'enabled': True}, 'deliverables': [{
                'deliverable_id': 'FINAL', 'label': 'Approved Concept Paper', 'deliverable_type': 'post',
                'file_policy': policy}]}, partial=True)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        serializer.save()
        final = self.stage.deliverables.get(deliverable_id='FINAL')
        self.assertEqual(final.file_policy, policy)
        policy['max_files'] = 5
        serializer = StageDeliverableSerializer(final, data={'file_policy': policy}, partial=True)
        self.assertTrue(serializer.is_valid(), serializer.errors)
        serializer.save()
        final.refresh_from_db()
        self.assertEqual(final.file_policy, policy)

    def test_single_file_configuration_remains_compatible(self):
        self.prepare(mode='single')
        sub = self.upload_final()
        self.accept(sub)
        self.assertTrue(final_paper_complete(self.team, self.stage))

    def test_pit_setup_saves_and_roundtrips_multiple_attachment_policy(self):
        from defense.scheduler.pit_config import upsert_pit_event_config
        policy = {'mode': 'multiple', 'min_files': 2, 'max_files': 4, 'purpose': 'approved_concept'}
        items = [{'deliverable_id': 'FINAL', 'label': 'Approved Concept Paper',
                  'deliverable_type': 'post', 'file_policy': policy}]
        event = upsert_pit_event_config(semester=self.semester, year_level='1st Year',
            event_name='Attachment event', concept_config={'enabled': True}, deliverables=items)
        self.assertEqual(event.deliverables.get(deliverable_id='FINAL').file_policy, policy)
        upsert_pit_event_config(semester=self.semester, year_level=event.year_level,
            event_name=event.event_name, config_id=event.pk, concept_config=event.concept_config, deliverables=items)
        self.assertEqual(event.deliverables.get(deliverable_id='FINAL').file_policy, policy)

    def test_nonpassing_concept_outcomes_keep_post_uploads_locked(self):
        self.prepare('for_redefense')
        self.assertFalse(archive_unlocked(self.team, self.stage.label))
        with self.assertRaises(PermissionError):
            self.upload_final()

    def test_failed_concept_hearing_keeps_post_uploads_locked(self):
        self.prepare('failed')
        self.assertFalse(archive_unlocked(self.team, self.stage.label))
        with self.assertRaises(PermissionError):
            self.upload_final()

    def test_rejected_project_keeps_post_uploads_locked(self):
        self.prepare('project_rejected')
        self.assertFalse(archive_unlocked(self.team, self.stage.label))
        with self.assertRaises(PermissionError):
            self.upload_final()

    def test_attachment_limits_and_formats_remain_enforced(self):
        self.prepare()
        for number in range(3):
            self.upload_final(f'attachment{number}.pdf')
        with self.assertRaises(ValueError):
            self.upload_final('excess.pdf')
        with self.assertRaises(ValueError):
            self.upload_final('invalid.zip')
