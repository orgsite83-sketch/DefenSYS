"""Exercise the real reviewed-import write path in the isolated test database."""
from time import perf_counter
from unittest.mock import patch

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from notifications.models import Notification
from student_teams.models import TeamStageProgress
from . import tests as fixtures
from .models import DefenseSchedule


class ScheduleImportPerformanceTests(APITestCase):
    setUp = fixtures.DefenseSchedulerApiTests.setUp
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages
    create_ready_team = fixtures.DefenseSchedulerApiTests.create_ready_team
    schedule_payload = fixtures.DefenseSchedulerApiTests.schedule_payload

    def test_sixteen_reviewed_slots_keep_writes_bounded_and_preserve_side_effects(self):
        teams = [self.team] + [
            self.create_ready_team(name=f'Import team {index}', username=f'import-{index}')
            for index in range(1, 16)
        ]
        documenter = fixtures.User.objects.create_user(
            username='import-documenter', role='faculty', is_documenter=True,
        )
        saved_ids = []
        query_counts = []
        started = perf_counter()
        # A board projection per row is the expensive operation this path must
        # never reintroduce. All validation and write side effects still run.
        with patch('defense.scheduler.views.list_payload', side_effect=AssertionError('Unexpected board rebuild')):
            for index, team in enumerate(teams):
                minutes = 8 * 60 + index * 30
                with CaptureQueriesContext(connection) as queries:
                    response = self.client.post(
                        '/api/defense/schedules/?response=compact',
                        self.schedule_payload(
                            team_id=team.pk, documenter_id=documenter.pk,
                            start_time=f'{minutes // 60:02d}:{minutes % 60:02d}',
                            slot_duration=30,
                        ), format='json',
                    )
                self.assertEqual(response.status_code, 201, response.data)
                self.assertEqual(set(response.data), {'schedule_id'})
                saved_ids.append(response.data['schedule_id'])
                query_counts.append(len(queries))
        elapsed = perf_counter() - started

        self.assertEqual(len(set(saved_ids)), 16)
        schedules = DefenseSchedule.objects.filter(pk__in=saved_ids)
        self.assertEqual(schedules.count(), 16)
        self.assertEqual(schedules.values('session_id').distinct().count(), 1)
        self.assertEqual(sum(schedule.panel_assignments.count() for schedule in schedules), 32)
        self.assertEqual(sum(schedule.grade_records.count() for schedule in schedules), 16)
        self.assertEqual(TeamStageProgress.objects.filter(
            team__in=teams, defense_stage=self.stage,
            status=TeamStageProgress.STATUS_SCHEDULED,
        ).count(), 16)
        self.assertEqual(Notification.objects.filter(
            recipient=documenter, title='Documenter Assignment',
        ).count(), 16)
        # Adding slots must not add a fresh board's queries to every save.
        self.assertLessEqual(max(query_counts[1:]), query_counts[0] + 4)
        print(f'16-slot compact import: {sum(query_counts)} queries, {elapsed:.3f}s; '
              f'per-slot range {min(query_counts)}-{max(query_counts)}')

