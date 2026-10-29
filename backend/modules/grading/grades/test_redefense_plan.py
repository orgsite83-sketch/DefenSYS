from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.scheduler.panelist_evaluation import validate_evaluation_submissions
from defense.stages.models import StageDeliverable
from repository.deliverables import concepts
from repository.deliverables.documents import current_files
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from repository.deliverables.services import upsert_submission, review_submission, endorse_team, stage_payload
from . import test_outcome_rules as fixtures
from .defense_workflow import record_verdict
from .services import GradeContextService, submit_panelist_grade


class FocusedRepeatAssessmentTests(APITestCase):
    _rubric = fixtures.PerConceptOutcomeTests._rubric
    prepare = fixtures.PerConceptOutcomeTests.prepare
    scores = fixtures.PerConceptOutcomeTests.scores
    submit = fixtures.PerConceptOutcomeTests.submit
    setUp = fixtures.PerConceptOutcomeTests.setUp

    def test_next_hearing_assesses_only_requested_concept_and_keeps_prior_evidence(self):
        self.submit([5, 6, 7])
        grade = record_verdict(self.grade, actor=self.admin, verdict='for_redefense', remarks='Revise Concept 2.',
            concept_decisions=[{'key': f'c{i}', 'decision': 'rejected', 'remarks': 'Narrow the scope.',
                'next_action': 'revise' if i == 2 else 'omit'} for i in range(1, 4)])
        first = concepts.latest_round(self.capstone_team, self.stage)
        self.assertEqual([c['key'] for c in first.concepts], ['c2'])
        sub = upsert_submission(self.capstone_team, self.stage.label, 'CONCEPTS', 'revised2.pdf', '10 B', self.student,
            file=SimpleUploadedFile('revised2.pdf', b'revised concept'), slot_key='c2:paper')
        review_submission(self.capstone_team, self.stage.label, 'CONCEPTS', 'accepted', '', self.adviser,
                          file_id=current_files(sub)[0].pk)
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        next_schedule = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date='2026-05-16', start_time='11:00', room='Repeat')
        SchedulePanelist.objects.create(schedule=next_schedule, panelist=self.panelist, is_chair=True)
        next_grade, _, _ = GradeContextService.get_or_create_for_schedule(next_schedule)
        self.assertIsNone(next_grade.panel_score)
        rows = [{'concept_key': 'c2', 'student_id': None,
                 'criteria_scores': [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 8}]}]
        validate_evaluation_submissions(next_schedule, rows)
        submit_panelist_grade(next_schedule, next_grade, rows[0]['criteria_scores'], panelist=self.panelist, concept_key='c2')
        # The new hearing captures automatic outcomes while preserving the
        # earlier panel's narrower concept set and evidence.
        next_grade.refresh_from_db()
        approved = next_grade
        self.assertEqual(approved.verdict, 'approved')
        self.assertEqual(approved.panel_score, 80)
        self.assertEqual(approved.attempt_count, 2)
        self.assertEqual(approved.attempt_history.get().verdict, 'for_redefense')
        old = concepts.payload(self.capstone_team, self.stage)['history'][-1]
        self.assertEqual(len(old['concepts']), 3)
        self.assertEqual(len(old['documents'][0]['files']), 3)
        self.assertEqual(approved.panelist_submissions.filter(schedule=self.capstone_schedule).count(), 3)
        from reports.assessment_reports import _team_rows
        from reports.grade_summary import assessment_panel_submissions
        self.assertEqual(_team_rows(approved)[0]['panel_1'], '80.00%')
        self.assertEqual({row.schedule_id for row in assessment_panel_submissions(approved)}, {next_schedule.pk})

    def test_rejection_without_a_requested_next_set_is_an_atomic_error(self):
        self.submit([5, 6, 7])
        with self.assertRaisesMessage(ValidationError, 'at least one'):
            record_verdict(self.grade, actor=self.admin, verdict='for_redefense', remarks='Panel rejected the concepts.',
                concept_decisions=[{'key': f'c{i}', 'decision': 'rejected', 'remarks': 'Unsuitable scope.'} for i in range(1, 4)])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertEqual(concepts.latest_round(self.capstone_team, self.stage).number, 1)


class GeneralRepeatFilesTests(APITestCase):
    _rubric = fixtures.ConfiguredOutcomeTests._rubric
    new_hearing = fixtures.ConfiguredOutcomeTests.new_hearing
    submit = fixtures.ConfiguredOutcomeTests.submit

    def setUp(self):
        fixtures.ConfiguredOutcomeTests.setUp(self)
        self.media = TemporaryDirectory()
        self.addCleanup(self.media.cleanup)
        override = override_settings(MEDIA_ROOT=self.media.name)
        override.enable()
        self.addCleanup(override.disable)
        extraction = patch('repository.deliverables.pdf_processor.extract_pdf_from_file_object', return_value={'text': 'Test evidence'})
        extraction.start()
        self.addCleanup(extraction.stop)
        self.stage.deliverables.all().delete()
        self.material = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='MATERIAL',
            label='Panel attachments', required=True, is_defense_material=True,
            file_policy={'mode': 'multiple', 'min_files': 1, 'max_files': 3})
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='GENERAL', label='General form',
            required=True, file_policy={'mode': 'single'})
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        capture_participation(self.capstone_team, requirements=configured_requirements())
        for identifier in ('MATERIAL', 'GENERAL'):
            submission = DeliverableSubmission.objects.create(team=self.capstone_team, stage_label=self.stage.label,
                deliverable_id=identifier, label=identifier, required=True, deliverable_type='pre', status='accepted',
                file=SimpleUploadedFile(identifier+'.pdf', b'test file'), file_name=identifier+'.pdf', extracted_text='Fixture text')
            if identifier == 'GENERAL':
                DeliverableSubmissionFile.objects.create(submission=submission, file=submission.file.name,
                    file_name=submission.file_name, status='accepted')
        self.submit(5)
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='for_redefense', remarks='Revise the panel materials.')

    def test_reuses_general_file_and_refreshes_materials_without_concept_selection(self):
        general = self.capstone_team.deliverable_submissions.get(deliverable_id='GENERAL')
        material = self.capstone_team.deliverable_submissions.get(deliverable_id='MATERIAL')
        self.assertEqual(general.status, 'accepted')
        self.assertEqual(len(current_files(general)), 1)
        self.assertEqual(current_files(material), [])
        payload = stage_payload(self.capstone_team, self.stage.label)
        self.assertEqual(len(payload['hearing_history']), 1)
        old_material = next(d for d in payload['hearing_history'][0]['documents'] if d['deliverable_id'] == 'MATERIAL')
        self.assertEqual(old_material['files'][0]['file_name'], 'MATERIAL.pdf')
        self.assertEqual(old_material['files'][0]['status'], 'accepted')
        self.assertEqual(material.files.get(file_name='MATERIAL.pdf').uploaded_at.isoformat(), old_material['files'][0]['uploaded_at'])
        self.assertFalse(next(d for d in payload['pre'] if d['id'] == 'GENERAL')['can_upload'])
        self.assertFalse(payload['vault_unlocked'])
        self.assertTrue(payload['repeat_preparation'])
        self.assertEqual(payload['stage_status_detail'], 'awaiting_files')
        with self.assertRaises(ValidationError):
            record_verdict(self.grade, actor=self.admin, verdict='for_redefense', remarks='Record again.')

    def test_fresh_materials_are_reviewed_then_locked_by_new_endorsement(self):
        sub = upsert_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'new.pdf', '10 B', self.student,
            file=SimpleUploadedFile('new.pdf', b'new attachment'))
        with self.assertRaises(ValueError):
            endorse_team(self.capstone_team, self.stage.label, self.adviser)
        review_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'accepted', '', self.adviser)
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        with self.assertRaises(PermissionError):
            upsert_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'extra.pdf', '10 B', self.student,
                file=SimpleUploadedFile('extra.pdf', b'after endorsement'))
        self.assertTrue(Path(sub.files.get(file_name='MATERIAL.pdf').file.path).exists())
        payload = stage_payload(self.capstone_team, self.stage.label)
        self.assertTrue(payload['endorsed'])
        self.assertTrue(all(not d['can_faculty_review'] for d in payload['pre']))
        self.assertTrue(payload['repeat_preparation'])
        self.assertEqual(payload['stage_status_detail'], 'ready_to_schedule_redefense')
        from defense.scheduler.serializers import ScheduleTeamSerializer
        self.assertEqual(ScheduleTeamSerializer(self.capstone_team).data['stage_progress'][self.stage.label],
                         'ready_to_schedule_redefense')

    def test_unreviewed_extra_attachment_cannot_hide_behind_one_accepted_file(self):
        for name in ('one.pdf', 'two.pdf'):
            sub = upsert_submission(self.capstone_team, self.stage.label, 'MATERIAL', name, '10 B', self.student,
                file=SimpleUploadedFile(name, b'new panel evidence'))
        rows = current_files(sub)
        review_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'accepted', '', self.adviser, file_id=rows[0].pk)
        with self.assertRaises(ValueError):
            endorse_team(self.capstone_team, self.stage.label, self.adviser)
        review_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'accepted', '', self.adviser, file_id=rows[1].pk)
        endorse_team(self.capstone_team, self.stage.label, self.adviser)

    def test_new_endorsement_also_closes_an_earlier_optional_correction_request(self):
        self.material.required = False
        self.material.save(update_fields=['required'])
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        capture_participation(self.capstone_team, requirements=configured_requirements())
        upsert_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'optional.pdf', '10 B', self.student,
            file=SimpleUploadedFile('optional.pdf', b'optional evidence'))
        review_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'rejected', 'Clarify this optional attachment.', self.adviser)
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        with self.assertRaises(PermissionError):
            upsert_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'changed.pdf', '10 B', self.student,
                file=SimpleUploadedFile('changed.pdf', b'after endorsement'))
