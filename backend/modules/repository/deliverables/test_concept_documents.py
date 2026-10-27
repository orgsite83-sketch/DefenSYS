from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.exceptions import ValidationError
from rest_framework.test import APITestCase
from defense.document_policy import validate_file_policy
from defense.scheduler.models import DefenseSchedule
from student_teams.services import is_stage_ready, was_stage_endorsed
from . import test_submission_timing as fixtures
from .models import ConceptRound
from .services import upsert_submission, review_submission, required_complete, endorse_team, stage_payload
from .documents import current_files, file_payload
from . import concepts


class ConceptDocumentTests(APITestCase):
    setUp = fixtures.faculty_review_setup

    def configure(self, mode='concepts', **extra):
        self.stage.concept_config = {'enabled': True, 'required_count': 3} if mode == 'concepts' else {}
        self.stage.save()
        self.paper.file_policy = {'mode': mode, **extra}
        self.paper.save()
        if mode == 'concepts':
            concepts.get_round(self.team, self.stage).__class__.objects.filter(team=self.team).update(title_workflow_version=1)
            concepts.save_titles(self.team, self.stage, [
                {'key': f'c{i}', 'title': f'Candidate project {i}'} for i in range(1, 4)])

    def upload(self, slot, filename='concept.pdf'):
        return upsert_submission(self.team, self.stage.label, 'PAPER', filename, '10 B', self.student,
            file=SimpleUploadedFile(filename, b'concept test content'), slot_key=slot)

    def accept(self, submission, slot):
        row = next(f for f in current_files(submission) if f.slot_key == slot)
        review_submission(self.team, self.stage.label, 'PAPER', 'accepted', '', self.adviser, file_id=row.pk)
        submission.refresh_from_db()

    def complete_set(self):
        for i in range(1, 4):
            submission = self.upload(f'c{i}:paper')
            self.accept(submission, f'c{i}:paper')
        return submission

    def test_three_concepts_require_three_distinct_reviewed_documents(self):
        self.configure()
        one = self.upload('c1:paper')
        self.accept(one, 'c1:paper')
        self.assertFalse(required_complete(self.team, self.stage.label))
        with self.assertRaises(ValueError):
            endorse_team(self.team, self.stage.label, self.adviser)
        self.complete_set_except_first()
        self.assertTrue(required_complete(self.team, self.stage.label))
        endorse_team(self.team, self.stage.label, self.adviser)
        self.assertTrue(is_stage_ready(self.team, self.stage))
        self.assertTrue(was_stage_endorsed(self.team, self.stage))
        data = stage_payload(self.team, self.stage.label)
        self.assertEqual(data['concept_workflow']['status'], 'ready_to_schedule')
        self.assertEqual(len(next(d for d in data['pre'] if d['id'] == 'PAPER')['submission']['files']), 3)

    def complete_set_except_first(self):
        for i in (2, 3):
            submission = self.upload(f'c{i}:paper')
            self.accept(submission, f'c{i}:paper')

    def test_revision_keeps_old_bytes_and_only_reopens_affected_document(self):
        self.configure()
        submission = self.complete_set()
        second = next(f for f in current_files(submission) if f.slot_key == 'c2:paper')
        old_path = second.file.path
        review_submission(self.team, self.stage.label, 'PAPER', 'rejected', 'Clarify the problem statement.', self.adviser, file_id=second.pk)
        self.upload('c2:paper', 'revised.pdf')
        submission.refresh_from_db()
        self.assertEqual(len(current_files(submission)), 3)
        self.assertEqual(submission.files.count(), 4)
        second.refresh_from_db()
        self.assertFalse(second.is_current)
        from pathlib import Path
        self.assertTrue(Path(old_path).exists())
        self.assertEqual(sum(f.status == 'accepted' for f in current_files(submission)), 2)
        self.assertFalse(required_complete(self.team, self.stage.label))
        self.accept(submission, 'c2:paper')
        self.assertTrue(required_complete(self.team, self.stage.label))

    def test_extra_uploads_cannot_replace_missing_slots_and_format_is_enforced(self):
        self.configure()
        with self.assertRaises(ValueError):
            self.upload('c4:paper')
        with self.assertRaises(ValueError):
            self.upload('c1:paper', 'concept.zip')

    def test_title_changes_invalidate_endorsement(self):
        self.configure()
        self.complete_set()
        endorse_team(self.team, self.stage.label, self.adviser)
        concepts.save_titles(self.team, self.stage, [
            {'key': f'c{i}', 'title': f'Revised title {i}'} for i in range(1, 4)])
        self.assertFalse(is_stage_ready(self.team, self.stage))

    def test_all_rejected_creates_replacement_round_and_preserves_evidence(self):
        self.configure()
        submission = self.complete_set()
        endorse_team(self.team, self.stage.label, self.adviser)
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, scheduled_date=self.date, start_time='09:00', room='Concept room')
        concepts.bind_schedule(schedule)
        from grading.grades.models import TeamGrade
        grade = TeamGrade(team=self.team, semester=self.semester, defense_stage=self.stage,
            scope='capstone', schedule=schedule, verdict='for_redefense', verdict_remarks='Prepare three new concepts.', verdict_by=self.admin)
        concepts.record_outcome(grade, [
            {'key': f'c{i}', 'decision': 'rejected', 'remarks': 'Problem scope is not suitable.', 'next_action': 'replace'} for i in range(1, 4)])
        rounds = list(ConceptRound.objects.filter(team=self.team))
        self.assertEqual(len(rounds), 2)
        self.assertTrue(rounds[0].replacement_required)
        self.assertEqual(len(rounds[0].documents_snapshot[0]['files']), 3)
        self.assertEqual(len(current_files(submission)), 0)
        self.assertFalse(is_stage_ready(self.team, self.stage))
        self.team.refresh_from_db()
        self.assertNotEqual(self.team.status, 'Failed')
        self.assertEqual(concepts.payload(self.team, self.stage)['status'], 'replacement_concepts_needed')
        # Resolving the old schedule must never bind it to the new round.
        concepts.bind_schedule(schedule)
        self.assertIsNone(concepts.latest_round(self.team, self.stage).schedule_id)

    def test_named_documents_and_multiple_attachment_limits(self):
        self.configure('named', slots=[{'key': 'paper', 'label': 'Paper', 'file_format': 'pdf'},
                                      {'key': 'deck', 'label': 'Deck', 'file_format': 'presentation'}])
        submission = self.upload('paper')
        self.accept(submission, 'paper')
        self.assertFalse(required_complete(self.team, self.stage.label))
        submission = self.upload('deck', 'deck.pptx')
        self.accept(submission, 'deck')
        self.assertTrue(required_complete(self.team, self.stage.label))
        with self.assertRaises(ValidationError):
            validate_file_policy({'mode': 'multiple', 'min_files': 3, 'max_files': 2})

    def test_other_students_cannot_edit_and_non_admin_cannot_override(self):
        self.configure()
        from django.contrib.auth import get_user_model
        other = get_user_model().objects.create_user(username='outside-concept-team', role='student')
        self.client.force_authenticate(other)
        response = self.client.post('/api/repository/deliverables/concepts/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'action': 'save_titles', 'concepts': []}, format='json')
        self.assertIn(response.status_code, (403, 404))
        with self.assertRaises(PermissionError):
            concepts.override_clearance(self.team, self.stage, self.adviser, 'Exception')

    def test_multiple_attachments_enforce_limits_and_removal_preserves_history(self):
        self.configure('multiple', min_files=2, max_files=2)
        first = self.upload('a')
        self.accept(first, 'a')
        self.assertFalse(required_complete(self.team, self.stage.label))
        second = self.upload('b', 'second.pdf')
        self.accept(second, 'b')
        self.assertTrue(required_complete(self.team, self.stage.label))
        with self.assertRaises(ValueError):
            self.upload('c', 'third.pdf')
        row = second.files.get(slot_key='b', is_current=True)
        review_submission(self.team, self.stage.label, 'PAPER', 'rejected', 'Remove unrelated evidence.', self.adviser, file_id=row.pk)
        from .services import remove_submission
        remove_submission(self.team, self.stage.label, 'PAPER', file_id=row.pk)
        row.refresh_from_db()
        self.assertFalse(row.is_current)
        self.assertFalse(required_complete(self.team, self.stage.label))

    def test_pre_defense_file_cannot_bypass_endorsement_lock(self):
        self.configure()
        self.complete_set()
        endorse_team(self.team, self.stage.label, self.adviser)
        with self.assertRaises(PermissionError):
            upsert_submission(self.team, self.stage.label, 'DECK', 'pitch.pptx', '10 B', self.student,
                file=SimpleUploadedFile('pitch.pptx', b'deck test content'))
        self.assertTrue(concepts.clearance_valid(self.team, self.stage))
        self.assertTrue(is_stage_ready(self.team, self.stage))

    def test_optional_post_documents_do_not_block_completion_or_publish_without_review(self):
        from unittest.mock import patch
        from defense.stages.models import StageDeliverable
        from repository.archive.services import capstone_entry_payload
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='POST',
            label='Approved project documents', deliverable_type='post', required=True,
            file_policy={'mode': 'named', 'slots': [
                {'key': 'paper', 'label': 'Approved paper', 'file_format': 'pdf'},
                {'key': 'notes', 'label': 'Supporting notes', 'required': False, 'file_format': 'pdf'}]})
        with patch('repository.deliverables.services.archive_unlocked', return_value=True), \
             patch('repository.deliverables.services.is_stage_defense_done', return_value=True):
            for key in ('paper', 'notes'):
                sub = upsert_submission(self.team, self.stage.label, 'POST', f'{key}.pdf', '10 B', self.student,
                    file=SimpleUploadedFile(f'{key}.pdf', b'post document fixture'), slot_key=key)
            paper = sub.files.get(slot_key='paper', is_current=True)
            review_submission(self.team, self.stage.label, 'POST', 'accepted', '', self.adviser, file_id=paper.pk)
            sub.refresh_from_db()
            self.assertEqual(sub.status, 'accepted')
            self.assertEqual([f['file_name'] for f in capstone_entry_payload(sub)], ['paper.pdf'])
            notes = sub.files.get(slot_key='notes', is_current=True)
            review_submission(self.team, self.stage.label, 'POST', 'accepted', '', self.adviser, file_id=notes.pk)
            sub.refresh_from_db()
            self.assertEqual(len(capstone_entry_payload(sub)), 2)
