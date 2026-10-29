"""Scheduling filters use faculty identities from the team's actual PIT section."""
from django.contrib.auth import get_user_model
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from student_teams.models import StudentTeam
from user_management.models import SectionInstructorAssignment
from . import test_year_scope as fixtures
from .serializers import ScheduleTeamSerializer


class SchedulerTeamFilterOptionsTests(APITestCase):
    setUp = fixtures.PitYearIsolationTests.setUp
    rubric = fixtures.PitYearIsolationTests.rubric

    def assign(self, faculty, *, semester=None, year='1st Year', section='BSIT-1A', active=True):
        return SectionInstructorAssignment.objects.create(faculty=faculty,
            semester=semester or self.semester, year_level=year, section=section, is_active=active)

    def prepare(self):
        self.team = self.teams[0]
        self.team.section = 'BSIT-1A'
        self.team.save(update_fields=['section'])
        self.instructor = get_user_model().objects.create_user(username='pit-instructor', role='faculty',
            first_name='Maria', last_name='Santos')
        self.assign(self.instructor)

    def test_scheduler_returns_the_sole_active_instructor_and_omits_retired_assignment(self):
        self.prepare()
        other = get_user_model().objects.create_user(username='second-instructor', role='faculty',
            first_name='Ramon', last_name='Cruz')
        self.assign(other, active=False)
        self.client.force_authenticate(self.first)
        response = self.client.get('/api/defense/schedules/', {'workspace': 'operations', 'scope': 'pit'})
        self.assertEqual(response.status_code, 200, response.data)
        team = next(t for t in response.data['teams'] if t['id'] == self.team.pk)
        self.assertEqual(team['instructors'], [
            {'id': self.instructor.pk, 'name': 'Maria Santos'}])
        self.assertEqual(team['instructor_name'], 'Maria Santos')
        self.assertIsNone(team['adviser'])

    def test_other_term_year_section_and_inactive_assignments_do_not_leak(self):
        self.prepare()
        previous = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        for changes in ({'semester': previous}, {'year': '2nd Year'}, {'section': 'BSIT-1B'}, {'active': False}):
            user = get_user_model().objects.create_user(username=f'excluded-{len(SectionInstructorAssignment.objects.all())}',
                role='faculty')
            self.assign(user, **changes)
        inactive = get_user_model().objects.create_user(username='inactive-instructor', role='faculty', is_active=False)
        self.assign(inactive, section='BSIT-1C')
        data = ScheduleTeamSerializer(self.team).data
        self.assertEqual(data['instructors'], [{'id': self.instructor.pk, 'name': 'Maria Santos'}])
        self.assertEqual(data['instructor_name'], 'Maria Santos')
        self.teams[2].section = self.team.section
        # Deliberately malformed legacy data must still respect scope. Normal
        # model validation correctly rejects this third-year/first-year pairing.
        StudentTeam.objects.filter(pk=self.teams[2].pk).update(section=self.team.section)
        self.assertEqual(ScheduleTeamSerializer(self.teams[2]).data['instructors'], [])

    def test_list_batches_section_assignments_and_keeps_unassigned_teams_explicit(self):
        self.prepare()
        self.team.adviser = self.panelist
        self.team.save(update_fields=['adviser'])
        teams = [self.team, StudentTeam.objects.create(name='Another module', semester=self.semester,
            leader=self.team.leader, section=self.team.section, year_level=self.team.year_level, level=self.team.level),
            self.teams[1]]
        with CaptureQueriesContext(connection) as queries:
            data = ScheduleTeamSerializer(teams, many=True).data
        assignment_queries = [q for q in queries if 'user_management_sectioninstructorassignment' in q['sql'].lower()]
        self.assertEqual(len(assignment_queries), 1)
        self.assertEqual(data[0]['instructors'], data[1]['instructors'])
        self.assertEqual(data[2]['instructors'], [])
        self.assertIsNone(data[2]['instructor_name'])
        self.assertNotIn(self.panelist.pk, [person['id'] for person in data[0]['instructors']])

    def test_same_display_names_remain_distinct_instructor_options(self):
        self.prepare()
        same_name = get_user_model().objects.create_user(username='another-maria', role='faculty',
            first_name='Maria', last_name='Santos')
        self.assign(same_name, section='BSIT-1B')
        people = ScheduleTeamSerializer(self.team).data['instructors']
        self.assertEqual({p['id'] for p in people}, {self.instructor.pk})
        self.team.section = 'BSIT-1B'
        self.team.save(update_fields=['section'])
        people = ScheduleTeamSerializer(self.team).data['instructors']
        self.assertEqual({p['id'] for p in people}, {same_name.pk})
