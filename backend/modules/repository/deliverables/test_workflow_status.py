"""Deliverable badges follow assessment evidence without mutating the workflow."""
from datetime import time

from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from defense.scheduler.models import DefenseSchedule, PitEventDeliverable, PitEventGradingConfig
from defense.scheduler.progress import schedule_progress
from defense.stages.models import StageDeliverable
from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam
from . import test_submission_timing as fixtures
from .services import stage_payload


class DeliverableWorkflowStatusTests(APITestCase):
    setUp = fixtures.SubmissionTimingTests.setUp
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
        progress = stage_payload(self.team, self.stage.label)['assessment_progress']
        self.assertEqual(progress['display_status'], 'awaiting_verdict')
        self.assertFalse(progress['is_completed'])

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
        self.assertTrue(payload['assessment_progress']['is_completed'])
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
