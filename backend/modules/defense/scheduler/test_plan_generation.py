"""Preview performance must preserve eligibility and confirmation checks."""
from unittest.mock import patch

from rest_framework.test import APITestCase

from student_teams.models import TeamStageProgress
from . import tests as fixtures
from .models import DefenseSchedule


class SchedulePlanGenerationTests(APITestCase):
    setUp = fixtures.DefenseSchedulerApiTests.setUp
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages
    schedule_payload = fixtures.DefenseSchedulerApiTests.schedule_payload

    def preview(self, **overrides):
        return self.client.post(
            '/api/defense/schedules/generate-plan/?response=compact',
            self.schedule_payload(sessions=[{
                'key': 'session-1', 'scheduled_date': '2026-05-15',
                'start_time': '08:00', 'end_time': '10:00',
                'slot_duration': 60, 'room': 'Room 301',
                'team_ids': [self.team.pk],
            }], **overrides), format='json',
        )

    def test_compact_preview_skips_board_rebuild_and_does_not_save_schedules(self):
        with patch('defense.scheduler.views.schedule_options_payload',
                   side_effect=AssertionError('Preview rebuilt scheduler options')):
            response = self.preview()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(set(response.data), {'slots', 'slot_count', 'unassigned_count'})
        self.assertEqual(response.data['slot_count'], 1)
        self.assertEqual(response.data['unassigned_count'], 0)
        slot = response.data['slots'][0]
        self.assertEqual(slot['team_id'], self.team.pk)
        self.assertEqual(slot['session_key'], 'session-1')
        self.assertEqual(str(slot['start_time']), '08:00:00')
        self.assertEqual(str(slot['end_time']), '09:00:00')
        self.assertEqual(len(slot['panelists']), 2)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_later_preview_and_confirmation_recheck_changed_readiness(self):
        generated = self.preview()
        self.assertEqual(generated.status_code, 200, generated.data)
        TeamStageProgress.objects.filter(team=self.team, defense_stage=self.stage).delete()
        rejected = self.preview()
        self.assertEqual(rejected.status_code, 400, rejected.data)
        self.assertIn('not eligible', str(rejected.data))
        confirmed = self.client.post('/api/defense/schedules/confirm-plan/',
            self.schedule_payload(slots=[{'team_id': self.team.pk}]), format='json')
        self.assertEqual(confirmed.status_code, 400, confirmed.data)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_compact_preview_retains_adviser_conflict_validation(self):
        response = self.preview(panelist_ids=[self.adviser.pk])
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('team adviser cannot', str(response.data['slots']))
        self.assertFalse(DefenseSchedule.objects.exists())
