from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense_scheduler.models import DefenseSchedule, SchedulePanelist
from defense_stages.models import DefenseStage
from rubric_engine.models import Rubric, RubricCriterion
from student_teams.models import StudentTeam, TeamMembership
from .models import GradeBreakdown, StudentPeerGrade, TeamGrade


User = get_user_model()


class GradeCenterApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.pit_lead = User.objects.create_user(
            username='pit-lead',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        self.panelist = User.objects.create_user(
            username='panel-1',
            password='pass12345',
            role='faculty',
            first_name='Grace',
            last_name='Hopper',
            is_panelist=True,
        )
        self.adviser = User.objects.create_user(
            username='adviser-1',
            password='pass12345',
            role='faculty',
            first_name='Ada',
            last_name='Lovelace',
            is_adviser=True,
        )
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
            first_name='Juan',
            last_name='Dela Cruz',
        )
        self.second_student = User.objects.create_user(
            username='2024-0002',
            password='pass12345',
            role='student',
            first_name='Maria',
            last_name='Santos',
        )
        self.pit_student = User.objects.create_user(
            username='2025-0001',
            password='pass12345',
            role='student',
            first_name='Pedro',
            last_name='Reyes',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        self.first_semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
        )
        self.stage = DefenseStage.objects.get(label='Project Proposal')
        self.capstone_team = StudentTeam.objects.create(
            name='Team VaultSync',
            project_title='Cloud File Sync',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.adviser,
            ready_for_stage=self.stage.label,
        )
        TeamMembership.objects.create(team=self.capstone_team, student=self.student, is_leader=True, order=0)
        TeamMembership.objects.create(team=self.capstone_team, student=self.second_student, order=1)
        self.pit_team = StudentTeam.objects.create(
            name='Team Circuit',
            project_title='Circuit Trainer',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.first_semester,
            leader=self.pit_student,
        )
        TeamMembership.objects.create(team=self.pit_team, student=self.pit_student, is_leader=True)
        self.panel_rubric = self._rubric(Rubric.EVAL_PANEL, 'Panel Rubric')
        self.adviser_rubric = self._rubric(Rubric.EVAL_ADVISER, 'Adviser Rubric')
        self.peer_rubric = self._rubric(Rubric.EVAL_PEER, 'Peer Rubric', max_score=5)
        self.capstone_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.capstone_team,
            defense_stage=self.stage,
            rubric=self.panel_rubric,
            scheduled_date='2026-05-15',
            start_time='08:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        self.pit_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.first_semester,
            team=self.pit_team,
            event_name='PIT Expo',
            scheduled_date='2026-05-16',
            start_time='09:00',
            slot_duration=45,
            room='Lab 2',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=self.panelist)
        SchedulePanelist.objects.create(schedule=self.pit_schedule, panelist=self.panelist)
        self.client.force_authenticate(user=self.admin)

    def _rubric(self, eval_type, name, max_score=10):
        rubric = Rubric.objects.create(
            name=name,
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=eval_type,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        RubricCriterion.objects.create(
            rubric=rubric,
            name='Technical Quality',
            scale=Rubric.SCALE_10 if max_score == 10 else Rubric.SCALE_5,
            max_score=max_score,
            display_order=0,
        )
        return rubric

    def _capstone_grade(self):
        self.client.get('/api/grade-center/')
        return TeamGrade.objects.get(team=self.capstone_team)

    def test_list_syncs_schedules_into_grade_rows(self):
        response = self.client.get('/api/grade-center/', {'scope': 'capstone'})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['filtered'], 1)
        self.assertEqual(response.data['grades'][0]['team_name'], 'Team VaultSync')
        self.assertEqual(response.data['grades'][0]['weights']['panel'], 50)
        self.assertEqual(TeamGrade.objects.count(), 2)

    def test_update_scores_calculates_status_and_final_grade(self):
        grade = self._capstone_grade()

        awaiting = self.client.patch(
            f'/api/grade-center/{grade.id}/',
            {'panel_score': '88.00', 'adviser_score': '90.00'},
            format='json',
        )
        complete = self.client.patch(
            f'/api/grade-center/{grade.id}/',
            {'peer_score': '86.00'},
            format='json',
        )

        self.assertEqual(awaiting.status_code, 200)
        self.assertEqual(awaiting.data['grade']['status'], TeamGrade.STATUS_AWAITING_PEERS)
        self.assertIsNone(awaiting.data['grade']['final_grade'])
        self.assertEqual(complete.status_code, 200)
        self.assertEqual(complete.data['grade']['status'], TeamGrade.STATUS_PENDING)
        self.assertEqual(complete.data['grade']['final_grade'], '88.20')

    @override_settings(ENABLE_PROTOTYPE_TOOLS=True)
    def test_demo_fill_publishes_capstone_grades_with_breakdowns(self):
        response = self.client.post('/api/grade-center/demo-fill/')

        grade = TeamGrade.objects.get(team=self.capstone_team)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['filled_count'], 1)
        self.assertEqual(grade.status, TeamGrade.STATUS_PUBLISHED)
        self.assertIsNotNone(grade.final_grade)
        self.assertGreaterEqual(GradeBreakdown.objects.filter(team_grade=grade).count(), 3)
        self.assertEqual(StudentPeerGrade.objects.filter(team_grade=grade).count(), 2)

    def test_publish_sets_team_result_and_schedule_done(self):
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grade-center/{grade.id}/',
            {'panel_score': '70.00', 'adviser_score': '70.00', 'peer_score': '70.00'},
            format='json',
        )

        response = self.client.post(f'/api/grade-center/{grade.id}/publish/')
        self.capstone_team.refresh_from_db()
        self.capstone_schedule.refresh_from_db()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['grade']['status'], TeamGrade.STATUS_PUBLISHED)
        self.assertEqual(self.capstone_team.status, StudentTeam.STATUS_FAILED)
        self.assertEqual(self.capstone_schedule.status, DefenseSchedule.STATUS_DONE)

    def test_pit_lead_scope_only_returns_assigned_pit_year(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/grade-center/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(response.data['grades'][0]['team_name'], 'Team Circuit')

    def test_admin_dashboard_counts_grades_and_reports_phase_eleven(self):
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grade-center/{grade.id}/',
            {'panel_score': '88.00', 'adviser_score': '90.00', 'peer_score': '87.00'},
            format='json',
        )
        self.client.post(f'/api/grade-center/{grade.id}/publish/')

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['published_grades'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)
