from decimal import Decimal
from django.core.exceptions import ValidationError
from django.utils import timezone
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.scheduler.progress import schedule_progress
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import TeamStageProgress
from student_teams.services import is_stage_ready, mark_stage_ready
from .models import TeamGrade
from . import tests as grade_fixtures
from .services import GradeContextService, submit_panelist_grade, finalize_passed_grade_for_archive
from .defense_workflow import record_verdict, apply_workflow_action


class DefenseWorkflowTests(APITestCase):
    _rubric = grade_fixtures.GradeCenterApiTests._rubric

    def setUp(self):
        grade_fixtures.GradeCenterApiTests.setUp(self)
        for previous in DefenseStage.objects.filter(is_active=True, display_order__lt=self.stage.display_order):
            TeamStageProgress.objects.update_or_create(team=self.capstone_team, semester=self.semester,
                defense_stage=previous, defaults={'status': TeamStageProgress.STATUS_PASSED})
        self.grade, _, _ = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)
        self.grade.adviser_score = Decimal('84')
        self.grade.peer_score = Decimal('88')
        self.grade.peer_score_is_override = True
        self.grade.save()

    def submit_panel(self, panelist=None, score=8):
        submit_panelist_grade(self.capstone_schedule, self.grade,
            [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': score}],
            panelist=panelist or self.panelist)
        self.grade.refresh_from_db()

    def verdict(self, value, **kwargs):
        self.submit_panel()
        self.grade = record_verdict(self.grade, actor=self.admin, verdict=value,
            remarks='Documented panel decision and required action.', **kwargs)

    def test_backdated_slot_does_not_claim_evaluation_started(self):
        self.assertEqual(schedule_progress(self.capstone_schedule)['display_status'], 'awaiting_evaluation')

    def test_all_assigned_panels_are_required_before_verdict(self):
        second_panelist = self.panelist.__class__.objects.create_user(
            username='second-workflow-panel', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=second_panelist)
        self.submit_panel()
        with self.assertRaises(ValidationError):
            record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.submit_panel(second_panelist)
        result = record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.assertEqual(result.verdict, 'approved')

    def test_redefense_retains_adviser_peer_and_releases_assessed_slot(self):
        self.verdict('for_redefense')
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.capstone_schedule.status, 'done')
        self.assertTrue(is_stage_ready(self.capstone_team, self.stage))
        next_slot = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date=timezone.localdate(),
            start_time='10:00', room='Room 302')
        grade, _, _ = GradeContextService.get_or_create_for_schedule(next_slot)
        self.assertEqual(grade.attempt_count, 2)
        self.assertEqual(grade.adviser_score, Decimal('84'))
        self.assertEqual(grade.peer_score, Decimal('88'))
        self.assertIsNone(grade.panel_score)
        self.assertEqual(grade.verdict, '')
        self.assertEqual(grade.attempt_history.get().verdict, 'for_redefense')
        self.assertEqual(grade.attempt_history.get().project_title, self.capstone_team.project_title)
        self.assertEqual(self.capstone_team.adviser_id, self.adviser.pk)
        self.assertTrue(all(s.panel_score is None for s in grade.student_grades.all()))
        old_grade, _, changed = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)
        self.assertFalse(changed)
        self.assertEqual(old_grade.schedule_id, next_slot.pk)

    def test_readiness_verification_is_only_required_when_requested(self):
        self.verdict('for_redefense', verification_required=True)
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        apply_workflow_action(self.grade, actor=self.adviser, action='verify_redefense', reason='Verified the required prototype corrections.')
        self.assertTrue(is_stage_ready(self.capstone_team, self.stage))

    def test_revision_clearance_preserves_scores_and_blocks_archive(self):
        self.verdict('approved_with_revisions')
        self.assertEqual(self.grade.result, 'revisions_pending')
        with self.assertRaises(ValidationError):
            finalize_passed_grade_for_archive(self.grade, user=self.admin)
        with self.assertRaises(PermissionError):
            apply_workflow_action(self.grade, actor=self.student, action='clear_revisions', reason='Student self-clearance.')
        apply_workflow_action(self.grade, actor=self.adviser, action='schedule_compliance_review', review_date=timezone.localdate())
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.attempt_count, 1)
        self.assertEqual(self.grade.panel_score, Decimal('80'))
        apply_workflow_action(self.grade, actor=self.adviser, action='clear_revisions', reason='All panel-required corrections verified by adviser.')
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved_with_revisions')
        self.assertEqual(self.grade.result, 'passed')
        finalize_passed_grade_for_archive(self.grade, user=self.admin)
        self.assertEqual(TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage).status, 'passed')



    def test_failed_or_uncleared_previous_stage_blocks_next_stage(self):
        self.verdict('approved_with_revisions')
        following = DefenseStage.objects.filter(is_active=True, display_order__gt=self.stage.display_order).first()
        self.assertIsNotNone(following)
        with self.assertRaises(ValidationError):
            mark_stage_ready(self.capstone_team, following)


    def test_unfinalized_approval_does_not_complete_stage(self):
        self.verdict('approved')
        self.assertEqual(TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage).status, 'grading')
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(schedule_progress(self.capstone_schedule)['display_status'], 'awaiting_completion')

    def test_external_evaluator_is_required_even_after_faculty_finish(self):
        from user_management.models import GuestPanelistCode
        invitation = GuestPanelistCode.objects.create(guest_name='External evaluator', created_by=self.admin)
        invitation.schedules.add(self.capstone_schedule)
        self.submit_panel()
        with self.assertRaises(ValidationError):
            record_verdict(self.grade, actor=self.admin, verdict='approved')
        submit_panelist_grade(self.capstone_schedule, self.grade,
            [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 9}],
            guest=__import__('types').SimpleNamespace(guest_name=invitation.guest_name,
                guest_code=invitation.code, guest_code_id=invitation.pk, token={'access_version': 1}))
        result = record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.assertEqual(result.verdict, 'approved')


    def test_revision_and_redefense_cannot_be_published_early(self):
        from .services import publish_grade_record
        self.submit_panel()
        for verdict in ['approved_with_revisions', 'for_redefense']:
            self.grade = record_verdict(self.grade, actor=self.admin, verdict=verdict,
                remarks='Recorded required corrections and further action.')
            with self.assertRaises(ValidationError):
                publish_grade_record(self.grade, user=self.admin)
            self.grade.refresh_from_db()
            self.assertEqual(self.grade.status, 'pending')


    def test_completed_nonfinal_stage_is_eligible_for_its_own_archive(self):
        from defense.stages.models import StageGradingConfig
        from repository.project_archive.services import capstone_archive_upload_queue
        self.verdict('approved')
        finalize_passed_grade_for_archive(self.grade, user=self.admin)
        StageGradingConfig.objects.filter(defense_stage=self.stage, semester=self.semester).update(is_officially_complete=True)
        queue = capstone_archive_upload_queue(self.semester)
        self.assertTrue(any(row['team_id'] == self.capstone_team.pk for row in queue))

    def test_retained_individual_adviser_grades_survive_the_new_panel_submission(self):
        self.verdict('for_redefense')
        self.grade.student_grades.filter(student=self.student).update(adviser_score=Decimal('91'))
        slot = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date=timezone.localdate(),
            start_time='10:00', room='Room 302')
        grade, _, _ = GradeContextService.get_or_create_for_schedule(slot)
        SchedulePanelist.objects.create(schedule=slot, panelist=self.panelist, is_chair=True)
        submit_panelist_grade(slot, grade,
            [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 9}], panelist=self.panelist)
        self.assertEqual(grade.student_grades.get(student=self.student).adviser_score, Decimal('91'))


    def test_stage_completion_blocked_until_post_defense_deliverables_approved(self):
        from defense.stages.models import StageDeliverable, StageGradingConfig
        from repository.deliverables.models import DeliverableSubmission
        from repository.deliverables.services import review_submission
        from grading.grades.services import StageCompletionService, IncompleteGradingTeamsError, incomplete_grading_teams_for_group

        post_del = StageDeliverable.objects.create(
            defense_stage=self.stage,
            deliverable_id='post_concept',
            label='Approved Concept Paper',
            deliverable_type='post',
            required=True,
            verdict_condition='all_pass',
        )
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        capture_participation(self.capstone_team, requirements=configured_requirements())
        self.verdict('approved')
        config, _ = StageGradingConfig.objects.get_or_create(defense_stage=self.stage, semester=self.semester)

        incomplete = incomplete_grading_teams_for_group(self.semester, 'capstone', self.stage.label, config=config)
        self.assertTrue(any('post_defense' in row['missing_components'] for row in incomplete))

        with self.assertRaises(IncompleteGradingTeamsError):
            StageCompletionService.complete_group(
                semester=self.semester, scope='capstone', stage_label=self.stage.label, config=config, user=self.admin
            )

        DeliverableSubmission.objects.create(
            team=self.capstone_team,
            stage_label=self.stage.label,
            deliverable_id=post_del.deliverable_id,
            deliverable_type='post',
            status='pending',
            label=post_del.label,
        )

        incomplete = incomplete_grading_teams_for_group(self.semester, 'capstone', self.stage.label, config=config)
        self.assertTrue(any('post_defense' in row['missing_components'] for row in incomplete))

        review_submission(self.capstone_team, self.stage.label, post_del.deliverable_id, 'accepted', feedback_val='Approved for archive', reviewer_user=self.adviser)

        incomplete = incomplete_grading_teams_for_group(self.semester, 'capstone', self.stage.label, config=config)
        self.assertEqual(len(incomplete), 0)

        StageCompletionService.complete_group(
            semester=self.semester, scope='capstone', stage_label=self.stage.label, config=config, user=self.admin
        )
        config.refresh_from_db()
        self.assertTrue(config.is_officially_complete)
        self.assertEqual(TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage).status, 'passed')
