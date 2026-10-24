"""Exercise configured outcomes, real file clearance and progression together."""
from decimal import Decimal

from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule
from defense.scheduler.progress import schedule_progress
from defense.scheduler.serializers import ScheduleTeamSerializer
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from repository.deliverables.services import stage_payload, post_deliverables_complete, review_submission
from reports.assessment_reports import _team_rows
from reports.assessment_workbooks import assessment_document_sheets
from reports.grade_summary import grade_outcome_label
from student_teams.models import TeamStageProgress
from student_teams.services import stage_progression_blocker
from . import test_outcome_rules as fixtures
from .defense_workflow import record_verdict
from .models import TeamGrade
from .services import GradeContextService, cohort_grading_teams_for_group


class WorkflowCompletionTests(APITestCase):
    _rubric = fixtures.ConfiguredOutcomeTests._rubric
    new_hearing = fixtures.ConfiguredOutcomeTests.new_hearing
    submit = fixtures.ConfiguredOutcomeTests.submit

    def setUp(self):
        fixtures.ConfiguredOutcomeTests.setUp(self)
        self.post = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='P5FILES',
            label='Configured final attachments', deliverable_type='post', required=True,
            file_policy={'mode': 'multiple', 'min_files': 1, 'max_files': 3})
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        capture_participation(self.capstone_team, requirements=configured_requirements())

    def approve(self, verdict='approved'):
        self.submit(8)
        self.grade.refresh_from_db()
        self.grade.adviser_score = self.grade.peer_score = Decimal('80')
        self.grade.save()
        self.grade = record_verdict(self.grade, actor=self.admin, verdict=verdict, remarks='Review final files.')

    def accepted_files(self):
        sub = DeliverableSubmission.objects.create(team=self.capstone_team, stage_label=self.stage.label,
            deliverable_id=self.post.deliverable_id, label=self.post.label, deliverable_type='post',
            status='accepted', file_name='final.pdf', file='test-evidence/final.pdf', extracted_text='Final evidence')
        DeliverableSubmissionFile.objects.create(submission=sub, file='test-evidence/final.pdf',
            file_name='final.pdf', slot_key='attachment-1', status='accepted', extracted_text='Final evidence')
        return sub

    def progress(self):
        return schedule_progress(DefenseSchedule.objects.get(pk=self.capstone_schedule.pk), reconcile_status=False)

    def test_panel_qualification_and_academic_total_do_not_record_a_verdict(self):
        self.submit(8)
        self.grade.refresh_from_db()
        self.grade.adviser_score = self.grade.peer_score = Decimal('100')
        self.grade.save()
        self.assertEqual(self.grade.result, 'pending')
        self.assertEqual(grade_outcome_label(self.grade), 'Awaiting defense decision')
        self.assertEqual(self.progress()['display_status'], 'awaiting_verdict')

    def test_already_published_legacy_numeric_result_keeps_its_recorded_basis(self):
        DefenseSchedule.objects.filter(pk=self.capstone_schedule.pk).update(assessment_policy={'version': 0})
        self.grade.refresh_from_db()
        self.grade.panel_score = self.grade.adviser_score = self.grade.peer_score = Decimal('80')
        self.grade.status = TeamGrade.STATUS_PUBLISHED
        self.grade.save()
        self.assertFalse(self.progress()['is_completed'])
        self.accepted_files()
        self.assertTrue(self.progress()['is_completed'])
        self.assertIn(self.stage.label, ScheduleTeamSerializer(self.capstone_team).data['completed_stages'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertEqual(grade_outcome_label(self.grade), 'Grade passed')

    def test_finalized_legacy_approval_does_not_require_a_new_evaluator_ledger(self):
        DefenseSchedule.objects.filter(pk=self.capstone_schedule.pk).update(assessment_policy={'version': 0})
        self.grade.refresh_from_db()
        self.grade.panel_score = self.grade.adviser_score = self.grade.peer_score = Decimal('80')
        self.grade.verdict = 'approved'
        self.grade.status = TeamGrade.STATUS_PUBLISHED
        self.grade.save()
        self.accepted_files()
        self.assertTrue(self.progress()['is_completed'])

    def test_approved_outcome_remains_visible_while_files_are_pending(self):
        self.approve()
        result = self.progress()
        self.assertEqual(result['display_status'], 'pending_post_defense')
        self.assertEqual(result['verdict'], 'approved')
        self.assertTrue(result['defense_approved'])
        self.assertFalse(result['post_defense_complete'])
        self.assertFalse(result['is_completed'])
        payload = stage_payload(self.capstone_team, self.stage.label)
        self.assertEqual(payload['stage_status_detail'], result['display_status'])

    def test_qualifying_panel_scores_alone_do_not_unlock_post_files_or_review(self):
        self.submit(8)
        payload = stage_payload(self.capstone_team, self.stage.label)
        self.assertFalse(payload['post_unlocked'])
        self.assertFalse(payload['can_faculty_review_post'])
        self.assertFalse(payload['post_defense_ready'])

    def test_published_assessment_with_missing_files_is_not_a_completed_stage(self):
        self.approve()
        GradeContextService.publish(self.grade, user=self.admin)
        self.assertTrue(self.progress()['assessment_finalized'])
        self.assertFalse(self.progress()['is_completed'])
        self.assertNotIn(self.stage.label, ScheduleTeamSerializer(self.capstone_team).data['completed_stages'])
        self.assertIsNone(GradeContextService.grade_ready_for_archive(self.capstone_team,
            scope='capstone', defense_stage_id=self.stage.pk))

    def test_pending_extra_attachment_blocks_a_published_approved_stage(self):
        self.approve()
        sub = self.accepted_files()
        GradeContextService.publish(self.grade, user=self.admin)
        DeliverableSubmissionFile.objects.create(submission=sub, file='test-evidence/extra.pdf',
            file_name='extra.pdf', slot_key='attachment-2', status='pending', extracted_text='Extra evidence')
        self.assertFalse(post_deliverables_complete(self.capstone_team, self.stage.label))
        self.assertFalse(self.progress()['is_completed'])

    def test_post_files_never_complete_missing_academic_components(self):
        self.submit(8)
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.accepted_files()
        result = self.progress()
        self.assertTrue(result['post_defense_complete'])
        self.assertFalse(result['grading_complete'])
        self.assertEqual(result['display_status'], 'grading_incomplete')
        self.assertFalse(result['is_completed'])

    def test_last_file_review_updates_an_already_published_stage(self):
        self.approve()
        sub = self.accepted_files()
        sub.status = 'pending'
        sub.save(update_fields=['status'])
        sub.files.update(status='pending')
        GradeContextService.publish(self.grade, user=self.admin)
        self.assertEqual(TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage).status, 'grading')
        review_submission(self.capstone_team, self.stage.label, self.post.deliverable_id,
            'accepted', '', self.adviser, file_id=sub.files.get().pk)
        self.assertEqual(TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage).status, 'passed')
        self.assertTrue(self.progress()['is_completed'])
        from repository.project_archive.services import _complete_passing_grades
        self.assertIn(self.grade, _complete_passing_grades('capstone'))

    def test_revision_clearance_and_files_are_both_reported_as_outstanding(self):
        self.approve('approved_with_revisions')
        row = next(row for row in cohort_grading_teams_for_group(self.semester, 'capstone', self.stage.label)
                   if row['grade_id'] == self.grade.pk)
        self.assertIn('clearance', row['missing_components'])
        self.assertIn('post_defense', row['missing_components'])
        self.assertFalse(row['post_defense_complete'])
        self.assertEqual(self.progress()['display_status'], 'revisions_pending')

    def test_schedule_report_uses_assessment_evidence_and_does_not_reconcile_records(self):
        self.approve()
        GradeContextService.publish(self.grade, user=self.admin)
        DefenseSchedule.objects.filter(pk=self.capstone_schedule.pk).update(status='scheduled')
        response = self.client.get('/api/reports/defense-schedules/', {
            'semester_id': self.semester.pk, 'scope': 'capstone', 'export_format': 'json'})
        self.assertEqual(response.status_code, 200)
        row = next(row for row in response.data['rows'] if row['team_name'] == self.capstone_team.name)
        self.assertEqual(row['status'], 'Pending Post Defense')
        summary = {item['label']: item['value'] for item in response.data['summary_kpis']}
        self.assertEqual(summary['Completed stages / events'], '0')
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.capstone_schedule.status, 'scheduled')

    def test_approved_below_75_academic_grade_can_archive_at_configured_cutoff(self):
        self.stage.qualifying_score = 50
        self.stage.save()
        self.new_hearing()
        self.submit(5)
        self.grade.refresh_from_db()
        self.grade.adviser_score = self.grade.peer_score = Decimal('0')
        self.grade.save()
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.accepted_files()
        GradeContextService.finalize_for_archive(self.grade, user=self.admin)
        self.assertLess(self.grade.final_grade, 75)
        from repository.project_archive.services import _complete_passing_grades
        self.assertIn(self.grade, _complete_passing_grades('capstone'))
        self.assertEqual(GradeContextService.grade_ready_for_archive(self.capstone_team,
            scope='capstone', defense_stage_id=self.stage.pk), self.grade)
        self.assertTrue(self.progress()['is_completed'])

    def test_configured_stage_order_checks_current_outcome_and_post_files(self):
        self.approve()
        next_stage = DefenseStage.objects.create(label='Custom follow-up', display_order=self.stage.display_order + 10)
        # Keep this scenario independent of seeded stage labels/order.
        DefenseStage.objects.exclude(pk__in=[self.stage.pk, next_stage.pk]).update(is_active=False)
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        capture_participation(self.capstone_team, requirements=configured_requirements())
        progress = TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage)
        progress.status = TeamStageProgress.STATUS_PASSED
        progress.save()
        self.assertTrue(stage_progression_blocker(self.capstone_team, next_stage))
        self.accepted_files()
        GradeContextService.finalize_for_archive(self.grade, user=self.admin)
        self.assertEqual(stage_progression_blocker(self.capstone_team, next_stage), '')


class SelectedConceptReportTests(APITestCase):
    _rubric = fixtures.PerConceptOutcomeTests._rubric
    prepare = fixtures.PerConceptOutcomeTests.prepare
    scores = fixtures.PerConceptOutcomeTests.scores
    submit = fixtures.PerConceptOutcomeTests.submit
    setUp = fixtures.PerConceptOutcomeTests.setUp

    def test_reports_keep_alternatives_separate_from_the_official_panel_score(self):
        self.submit([8, 9, 10])
        self.grade = record_verdict(self.grade, actor=self.admin, verdict='approved',
            concept_decisions=[{'key': f'c{i}', 'decision': 'approved' if i == 2 else 'rejected',
                               'remarks': '' if i == 2 else 'Alternative concept.'} for i in range(1, 4)])
        rows = _team_rows(self.grade)
        self.assertEqual(rows[0]['panel_1'], '90.00%')
        sheets = assessment_document_sheets([self.grade], student=None, team_rows=_team_rows, coverage='Current')
        criteria = next(sheet for sheet in sheets if sheet['name'].endswith('Criteria'))
        self.assertEqual({r['candidate'].split(' | ')[0] for r in criteria['rows']}, {'C1', 'C2', 'C3'})

    def test_qualifying_concepts_wait_for_selection_without_an_official_grade(self):
        self.submit([8, 9, 10])
        result = schedule_progress(self.capstone_schedule, reconcile_status=False)
        self.assertEqual(result['display_status'], 'awaiting_concept_selection')
        self.grade.refresh_from_db()
        self.assertIsNone(self.grade.panel_score)
        self.assertNotIn('panel_1', _team_rows(self.grade)[0])
