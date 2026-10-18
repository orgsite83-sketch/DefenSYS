"""Dashboard query budgets and readiness parity on the isolated test database."""
from time import perf_counter

from django.contrib.auth import get_user_model
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam, TeamMembership
from user_management.academic_records.models import StudentAcademicRecord


class DashboardReadPerformanceTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        user_model = get_user_model()
        cls.admin = user_model.objects.create_user(username='perf-admin', role='admin')
        cls.leader = user_model.objects.create_user(username='perf-student', role='student')
        cls.semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2045-2046'),
            label=Semester.FIRST, is_active=True,
        )
        DefenseStage.objects.all().delete()
        for index in range(3):
            DefenseStage.objects.create(
                label=f'Performance Stage {index}', code=f'perf-stage-{index}',
                display_order=index + 1, is_active=True, is_presentation_only=True,
            )

    def add_teams(self, count):
        offset = StudentTeam.objects.count()
        StudentTeam.objects.bulk_create([
            StudentTeam(
                name=f'Performance Team {offset + index}', leader=self.leader,
                semester=self.semester, level=StudentTeam.LEVEL_3_CAPSTONE,
                year_level='3rd Year',
            ) for index in range(count)
        ])

    def dashboard(self):
        self.client.force_authenticate(self.admin)
        with CaptureQueriesContext(connection) as queries:
            started = perf_counter()
            response = self.client.get('/api/dashboards/admin/')
            elapsed = perf_counter() - started
        self.assertEqual(response.status_code, 200)
        return response.data, len(queries), elapsed

    def test_unendorsed_teams_do_not_add_per_team_readiness_queries(self):
        self.add_teams(1)
        _, one_queries, _ = self.dashboard()
        self.add_teams(31)
        payload, cohort_queries, elapsed = self.dashboard()
        self.assertEqual(payload['stats']['total_teams'], 32)
        self.assertEqual(payload['stats']['ready_capstone_teams'], 0)
        self.assertEqual(payload['team_pipeline']['teams_without_adviser'], 32)
        print(f'Admin dashboard, 32 unendorsed teams / 3 stages: '
              f'{cohort_queries} queries, {elapsed:.3f}s (one team: {one_queries} queries)')
        self.assertLessEqual(cohort_queries, one_queries + 2)


class CohortReadPerformanceTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        user_model = get_user_model()
        cls.lead = user_model.objects.create_user(
            username='cohort-perf-lead', role='faculty', is_pit_lead=True, pit_lead_year='1st Year',
        )
        cls.semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2047-2048'),
            label=Semester.FIRST, is_active=True,
        )
        students = user_model.objects.bulk_create([
            user_model(username=f'cohort-perf-{i}', role='student') for i in range(256)
        ])
        StudentAcademicRecord.objects.bulk_create([
            StudentAcademicRecord(student=student, semester=cls.semester, year_level='1st Year', section='BSIT-1A')
            for student in students
        ])
        teams = StudentTeam.objects.bulk_create([
            StudentTeam(name=f'Cohort Performance {i}', semester=cls.semester,
                        leader=students[i * 4], level=StudentTeam.LEVEL_1_PIT,
                        year_level='1st Year', section='BSIT-1A') for i in range(64)
        ])
        TeamMembership.objects.bulk_create([
            TeamMembership(team=teams[i // 4], student=student, is_leader=i % 4 == 0)
            for i, student in enumerate(students)
        ])

    def test_256_student_cohort_has_bounded_membership_queries(self):
        self.client.force_authenticate(self.lead)
        with CaptureQueriesContext(connection) as queries:
            started = perf_counter()
            response = self.client.get('/api/dashboards/pit-lead/cohort/')
            elapsed = perf_counter() - started
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['on_team'], 256)
        self.assertEqual(len(response.data['students']), 256)
        self.assertTrue(all(row['term_label'] == self.semester.display_name for row in response.data['students']))
        print(f'Faculty cohort, 256 students / 64 teams: {len(queries)} queries, {elapsed:.3f}s')
        self.assertLessEqual(len(queries), 20)
