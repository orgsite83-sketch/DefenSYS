"""Deliverable badges follow assessment evidence without mutating the workflow."""
from datetime import time

from django.contrib.auth import get_user_model
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from defense.scheduler.models import DefenseSchedule, PitEventDeliverable, PitEventGradingConfig, SchedulePanelist
from defense.scheduler.progress import schedule_progress
from defense.stages.models import StageDeliverable
from grading.grades.models import TeamGrade, PanelistGradeSubmission, PanelistCriterionScore
from grading.rubrics.models import Rubric, RubricCriterion
from student_teams.models import StudentTeam
from . import test_submission_timing as fixtures
from .services import post_defense_ready, stage_payload


class DeliverableWorkflowStatusTests(APITestCase):
    setUp = fixtures.faculty_review_setup
    upload = fixtures.SubmissionTimingTests.upload
    clear_and_endorse = fixtures.SubmissionTimingTests.clear_and_endorse
    schedule = fixtures.SubmissionTimingTests.schedule

    def grade(self, schedule, **kwargs):
        return TeamGrade.objects.create(team=self.team, semester=self.semester,
            defense_stage=self.stage, schedule=schedule, **kwargs)

    def test_today_without_evaluation_is_not_ongoing(self):
        schedule = self.schedule()
        schedule.scheduled_date = timezone.localdate()
        schedule.save(update_fields=['scheduled_date'])
        progress = stage_payload(self.team, self.stage.label)['assessment_progress']
        self.assertEqual(progress['display_status'], 'awaiting_evaluation')
        self.assertFalse(progress['is_completed'])

    def test_panel_score_and_done_schedule_are_not_completion(self):
        schedule = self.schedule()
        self.grade(schedule, panel_score=80)
        schedule.status = DefenseSchedule.STATUS_DONE
        schedule.save(update_fields=['status'])
        payload = stage_payload(self.team, self.stage.label)
        progress = payload['assessment_progress']
        self.assertEqual(progress['display_status'], 'awaiting_verdict')
        self.assertFalse(progress['is_completed'])
        self.assertFalse(payload['post_defense_ready'])

    def test_schedule_and_upload_override_do_not_reveal_post_defense_requirements(self):
        schedule = self.schedule()
        schedule.status = DefenseSchedule.STATUS_DONE
        schedule.save(update_fields=['status'])
        self.team.unlocked_stages = [f'{self.stage.label}:post']
        self.team.save(update_fields=['unlocked_stages'])
        payload = stage_payload(self.team, self.stage.label)
        self.assertTrue(payload['archive_unlocked'])
        self.assertFalse(payload['post_defense_ready'])

    def test_passing_verdict_opens_requirements_before_archive_dependent_closure(self):
        schedule = self.schedule()
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='FINAL',
            label='Final paper', deliverable_type='post', required=True)
        grade = self.grade(schedule, panel_score=80)
        for verdict in TeamGrade.PASSING_VERDICTS:
            with self.subTest(verdict=verdict):
                grade.verdict = verdict
                grade.save(update_fields=['verdict'])
                payload = stage_payload(self.team, self.stage.label)
                self.assertTrue(payload['post_defense_ready'])
                self.assertFalse(payload['archive_complete'])
                self.assertFalse(payload['assessment_progress']['is_completed'])
                self.assertIsNone(grade.revisions_cleared_at)

    def test_nonpassing_verdicts_keep_archive_requirements_hidden(self):
        schedule = self.schedule()
        grade = self.grade(schedule, panel_score=80)
        for verdict in ('', 'for_redefense', 'failed', 'project_rejected'):
            with self.subTest(verdict=verdict):
                grade.verdict = verdict
                grade.save(update_fields=['verdict'])
                self.assertFalse(post_defense_ready(self.team, self.stage.label))

    def test_every_assigned_panelist_must_submit_a_complete_evaluation(self):
        schedule = self.schedule()
        rubric = Rubric.objects.create(name='Archive visibility panel', scope='capstone', semester=self.semester,
            defense_stage=self.stage, evaluation_type='panel', target_type='team', status='published')
        criterion = RubricCriterion.objects.create(rubric=rubric, name='Quality', max_score=10)
        schedule.rubric = rubric
        schedule.save(update_fields=['rubric'])
        second = get_user_model().objects.create_user(username='visibility-panel', role='faculty')
        for panelist in (self.admin, second):
            SchedulePanelist.objects.create(schedule=schedule, panelist=panelist)
        grade = self.grade(schedule, panel_score=80, verdict='approved')

        def submission(panelist):
            return PanelistGradeSubmission.objects.create(team_grade=grade, schedule=schedule, panelist=panelist)

        def score(row):
            PanelistCriterionScore.objects.create(submission=row, criterion=criterion, score=8,
                criterion_name_snapshot=criterion.name, max_score_snapshot=10)

        score(submission(self.admin))
        self.assertFalse(post_defense_ready(self.team, self.stage.label))
        last = submission(second)
        self.assertFalse(post_defense_ready(self.team, self.stage.label))
        score(last)
        self.assertTrue(post_defense_ready(self.team, self.stage.label))
        last.is_void = True
        last.save(update_fields=['is_void'])
        self.assertFalse(post_defense_ready(self.team, self.stage.label))

    def test_pit_panel_completion_needs_no_capstone_verdict_or_archive_closure(self):
        self.team.level = StudentTeam.LEVEL_3_PIT
        self.team.save(update_fields=['level'])
        event = PitEventGradingConfig.objects.create(semester=self.semester,
            year_level='3rd Year', event_name=self.stage.label)
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            scope='pit', event_name=event.event_name, scheduled_date=self.date,
            start_time=time(9), room='PIT Hall')
        grade = TeamGrade.objects.create(team=self.team, semester=self.semester, scope='pit',
            pit_event_config=event, stage_label=event.event_name, schedule=schedule,
            panel_weight=80, peer_weight=20)
        self.assertFalse(post_defense_ready(self.team, event.event_name))
        grade.panel_score = 0
        grade.save(update_fields=['panel_score'])
        self.assertTrue(post_defense_ready(self.team, event.event_name))
        event.concept_config = {'enabled': True, 'required_count': 3}
        event.save(update_fields=['concept_config'])
        self.assertFalse(post_defense_ready(self.team, event.event_name))

    def test_status_presentation_never_reconciles_or_writes_records(self):
        schedule = self.schedule()
        self.grade(schedule, panel_score=80, verdict='approved')
        DefenseSchedule.objects.filter(pk=schedule.pk).update(status=DefenseSchedule.STATUS_SCHEDULED)
        with CaptureQueriesContext(connection) as captured:
            payload = stage_payload(self.team, self.stage.label)
        self.assertFalse(payload['assessment_progress']['is_completed'])
        writes = [q['sql'] for q in captured if q['sql'].lstrip().upper().startswith(('UPDATE ', 'INSERT ', 'DELETE '))]
        self.assertEqual(writes, [])
        schedule.refresh_from_db()
        self.assertEqual(schedule.status, DefenseSchedule.STATUS_SCHEDULED)
        # A read-only cache must not suppress the existing operational behavior.
        schedule_progress(schedule, reconcile_status=False)
        schedule_progress(schedule)
        schedule.refresh_from_db()
        self.assertEqual(schedule.status, DefenseSchedule.STATUS_DONE)

    def test_published_assessment_exposes_outstanding_post_defense_files(self):
        schedule = self.schedule()
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='FINAL',
            label='Final paper', deliverable_type='post', required=True)
        self.grade(schedule, panel_score=80, peer_score=80, adviser_score=80,
            verdict='approved', status=TeamGrade.STATUS_PUBLISHED)
        payload = stage_payload(self.team, self.stage.label)
        self.assertFalse(payload['assessment_progress']['is_completed'])
        self.assertTrue(payload['assessment_progress']['assessment_finalized'])
        self.assertEqual(payload['assessment_progress']['display_status'], 'pending_post_defense')
        self.assertTrue(payload['post_defense_ready'])
        self.assertFalse(payload['archive_complete'])

    def test_finalized_pit_event_is_completed_even_with_a_low_result(self):
        self.team.level = StudentTeam.LEVEL_3_PIT
        self.team.save(update_fields=['level'])
        event = PitEventGradingConfig.objects.create(semester=self.semester,
            year_level='3rd Year', event_name=self.stage.label)
        PitEventDeliverable.objects.create(pit_event_config=event, deliverable_id='PAPER', label='Paper')
        schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
            scope='pit', event_name=event.event_name, scheduled_date=self.date,
            start_time=time(9), room='PIT Hall')
        TeamGrade.objects.create(team=self.team, semester=self.semester, scope='pit',
            pit_event_config=event, stage_label=event.event_name, schedule=schedule,
            panel_score=0, peer_score=0, panel_weight=80, peer_weight=20,
            status=TeamGrade.STATUS_PUBLISHED)
        progress = stage_payload(self.team, event.event_name)['assessment_progress']
        self.assertEqual(progress['display_status'], 'completed')
        self.assertTrue(progress['is_completed'])
        self.assertEqual(progress['published_result'], 'failed')

    def test_old_term_schedule_does_not_become_current_stage_status(self):
        self.schedule()
        self.team.semester = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        self.team.save(update_fields=['semester'])
        payload = stage_payload(self.team, self.stage.label)
        self.assertIsNone(payload['schedule'])
        self.assertIsNone(payload['assessment_progress'])
        self.assertFalse(payload['post_defense_ready'])
