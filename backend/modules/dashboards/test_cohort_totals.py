"""Cohort totals remain independent of roster search and table filters."""
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam, TeamMembership
from user_management.academic_records.models import StudentAcademicRecord


class CohortTotalsTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.lead = User.objects.create_user(
            username='cohort-totals-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='3rd Year',
        )
        year = SchoolYear.objects.create(label='2026-2027')
        cls.active = Semester.objects.create(
            school_year=year, label=Semester.FIRST, is_active=True,
        )
        cls.history = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2025-2026'),
            label=Semester.FIRST,
        )
        cls.students = []
        for index, name in enumerate(('Gabriel', 'Valerie', 'Christopher')):
            student = User.objects.create_user(
                username=f'cohort-totals-{index}', role='student', first_name=name,
            )
            cls.students.append(student)
            StudentAcademicRecord.objects.create(
                student=student, semester=cls.active, year_level='3rd Year',
            )
        team = StudentTeam.objects.create(
            name='Cohort Totals Team', leader=cls.students[0],
            semester=cls.active, level=StudentTeam.LEVEL_3_PIT, year_level='3rd Year',
        )
        TeamMembership.objects.create(team=team, student=cls.students[0], is_leader=True)
        for student in cls.students[:2]:
            StudentAcademicRecord.objects.create(
                student=student, semester=cls.history, year_level='3rd Year',
            )
        # Neither another year nor an inactive account belongs in these totals.
        for username, year_level, is_active in (
            ('cohort-other-year', '2nd Year', True),
            ('cohort-inactive', '3rd Year', False),
        ):
            student = User.objects.create_user(
                username=username, role='student', first_name='Gabriel', is_active=is_active,
            )
            StudentAcademicRecord.objects.create(
                student=student, semester=cls.active, year_level=year_level,
            )

    def setUp(self):
        self.client.force_authenticate(self.lead)

    def test_search_status_and_empty_results_preserve_active_cohort_totals(self):
        expected_counts = {'all': 3, 'on_team': 1, 'unassigned': 2}
        for query, expected_names in (
            ({}, {'Gabriel', 'Valerie', 'Christopher'}),
            ({'search': 'ga'}, {'Gabriel'}),
            ({'search': 'no-match'}, set()),
            ({'team_status': 'on_team'}, {'Gabriel'}),
            ({'team_status': 'unassigned'}, {'Valerie', 'Christopher'}),
            ({'search': 'ga', 'team_status': 'unassigned'}, set()),
            ({'search': ''}, {'Gabriel', 'Valerie', 'Christopher'}),
        ):
            with self.subTest(query=query):
                response = self.client.get('/api/dashboards/pit-lead/cohort/', query)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.data['counts'], expected_counts)
                self.assertEqual({row['name'] for row in response.data['students']}, expected_names)

    def test_historical_totals_stay_with_selected_roster(self):
        for search, expected_rows in (('', 2), ('ga', 1), ('no-match', 0)):
            with self.subTest(search=search):
                response = self.client.get(
                    '/api/dashboards/pit-lead/cohort/', {'scope': 'history', 'search': search},
                )
                self.assertEqual(response.status_code, 200)
                self.assertEqual(len(response.data['students']), expected_rows)
                self.assertEqual(response.data['counts'], {'all': 2, 'on_team': 0, 'unassigned': 2})
                self.assertEqual(response.data['history_counts'], response.data['counts'])
