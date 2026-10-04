from datetime import datetime, timedelta, timezone as datetime_timezone
from unittest.mock import patch

from django.utils import timezone
from rest_framework.test import APITestCase

from authentication_access_control.guest_authentication import GuestPanelistPrincipal
from grading.grades.models import PanelistGradeSubmission
from grading.grades.services import GradeContextService
from grading.rubrics.models import Rubric
from student_teams.models import TeamMembership
from . import tests as fixtures
from .models import DefenseSchedule, PanelistEvaluationDraft, SchedulePanelist
from .panelist_evaluation import evaluation_context


class PanelistEvaluationTests(APITestCase):
    def setUp(self):
        fixtures.DefenseSchedulerApiTests.setUp(self)
        self.client.force_authenticate(user=self.panelist)

    def schedule(self, **overrides):
        values = dict(
            scope=DefenseSchedule.SCOPE_CAPSTONE, semester=self.semester,
            team=self.team, defense_stage=self.stage, rubric=self.rubric,
            scheduled_date=timezone.localdate(), start_time='08:00',
            slot_duration=30, room='Room 301', created_by=self.admin,
        )
        values.update(overrides)
        schedule = DefenseSchedule.objects.create(**values)
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.panelist, is_chair=True)
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.second_panelist, order=1)
        return schedule

    def scores(self, score=0):
        return fixtures.DefenseSchedulerApiTests.criteria_scores(self, score)

    def save_draft(self, schedule, submissions=None, **overrides):
        payload = {
            'schedule_id': schedule.pk,
            'evaluation_context': evaluation_context(schedule, schedule.grade_records.first()),
            'submissions': submissions or [{
                'student_id': None,
                'criteria_scores': [self.scores()[0]],
                'remarks': 'Review the prototype',
            }],
        }
        payload.update(overrides)
        return self.client.post('/api/defense/schedules/grade-draft/', payload, format='json')

    def test_grading_is_available_early_late_and_after_slot_in_manila(self):
        schedule = self.schedule(scheduled_date='2026-10-20', start_time='08:00')
        # UTC 16:30 on the previous day is 00:30 on defense day in Manila.
        for now in [
            datetime(2026, 10, 19, 16, 30, tzinfo=datetime_timezone.utc),
            datetime(2026, 10, 20, 15, 50, tzinfo=datetime_timezone.utc),
            datetime(2026, 10, 21, 1, 0, tzinfo=datetime_timezone.utc),
        ]:
            with self.subTest(now=now), patch('django.utils.timezone.now', return_value=now):
                response = self.client.get('/api/defense/schedules/panelist-assignments/')
                self.assertTrue(response.data['teams'][0]['grading_available'])
                self.assertEqual(self.save_draft(schedule).status_code, 200)

    def test_upcoming_defense_blocks_draft_submission_and_verdict(self):
        schedule = self.schedule(scheduled_date=timezone.localdate() + timedelta(days=1))
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertFalse(response.data['teams'][0]['grading_available'])
        self.assertFalse(response.data['teams'][0]['can_issue_verdict'])
        self.assertEqual(self.save_draft(schedule).status_code, 400)
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk,
            'criteria_scores': self.scores(8),
        }, format='json')
        self.assertEqual(response.status_code, 400)
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        grade.panel_score = 80
        grade.save(update_fields=['panel_score'])
        response = self.client.patch(f'/api/defense/schedules/{schedule.pk}/verdict/',
                                     {'verdict': 'approved'}, format='json')
        self.assertEqual(response.status_code, 400)
        grade.refresh_from_db()
        self.assertFalse(grade.verdict)

    def test_chair_role_is_preserved_while_verdict_waits_for_panel_grading(self):
        schedule = self.schedule()
        assignment = self.client.get('/api/defense/schedules/panelist-assignments/').data['teams'][0]
        self.assertTrue(assignment['is_chair'])
        self.assertTrue(assignment['grading_available'])
        self.assertFalse(assignment['can_issue_verdict'])
        self.assertEqual(assignment['verdict_unavailable_reason'],
                         'Panel grading must be submitted before issuing a verdict.')
        response = self.client.patch(f'/api/defense/schedules/{schedule.pk}/verdict/',
                                     {'verdict': 'approved'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], assignment['verdict_unavailable_reason'])
        self.assertFalse(schedule.grade_records.first().verdict)

    def test_submitted_zero_scores_unlock_verdict_only_for_the_chair(self):
        schedule = self.schedule()
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk, 'criteria_scores': self.scores(0),
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        assignment = self.client.get('/api/defense/schedules/panelist-assignments/').data['teams'][0]
        self.assertTrue(assignment['is_chair'])
        self.assertTrue(assignment['can_issue_verdict'])
        self.assertEqual(assignment['verdict_unavailable_reason'], '')
        self.client.force_authenticate(user=self.second_panelist)
        member_assignment = self.client.get('/api/defense/schedules/panelist-assignments/').data['teams'][0]
        self.assertFalse(member_assignment['is_chair'])
        self.assertFalse(member_assignment['can_issue_verdict'])
        self.assertEqual(self.client.patch(f'/api/defense/schedules/{schedule.pk}/verdict/',
                                          {'verdict': 'approved'}, format='json').status_code, 403)
        self.client.force_authenticate(user=self.panelist)
        self.assertEqual(self.client.patch(f'/api/defense/schedules/{schedule.pk}/verdict/',
                                          {'verdict': 'approved'}, format='json').status_code, 200)

    def test_paused_defense_reports_the_same_verdict_lock_as_submission(self):
        schedule = self.schedule(operation_state='paused')
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        grade.panel_score = 80
        grade.save(update_fields=['panel_score'])
        assignment = self.client.get('/api/defense/schedules/panelist-assignments/').data['teams'][0]
        self.assertTrue(assignment['is_chair'])
        self.assertFalse(assignment['can_issue_verdict'])
        self.assertIn('paused', assignment['verdict_unavailable_reason'])
        response = self.client.patch(f'/api/defense/schedules/{schedule.pk}/verdict/',
                                     {'verdict': 'approved'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['detail'], assignment['verdict_unavailable_reason'])
        grade.refresh_from_db()
        self.assertFalse(grade.verdict)

    def test_draft_restores_zero_and_remarks_without_contributing_grades(self):
        schedule = self.schedule()
        self.assertEqual(self.save_draft(schedule).status_code, 200)
        self.assertFalse(PanelistGradeSubmission.objects.filter(schedule=schedule).exists())
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        self.assertIsNone(grade.panel_score)
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        team = response.data['teams'][0]
        self.assertFalse(team['is_submitted'])
        self.assertEqual(team['draft']['submissions'][0]['criteria_scores'][0]['score'], 0)
        self.assertEqual(team['draft']['submissions'][0]['remarks'], 'Review the prototype')

    def test_draft_is_private_to_owner(self):
        schedule = self.schedule()
        self.assertEqual(self.save_draft(schedule).status_code, 200)
        self.client.force_authenticate(user=self.second_panelist)
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertIsNone(response.data['teams'][0]['draft'])
        self.client.force_authenticate(user=self.adviser)
        self.assertEqual(self.save_draft(schedule).status_code, 403)
        self.assertEqual(PanelistEvaluationDraft.objects.count(), 1)

    def test_changed_rubric_hides_stale_draft_and_rejects_old_context(self):
        schedule = self.schedule()
        context = evaluation_context(schedule, schedule.grade_records.first())
        self.assertEqual(self.save_draft(schedule).status_code, 200)
        self.criterion.max_score = 5
        self.criterion.save(update_fields=['max_score'])
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertIsNone(response.data['teams'][0]['draft'])
        self.assertEqual(self.save_draft(schedule, evaluation_context=context).status_code, 400)

    def test_rescheduled_defense_hides_stale_draft(self):
        schedule = self.schedule()
        self.assertEqual(self.save_draft(schedule).status_code, 200)
        schedule.scheduled_date += timedelta(days=1)
        schedule.save(update_fields=['scheduled_date'])
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertIsNone(response.data['teams'][0]['draft'])
        self.assertFalse(response.data['teams'][0]['grading_available'])

    def test_incomplete_final_scores_are_rejected_before_writes(self):
        schedule = self.schedule()
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk,
            'criteria_scores': [self.scores()[0]],
        }, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(PanelistGradeSubmission.objects.exists())

    def test_both_rubric_requires_every_member_before_any_submission(self):
        self.rubric.target_type = Rubric.TARGET_BOTH
        self.rubric.save(update_fields=['target_type'])
        self.second_criterion.target_type = 'individual'
        self.second_criterion.save(update_fields=['target_type'])
        student = fixtures.User.objects.create_user(username='second-student', role='student')
        TeamMembership.objects.create(team=self.team, student=student, order=1)
        schedule = self.schedule()
        team_scores, individual_score = self.scores()
        submissions = [
            {'student_id': None, 'criteria_scores': [team_scores]},
            {'student_id': self.student.pk, 'criteria_scores': [individual_score]},
        ]
        payload = {'team_id': self.team.pk, 'schedule_id': schedule.pk, 'submissions': submissions}
        response = self.client.post('/api/defense/schedules/submit-grades/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(PanelistGradeSubmission.objects.exists())
        submissions.append({'student_id': student.pk, 'criteria_scores': [individual_score]})
        response = self.client.post('/api/defense/schedules/submit-grades/', payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(PanelistGradeSubmission.objects.count(), 3)

    def test_submission_clears_draft_and_prevents_score_overwrites(self):
        schedule = self.schedule()
        self.assertEqual(self.save_draft(schedule).status_code, 200)
        payload = {'team_id': self.team.pk, 'schedule_id': schedule.pk, 'criteria_scores': self.scores()}
        response = self.client.post('/api/defense/schedules/submit-grades/', payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['panel_score'], 0)
        self.assertFalse(PanelistEvaluationDraft.objects.exists())
        self.assertEqual(self.save_draft(schedule).status_code, 400)
        payload['criteria_scores'] = self.scores(10)
        self.assertEqual(self.client.post('/api/defense/schedules/submit-grades/', payload, format='json').status_code, 400)
        submission = PanelistGradeSubmission.objects.get()
        self.assertTrue(all(score.score == 0 for score in submission.criterion_scores.all()))

    def test_guest_draft_is_private_and_resumes_without_submission(self):
        schedule = self.schedule()
        from user_management.models import GuestPanelistCode
        invitation = GuestPanelistCode.objects.create(guest_name='Guest Panelist', defense_schedule=schedule)
        invitation.schedules.add(schedule)
        guest = GuestPanelistPrincipal({
            'guest_code_id': str(invitation.pk), 'defense_schedule_id': schedule.pk,
            'team_id': self.team.pk, 'guest_name': 'Guest Panelist',
        })
        self.client.force_authenticate(user=guest)
        payload = {
            'schedule_id': schedule.pk,
            'evaluation_context': evaluation_context(schedule, schedule.grade_records.first()),
            'submissions': [{'student_id': None, 'criteria_scores': [self.scores()[0]]}],
        }
        response = self.client.post('/api/defense/schedules/guest-grade-draft/', payload, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        response = self.client.get('/api/defense/schedules/guest-assignments/')
        self.assertIsNotNone(response.data['teams'][0]['draft'])
        self.assertFalse(response.data['teams'][0]['is_submitted'])
        self.assertFalse(PanelistGradeSubmission.objects.exists())
        payload['schedule_id'] = schedule.pk + 1
        self.assertEqual(self.client.post('/api/defense/schedules/guest-grade-draft/', payload, format='json').status_code, 403)

    def test_cancelled_defense_blocks_draft_and_final_submission(self):
        schedule = self.schedule()
        schedule.status = DefenseSchedule.STATUS_CANCELLED
        schedule.save(update_fields=['status'])
        self.assertEqual(self.save_draft(schedule).status_code, 400)
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': schedule.pk, 'criteria_scores': self.scores(),
        }, format='json')
        self.assertNotEqual(response.status_code, 201)
        self.assertFalse(PanelistGradeSubmission.objects.exists())

    def test_officially_closed_stage_blocks_drafts_and_grading_availability(self):
        schedule = self.schedule()
        GradeContextService.get_or_create_for_schedule(schedule)
        config = fixtures.StageGradingConfig.objects.get(
            defense_stage=self.stage, semester=self.semester,
        )
        config.is_officially_complete = True
        config.save(update_fields=['is_officially_complete'])
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertFalse(response.data['teams'][0]['grading_available'])
        self.assertIn('officially complete', response.data['teams'][0]['grading_unavailable_reason'])
        self.assertEqual(self.save_draft(schedule).status_code, 400)
        self.assertFalse(PanelistEvaluationDraft.objects.exists())
