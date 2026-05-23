from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam, TeamMembership


User = get_user_model()


class DefenseBoardApiTests(APITestCase):
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
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
        )
        self.pit_student = User.objects.create_user(
            username='2025-0001',
            password='pass12345',
            role='student',
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
            ready_for_stage=self.stage.label,
        )
        TeamMembership.objects.create(team=self.capstone_team, student=self.student, is_leader=True)
        self.pit_team = StudentTeam.objects.create(
            name='Team Circuit',
            project_title='Circuit Trainer',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.first_semester,
            leader=self.pit_student,
        )
        TeamMembership.objects.create(team=self.pit_team, student=self.pit_student, is_leader=True)
        self.capstone_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.capstone_team,
            defense_stage=self.stage,
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
            status=DefenseSchedule.STATUS_DONE,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=self.panelist)
        SchedulePanelist.objects.create(schedule=self.pit_schedule, panelist=self.panelist)
        self.client.force_authenticate(user=self.admin)

    def test_board_lists_schedules_with_counts_and_stage_options(self):
        response = self.client.get('/api/defense/board/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 2)
        self.assertEqual(response.data['counts']['scheduled'], 1)
        self.assertEqual(response.data['counts']['done'], 1)
        self.assertIn('Project Proposal', response.data['stage_options'])
        self.assertIn('PIT Expo', response.data['stage_options'])

    def test_board_filters_by_stage_status_and_search(self):
        response = self.client.get(
            '/api/defense/board/',
            {'stage': 'Project Proposal', 'status': 'scheduled', 'search': 'Vault'},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['filtered'], 1)
        self.assertEqual(response.data['schedules'][0]['team_name'], 'Team VaultSync')

    def test_pit_lead_only_sees_assigned_year_pit_schedules(self):
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/defense/board/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(response.data['schedules'][0]['team_name'], 'Team Circuit')

    def test_board_can_update_status_and_delete_schedule(self):
        update = self.client.patch(
            f'/api/defense/board/{self.capstone_schedule.id}/',
            {'status': DefenseSchedule.STATUS_DONE},
            format='json',
        )
        delete = self.client.delete(f'/api/defense/board/{self.pit_schedule.id}/')

        self.assertEqual(update.status_code, 200)
        self.assertEqual(update.data['schedule']['status'], DefenseSchedule.STATUS_DONE)
        self.assertEqual(delete.status_code, 200)
        self.assertFalse(DefenseSchedule.objects.filter(pk=self.pit_schedule.id).exists())

    def test_admin_dashboard_reports_phase_ten(self):
        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['migration']['phase'], 15)
