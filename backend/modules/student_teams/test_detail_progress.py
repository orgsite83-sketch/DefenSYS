"""Assigned PIT events remain visible before evaluation; detail reads never write."""
from datetime import date

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from grading.grades.models import TeamGrade
from . import test_formation as fixtures
from .models import PITEventRoster, PITRosterTeamDetails
from .pit_rosters import register


class TeamDetailProgressTests(APITestCase):
    existing = fixtures.TeamFormationTests.existing

    def setUp(self):
        fixtures.TeamFormationTests.setUp(self)
        self.team = self.existing()
        self.team.current_defense_stage = None
        self.team.save(update_fields=['current_defense_stage'])
        register([self.team], self.lead)

    def detail(self, **params):
        return self.client.get(f'/api/teams/{self.team.pk}/', params)

    def test_assigned_ungraded_events_and_schedule_are_visible_without_writes(self):
        later = PitEventGradingConfig.objects.create(semester=self.term,
            year_level='2nd Year', event_name='Later showcase')
        PitEventGradingConfig.objects.create(semester=self.term,
            year_level='1st Year', event_name='Other year')
        DefenseSchedule.objects.create(team=self.team, semester=self.term, scope='pit',
            event_name=later.event_name, scheduled_date=date(2026, 11, 2),
            start_time='13:00', slot_duration=60, room='Room 101')
        with CaptureQueriesContext(connection) as queries:
            response = self.detail(event_id=later.pk)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['selected_event_name'], later.event_name)
        self.assertEqual([row['event_name'] for row in response.data['team_events']],
                         [self.event.event_name, later.event_name])
        row = response.data['team_events'][1]
        self.assertEqual(row['context']['scheduling_status'], 'scheduled')
        self.assertEqual(row['schedule']['room'], 'Room 101')
        self.assertFalse(TeamGrade.objects.exists())
        self.assertEqual(response.data['team']['defense_context']['event_label'], later.event_name)
        self.assertEqual(response.data['legacy_reports_count'], 0)
        self.assertFalse(any(q['sql'].lstrip().split()[0].upper() in ('INSERT', 'UPDATE', 'DELETE')
                             for q in queries))
        self.assertFalse(any('student_weekly_progress_weeklyprogressreport' in q['sql'] for q in queries))

    def test_unassigned_event_and_other_year_are_rejected(self):
        other = PitEventGradingConfig.objects.create(semester=self.term,
            year_level='1st Year', event_name='Other year')
        self.assertEqual(self.detail(event_id=other.pk).status_code, 400)
        self.assertEqual(self.detail(event_name='Unknown event').status_code, 400)

    def test_an_event_override_excludes_unassigned_team_but_keeps_recorded_history(self):
        roster = PITEventRoster.objects.create(section=self.team.section, event=self.event, source='custom')
        self.assertEqual(self.detail().data['team_events'], [])
        roster.teams.add(self.team)
        TeamGrade.objects.create(team=self.team, semester=self.term, scope='pit',
            pit_event_config=self.event, stage_label=self.event.event_name, panel_weight=80, peer_weight=20, adviser_weight=0)
        roster.teams.remove(self.team)
        response = self.detail()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['team_events'][0]['historical'])
        self.assertFalse(roster.teams.exists())

    def test_done_presentation_does_not_publish_grade(self):
        grade = TeamGrade.objects.create(team=self.team, semester=self.term, scope='pit',
            pit_event_config=self.event, stage_label=self.event.event_name, panel_weight=80, peer_weight=20, adviser_weight=0)
        DefenseSchedule.objects.create(team=self.team, semester=self.term, scope='pit',
            event_name=self.event.event_name, scheduled_date=date(2026, 11, 2),
            start_time='13:00', slot_duration=60, room='Room 101', status='done')
        response = self.detail()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['team_events'][0]['schedule']['status'], 'done')
        grade.refresh_from_db()
        self.assertNotEqual(grade.status, 'published')

    def test_unrelated_students_cannot_read_progress(self):
        self.client.force_authenticate(self.students[-1])
        self.assertIn(self.detail().status_code, (403, 404))

    def test_selected_event_keeps_its_own_overview_name(self):
        later = PitEventGradingConfig.objects.create(semester=self.term,
            year_level='2nd Year', event_name='Later showcase')
        PITRosterTeamDetails.objects.create(team=self.team, event=self.event, name='First event team')
        PITRosterTeamDetails.objects.create(team=self.team, event=later, name='Second event team')
        first = self.detail(event_id=self.event.pk)
        second = self.detail(event_id=later.pk)
        self.assertEqual(first.data['team']['name'], 'First event team')
        self.assertEqual(second.data['team']['name'], 'Second event team')
        self.team.refresh_from_db()
        self.assertNotEqual(self.team.name, 'Second event team')
