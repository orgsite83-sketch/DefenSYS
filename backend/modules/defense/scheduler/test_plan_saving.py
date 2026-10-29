"""Exercise complete schedule confirmations in the isolated test database."""
from time import perf_counter
from unittest.mock import patch
from types import SimpleNamespace

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase
from rest_framework.exceptions import ValidationError

from grading.grades.models import TeamGrade
from notifications.models import Notification
from student_teams.models import TeamStageProgress
from user_management.models import ExternalEvaluator, GuestPanelistCode
from . import tests as fixtures
from .models import DefenseSchedule, SchedulePanelist
from .serializers import ConfirmSchedulePlanSerializer


class SchedulePlanSavingTests(APITestCase):
    setUp = fixtures.DefenseSchedulerApiTests.setUp
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages
    create_ready_team = fixtures.DefenseSchedulerApiTests.create_ready_team
    schedule_payload = fixtures.DefenseSchedulerApiTests.schedule_payload

    def test_sixteen_team_plan_preserves_sessions_and_all_save_side_effects(self):
        teams = [self.team] + [self.create_ready_team(
            name=f'Plan team {i}', username=f'plan-student-{i}') for i in range(1, 16)]
        documenter = fixtures.User.objects.create_user(
            username='plan-documenter', role='faculty', is_documenter=True)
        evaluator = ExternalEvaluator.objects.create(
            name='Plan guest', email='plan@example.edu', status='approved',
            created_by=self.admin, reviewed_by=self.admin)
        sessions = [{
            'key': f'day-{day}', 'scheduled_date': f'2026-05-{15 + day}',
            'start_time': '08:00', 'end_time': '17:00', 'slot_duration': 60,
            'room': 'Smart Room', 'team_ids': [team.pk for team in teams[day * 8:(day + 1) * 8]],
            'time_blocks': [{'start_time': '08:00', 'end_time': '12:00'},
                            {'start_time': '13:00', 'end_time': '17:00'}],
        } for day in range(2)]
        payload = self.schedule_payload(sessions=sessions, documenter_id=documenter.pk,
            external_evaluator_ids=[evaluator.pk], slots=[
                {'team_id': team.pk, 'session_key': f'day-{i // 8}'} for i, team in enumerate(teams)])

        started = perf_counter()
        with CaptureQueriesContext(connection) as queries, \
             patch('defense.scheduler.views.list_payload', side_effect=AssertionError('Save rebuilt the board')), \
             patch('defense.scheduler.views.DefenseScheduleSerializer', side_effect=AssertionError('Save serialized the board')):
            response = self.client.post('/api/defense/schedules/confirm-plan/?response=compact', payload, format='json')
        elapsed = perf_counter() - started
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['created_count'], 16)
        self.assertEqual(set(response.data), {'created_count', 'schedule_ids', 'created_invitations'})
        self.assertEqual(len(set(response.data['schedule_ids'])), 16)
        saved = DefenseSchedule.objects.all()
        self.assertEqual(saved.count(), 16)
        self.assertEqual(saved.values('batch_id').distinct().count(), 1)
        self.assertEqual(saved.values('session_id').distinct().count(), 2)
        self.assertEqual(SchedulePanelist.objects.filter(schedule__in=saved).count(), 32)
        self.assertEqual(SchedulePanelist.objects.filter(schedule__in=saved, is_chair=True).count(), 16)
        self.assertEqual(TeamGrade.objects.filter(schedule__in=saved).count(), 16)
        self.assertEqual(TeamStageProgress.objects.filter(team__in=teams,
            defense_stage=self.stage, status=TeamStageProgress.STATUS_SCHEDULED).count(), 16)
        self.assertEqual(Notification.objects.filter(recipient=documenter,
            title='Documenter Assignment').count(), 16)
        invites = GuestPanelistCode.objects.filter(evaluator=evaluator)
        self.assertEqual(invites.count(), 2)
        self.assertEqual(sorted(invite.schedules.count() for invite in invites), [8, 8])
        self.assertEqual(len(response.data['created_invitations']), 2)
        print(f'16-team plan save: {len(queries)} queries, {elapsed:.3f}s', flush=True)
        # A retry after a lost acknowledgement must never duplicate a batch.
        retry = self.client.post('/api/defense/schedules/confirm-plan/?response=compact', payload, format='json')
        self.assertEqual(retry.status_code, 400, retry.data)
        self.assertEqual(DefenseSchedule.objects.count(), 16)
        self.assertEqual(GuestPanelistCode.objects.count(), 2)
        self.assertEqual(Notification.objects.filter(recipient=documenter,
            title='Documenter Assignment').count(), 16)

    def test_locked_validation_does_not_reuse_pre_lock_readiness(self):
        serializer = ConfirmSchedulePlanSerializer(
            data=self.schedule_payload(slots=[{'team_id': self.team.pk}]),
            context={'request': SimpleNamespace(user=self.admin)})
        serializer.is_valid(raise_exception=True)
        TeamStageProgress.objects.filter(team=self.team, defense_stage=self.stage).delete()
        with self.assertRaises(ValidationError):
            serializer.save()
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_late_save_failure_rolls_back_schedules_invitations_grades_and_notifications(self):
        from grading.grades.services import _sync_grade_for_schedule

        second = self.create_ready_team()
        documenter = fixtures.User.objects.create_user(
            username='rollback-documenter', role='faculty', is_documenter=True)
        evaluator = ExternalEvaluator.objects.create(
            name='Rollback guest', email='rollback@example.edu', status='approved',
            created_by=self.admin, reviewed_by=self.admin)
        payload = self.schedule_payload(documenter_id=documenter.pk,
            external_evaluator_ids=[evaluator.pk], slots=[{'team_id': self.team.pk}, {'team_id': second.pk}])
        calls = 0

        def fail_second(schedule, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise ValidationError({'detail': 'Simulated late grade initialization failure'})
            return _sync_grade_for_schedule(schedule, **kwargs)

        with patch('grading.grades.services._sync_grade_for_schedule', side_effect=fail_second):
            response = self.client.post('/api/defense/schedules/confirm-plan/?response=compact', payload, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(calls, 2)
        self.assertFalse(DefenseSchedule.objects.exists())
        self.assertFalse(SchedulePanelist.objects.exists())
        self.assertFalse(GuestPanelistCode.objects.exists())
        self.assertFalse(TeamGrade.objects.filter(defense_stage=self.stage).exists())
        self.assertFalse(Notification.objects.filter(recipient=documenter,
            title='Documenter Assignment').exists())
        self.assertEqual(TeamStageProgress.objects.filter(team__in=[self.team, second],
            defense_stage=self.stage, status=TeamStageProgress.STATUS_READY).count(), 2)
