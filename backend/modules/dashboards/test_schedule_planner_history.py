from datetime import date, timedelta
from decimal import Decimal
from uuid import uuid4

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from student_teams.models import StudentTeam


User = get_user_model()


class SchedulePlannerHistoryTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='calendar-admin', role='admin')
        self.lead = User.objects.create_user(
            username='calendar-lead', role='faculty', is_pit_lead=True,
            pit_lead_year='1st Year',
        )
        self.semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2026-2027'),
            label=Semester.FIRST, is_active=True,
        )
        self.day = date(2026, 10, 14)
        self.stage = DefenseStage.objects.create(label='Proposal Defense')
        self.sequence = 0

    def schedule(self, *, year='1st Year', scope='pit', **kwargs):
        self.sequence += 1
        leader = User.objects.create_user(username=f'calendar-student-{self.sequence}', role='student')
        team = StudentTeam.objects.create(
            name=f'Calendar team {self.sequence}', leader=leader,
            level=f'{year} {"PIT" if scope == "pit" else "Capstone"}',
            year_level=year, semester=self.semester,
        )
        values = dict(
            team=team, semester=self.semester, scope=scope,
            event_name='Prototype Showcase' if scope == 'pit' else '',
            defense_stage=self.stage if scope == 'capstone' else None,
            scheduled_date=self.day, start_time='08:00', room='Room 301',
        )
        values.update(kwargs)
        return DefenseSchedule.objects.create(**values)

    def feed(self, user):
        self.client.force_authenticate(user=user)
        response = self.client.get('/api/dashboards/schedule-planner/', {
            'start': self.day.isoformat(), 'end': self.day.isoformat(),
        })
        self.assertEqual(response.status_code, 200, response.data)
        return {item['session_id']: item for item in response.data['sessions']}

    def publish_grade(self, schedule, **kwargs):
        values = dict(
            team=schedule.team, schedule=schedule, semester=self.semester,
            scope=schedule.scope, defense_stage=schedule.defense_stage,
            panel_score=Decimal('85'), peer_score=Decimal('85'),
            adviser_score=Decimal('85'), panel_weight=80 if schedule.scope == 'pit' else 50,
            peer_weight=20, adviser_weight=0 if schedule.scope == 'pit' else 30,
            status=TeamGrade.STATUS_PUBLISHED,
        )
        values.update(kwargs)
        return TeamGrade.all_objects.create(**values)

    def test_history_preserves_assessed_archived_and_unconfirmed_states(self):
        past = self.schedule()
        assessed = self.schedule(status=DefenseSchedule.STATUS_DONE, start_time='09:00')
        completed = self.schedule(status=DefenseSchedule.STATUS_DONE, start_time='10:00')
        self.publish_grade(completed)
        archived = self.schedule(status=DefenseSchedule.STATUS_ARCHIVED, start_time='11:00')
        cancelled = self.schedule(status=DefenseSchedule.STATUS_CANCELLED, start_time='12:00')
        self.schedule(scheduled_date=self.day - timedelta(days=1))
        other_semester = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        other_term = self.schedule(semester=other_semester, start_time='13:00')

        sessions = self.feed(self.admin)
        self.assertEqual(len(sessions), 4)
        for schedule, state in ((past, 'scheduled'), (assessed, 'assessed'),
                                (completed, 'completed'), (archived, 'archived')):
            self.assertEqual(sessions[str(schedule.session_id)]['status_counts'], {state: 1})
        self.assertNotIn(str(cancelled.session_id), sessions)
        self.assertNotIn(str(other_term.session_id), sessions)
        past.refresh_from_db()
        self.assertEqual(past.status, DefenseSchedule.STATUS_SCHEDULED)

    def test_published_failed_and_revision_results_are_not_completed(self):
        for index, verdict in enumerate(('failed', 'approved_with_revisions', 'approved')):
            schedule = self.schedule(
                scope='capstone', year='4th Year', status=DefenseSchedule.STATUS_DONE,
                start_time=f'{8 + index:02d}:00',
            )
            self.publish_grade(schedule, verdict=verdict)
            session = self.feed(self.admin)[str(schedule.session_id)]
            self.assertEqual(session['status_counts'], {'completed' if verdict == 'approved' else 'assessed': 1})

    def test_mixed_session_keeps_years_and_completion_counts_separate(self):
        session_id = uuid4()
        self.schedule(session_id=session_id)
        self.schedule(session_id=session_id, year='2nd Year', status=DefenseSchedule.STATUS_DONE)
        completed = self.schedule(session_id=session_id, year='2nd Year', status=DefenseSchedule.STATUS_DONE)
        self.publish_grade(completed)
        summary = self.feed(self.lead)[str(session_id)]
        self.assertEqual(summary['year_levels'], ['1st Year', '2nd Year'])
        self.assertEqual(summary['team_count'], 3)
        self.assertEqual(summary['status_counts'], {'scheduled': 1, 'assessed': 1, 'completed': 1})
        self.assertTrue(summary['can_open'])

    def test_shared_occupancy_keeps_other_cohorts_read_only_and_venues_precise(self):
        own = self.schedule()
        other_year = self.schedule(year='2nd Year', start_time='09:00')
        capstone = self.schedule(scope='capstone', year='4th Year', start_time='13:00', room='Lab 2')
        session_id = uuid4()
        self.schedule(year='3rd Year', session_id=session_id, start_time='10:00')
        self.schedule(year='3rd Year', session_id=session_id, start_time='14:00', room='Lab 2')

        sessions = self.feed(self.lead)
        self.assertTrue(sessions[str(own.session_id)]['can_open'])
        for schedule in (other_year, capstone):
            summary = sessions[str(schedule.session_id)]
            self.assertFalse(summary['can_open'])
            self.assertEqual(summary['year_levels'], [schedule.team.year_level])
            self.assertNotIn('team_ids', summary)
            self.assertNotIn('team_name', summary)
            # Calendar visibility grants no access to the underlying defense.
            board = self.client.get('/api/defense/board/', {'scope': schedule.scope})
            self.assertEqual(board.status_code, 200, board.data)
            self.assertNotIn(schedule.pk, {item['id'] for item in board.data['schedules']})
            detail = self.client.patch(f'/api/defense/board/{schedule.pk}/', {'status': 'done'}, format='json')
            self.assertEqual(detail.status_code, 404)
        venues = sessions[str(session_id)]['venues']
        self.assertEqual([item['room'] for item in venues], ['Lab 2', 'Room 301'])
        self.assertEqual(venues[0]['time_blocks'][0]['start'], '2026-10-14T14:00')
        self.assertEqual(venues[1]['time_blocks'][0]['end'], '2026-10-14T11:00')
        self.assertTrue(all(item['can_open'] for item in self.feed(self.admin).values()))
