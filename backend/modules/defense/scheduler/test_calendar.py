from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from . import tests as fixtures
from .models import DefenseSchedule


class ScheduleCalendarApiTests(APITestCase):
    setUp = fixtures.DefenseSchedulerApiTests.setUp
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages
    schedule_payload = fixtures.DefenseSchedulerApiTests.schedule_payload

    def configure(self):
        Semester.objects.filter(pk=self.semester.pk).update(starts_on='2026-05-15', ends_on='2026-05-16')

    def test_manual_schedule_requires_calendar_and_rejects_outside_dates(self):
        Semester.objects.filter(pk=self.semester.pk).update(starts_on=None, ends_on=None)
        response = self.client.post('/api/defense/schedules/', self.schedule_payload(team_id=self.team.pk), format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('scheduled_date', response.data)
        self.configure()
        response = self.client.post('/api/defense/schedules/',
            self.schedule_payload(team_id=self.team.pk, scheduled_date='2026-05-17'), format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(DefenseSchedule.objects.exists())

    def test_each_session_is_validated_and_calendar_change_invalidates_confirmation(self):
        self.configure()
        session = {'key': 'day-1', 'scheduled_date': '2026-05-15', 'start_time': '08:00',
            'end_time': '10:00', 'slot_duration': 60, 'room': 'Lab 1', 'team_ids': [self.team.pk]}
        # The common date is unused when sessions specify their own dates.
        payload = self.schedule_payload(sessions=[session], scheduled_date='2026-11-27')
        generated = self.client.post('/api/defense/schedules/generate-plan/', payload, format='json')
        self.assertEqual(generated.status_code, 200, generated.data)
        invalid = self.client.post('/api/defense/schedules/generate-plan/',
            {**payload, 'sessions': [{**session, 'scheduled_date': '2026-05-17'}]}, format='json')
        self.assertEqual(invalid.status_code, 400)
        self.assertIn('sessions', invalid.data)
        Semester.objects.filter(pk=self.semester.pk).update(starts_on='2026-05-16', ends_on='2026-05-17')
        confirmed = self.client.post('/api/defense/schedules/confirm-plan/',
            {**payload, 'slots': generated.data['slots']}, format='json')
        self.assertEqual(confirmed.status_code, 400)
        self.assertFalse(DefenseSchedule.objects.exists())
