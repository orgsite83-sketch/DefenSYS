"""Regressions found while auditing the five configured defense phases."""
from decimal import Decimal

from rest_framework.test import APITestCase
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from . import test_outcome_rules as fixtures
from .corrections import correction_details, request_correction, review_correction
from .defense_workflow import record_verdict
from .models import TeamGrade
from .views import counts_payload
from defense.scheduler.models import DefenseSchedule
from defense.scheduler.services import transition_schedule_status
from . import test_workflow_completion as completion_fixtures
from . import test_redefense_plan as repeat_fixtures


class ConfiguredOutcomeAuditTests(APITestCase):
    _rubric = fixtures.ConfiguredOutcomeTests._rubric
    new_hearing = fixtures.ConfiguredOutcomeTests.new_hearing
    submit = fixtures.ConfiguredOutcomeTests.submit
    setUp = fixtures.ConfiguredOutcomeTests.setUp

    def test_grade_center_counts_follow_recorded_outcomes_not_academic_75(self):
        self.submit(8)
        self.grade.refresh_from_db()
        self.grade.adviser_score = self.grade.peer_score = Decimal('0')
        self.grade.save()
        record_verdict(self.grade, actor=self.admin, verdict='approved')
        query = TeamGrade.objects.filter(pk=self.grade.pk)
        self.assertEqual(counts_payload(query)['passed'], 1)
        self.assertEqual(counts_payload(query)['failed'], 0)

    def test_unrecorded_configured_decision_is_not_counted_as_numeric_pass(self):
        self.submit(8)
        self.grade.refresh_from_db()
        self.grade.adviser_score = self.grade.peer_score = Decimal('100')
        self.grade.save()
        query = TeamGrade.objects.filter(pk=self.grade.pk)
        self.assertEqual(counts_payload(query)['passed'], 0)
        self.assertEqual(counts_payload(query)['failed'], 0)

    def test_counts_match_each_configured_outcome(self):
        query = TeamGrade.objects.filter(pk=self.grade.pk)
        for verdict, cleared, expected in [
            ('approved', None, (1, 0)),
            ('approved_with_revisions', None, (0, 0)),
            ('approved_with_revisions', timezone.now(), (1, 0)),
            ('for_redefense', None, (0, 0)),
            ('failed', None, (0, 1)),
            ('project_rejected', None, (0, 1)),
        ]:
            with self.subTest(verdict=verdict, cleared=cleared):
                query.update(verdict=verdict, revisions_cleared_at=cleared, final_grade=99)
                result = counts_payload(query)
                self.assertEqual((result['passed'], result['failed']), expected)

    def test_counts_preserve_pit_and_legacy_numeric_results(self):
        query = TeamGrade.objects.filter(pk=self.grade.pk)
        for policy, scope, verdict in [({}, 'capstone', ''), ({'version': 0}, 'capstone', ''),
                                        ({'version': 1}, 'pit', 'approved')]:
            DefenseSchedule.objects.filter(pk=self.capstone_schedule.pk).update(assessment_policy=policy)
            for score, expected in [(80, (1, 0)), (70, (0, 1)), (None, (0, 0))]:
                with self.subTest(policy=policy, scope=scope, score=score):
                    query.update(scope=scope, verdict=verdict, final_grade=score)
                    result = counts_payload(query)
                    self.assertEqual((result['passed'], result['failed']), expected)

    def test_academic_amendment_crossing_75_preserves_panel_approval(self):
        self.submit(8)
        self.grade.refresh_from_db()
        self.grade.adviser_score = self.grade.peer_score = Decimal('80')
        self.grade.save()
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.grade.publish(self.admin)
        data = {'reason': 'Correcting the recorded academic peer score.',
                'expected_updated_at': self.grade.updated_at.isoformat(),
                'changes': {'aggregate': {'peer_score': 0}}}
        preview = request_correction(self.grade.pk, self.admin, {**data, 'preview': True})
        self.assertTrue(preview['requires_approval'])
        self.assertLess(Decimal(preview['after']['final_grade']), 75)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.final_grade, 80)
        amendment = request_correction(self.grade.pk, self.admin, data)
        self.assertEqual(amendment['status'], 'pending')
        review_correction(self.grade.pk, amendment['id'], self.admin, {
            'action': 'approve', 'acknowledge_published_change': True,
            'reason': 'Verified the original peer score record.'})
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.result, 'passed')
        self.assertEqual(self.grade.attempt_count, 1)

    def test_panel_amendment_cannot_invalidate_recorded_approval(self):
        self.submit(8)
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='approved')
        score = self.grade.panelist_submissions.get().criterion_scores.get()
        with self.assertRaises(ValidationError):
            request_correction(self.grade.pk, self.admin, {
                'preview': True, 'reason': 'Correcting the panel source score.',
                'expected_updated_at': self.grade.updated_at.isoformat(),
                'changes': {'criterion': {'id': score.pk, 'score': 6}}})
        score.refresh_from_db()
        self.assertEqual(score.score, 8)

    def test_new_configured_outcome_cannot_restore_optional_adviser_clearance(self):
        self.submit(5)
        grade = record_verdict(self.grade, actor=self.admin, verdict='for_redefense',
            remarks='Revise the materials and defend again.', verification_required=True)
        self.assertFalse(grade.redefense_verification_required)

    def test_scheduler_readiness_projection_does_not_rewrite_schedule_status(self):
        from defense.scheduler.serializers import ScheduleTeamSerializer
        self.submit(5)
        record_verdict(self.grade, actor=self.admin, verdict='for_redefense',
                       remarks='Revise the materials and defend again.')
        # Historical inconsistent status must not be repaired by a GET projection.
        DefenseSchedule.objects.filter(pk=self.capstone_schedule.pk).update(status='scheduled')
        ScheduleTeamSerializer(self.capstone_team).data
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.capstone_schedule.status, 'scheduled')


class ConceptCorrectionAuditTests(APITestCase):
    _rubric = fixtures.PerConceptOutcomeTests._rubric
    prepare = fixtures.PerConceptOutcomeTests.prepare
    scores = fixtures.PerConceptOutcomeTests.scores
    submit = fixtures.PerConceptOutcomeTests.submit
    setUp = fixtures.PerConceptOutcomeTests.setUp

    def test_correction_options_and_history_identify_each_concept(self):
        self.submit([8, 9, 10])
        details = correction_details(self.grade)
        self.assertEqual({row['concept_key'] for row in details['scores']}, {'c1', 'c2', 'c3'})
        self.assertEqual({row['concept_key'] for row in details['grade']['criteria']}, {'c1', 'c2', 'c3'})
        self.assertEqual(details['grade']['assessment_policy']['version'], 1)


class ConfiguredArchiveAuditTests(APITestCase):
    _rubric = completion_fixtures.WorkflowCompletionTests._rubric
    new_hearing = completion_fixtures.WorkflowCompletionTests.new_hearing
    submit = completion_fixtures.WorkflowCompletionTests.submit
    approve = completion_fixtures.WorkflowCompletionTests.approve
    accepted_files = completion_fixtures.WorkflowCompletionTests.accepted_files
    setUp = completion_fixtures.WorkflowCompletionTests.setUp

    def archive(self):
        self.capstone_schedule.refresh_from_db()
        return transition_schedule_status(self.capstone_schedule, 'archived', actor=self.admin)

    def test_approved_hearing_cannot_be_archived_with_pending_files(self):
        self.approve()
        self.grade.publish(self.admin)
        with self.assertRaises(ValidationError):
            self.archive()
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.capstone_schedule.status, 'done')

    def test_approved_hearing_cannot_be_archived_with_pending_academic_grades(self):
        self.submit(8)
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.accepted_files()
        with self.assertRaises(ValidationError):
            self.archive()

    def test_revision_clearance_is_required_before_archiving(self):
        self.approve('approved_with_revisions')
        self.accepted_files()
        self.grade.publish(self.admin)
        with self.assertRaises(ValidationError):
            self.archive()

    def test_fully_completed_hearing_can_be_archived(self):
        self.approve()
        self.accepted_files()
        self.grade.publish(self.admin)
        self.assertEqual(self.archive().status, 'archived')

    def test_redefense_attempt_can_be_archived_without_final_files(self):
        self.submit(4)
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='for_redefense',
                                    remarks='Revise the implementation and defend again.')
        self.assertEqual(self.archive().status, 'archived')


class RepeatEndorsementAuditTests(APITestCase):
    _rubric = repeat_fixtures.GeneralRepeatFilesTests._rubric
    new_hearing = repeat_fixtures.GeneralRepeatFilesTests.new_hearing
    submit = repeat_fixtures.GeneralRepeatFilesTests.submit
    setUp = repeat_fixtures.GeneralRepeatFilesTests.setUp

    def test_fresh_endorsement_does_not_require_a_second_clearance_flag(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from repository.deliverables.services import upsert_submission, review_submission, endorse_team
        from student_teams.services import is_stage_ready
        from .defense_workflow import workflow_payload
        TeamGrade.objects.filter(pk=self.grade.pk).update(redefense_verification_required=True)
        upsert_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'revised.pdf', '10 B', self.student,
            file=SimpleUploadedFile('revised.pdf', b'Revised panel material'))
        review_submission(self.capstone_team, self.stage.label, 'MATERIAL', 'accepted', '', self.adviser)
        endorse_team(self.capstone_team, self.stage.label, self.adviser)
        self.capstone_team.refresh_from_db()
        self.grade.refresh_from_db()
        self.assertTrue(is_stage_ready(self.capstone_team, self.stage))
        self.assertTrue(workflow_payload(self.grade)['redefense_ready'])


