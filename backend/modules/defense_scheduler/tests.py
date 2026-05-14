from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense_stages.models import DefenseStage
from rubric_engine.models import Rubric, RubricCriterion
from student_teams.models import StudentTeam, TeamMembership
from .models import DefenseSchedule, SchedulePanelist


User = get_user_model()


class DefenseSchedulerApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin-user',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.panelist = User.objects.create_user(
            username='panel-1',
            password='pass12345',
            role='faculty',
            first_name='Grace',
            last_name='Hopper',
            is_panelist=True,
        )
        self.second_panelist = User.objects.create_user(
            username='panel-2',
            password='pass12345',
            role='faculty',
            first_name='Alan',
            last_name='Turing',
            is_panelist=True,
        )
        self.adviser = User.objects.create_user(
            username='adviser-1',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        self.student = User.objects.create_user(
            username='2024-0001',
            password='pass12345',
            role='student',
            first_name='Juan',
            last_name='Dela Cruz',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.SECOND,
            is_active=True,
        )
        self.stage = DefenseStage.objects.get(label='Project Proposal')
        self.team = StudentTeam.objects.create(
            name='Team VaultSync',
            project_title='Cloud File Sync',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.adviser,
            ready_for_stage=self.stage.label,
        )
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True, order=0)
        self.rubric = Rubric.objects.create(
            name='Project Proposal Panel Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        RubricCriterion.objects.create(
            rubric=self.rubric,
            name='Technical Feasibility',
            scale=Rubric.SCALE_10,
            max_score=10,
            display_order=0,
        )
        self.client.force_authenticate(user=self.admin)

    def schedule_payload(self, **overrides):
        payload = {
            'scope': DefenseSchedule.SCOPE_CAPSTONE,
            'semester_id': self.semester.id,
            'defense_stage_id': self.stage.id,
            'rubric_id': self.rubric.id,
            'scheduled_date': '2026-05-15',
            'start_time': '08:00',
            'slot_duration': 60,
            'room': 'Room 301',
            'panelist_ids': [self.panelist.id, self.second_panelist.id],
        }
        payload.update(overrides)
        return payload

    def test_list_returns_scheduler_options(self):
        response = self.client.get('/api/defense-schedules/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_semester']['id'], self.semester.id)
        self.assertEqual(response.data['counts']['all'], 0)
        self.assertEqual(response.data['panelists'][0]['username'], 'panel-1')
        self.assertEqual(response.data['rubrics'][0]['id'], self.rubric.id)

    def test_generate_plan_returns_ready_capstone_teams(self):
        response = self.client.post(
            '/api/defense-schedules/generate-plan/',
            self.schedule_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['slot_count'], 1)
        self.assertEqual(response.data['slots'][0]['team_id'], self.team.id)
        self.assertEqual(str(response.data['slots'][0]['start_time']), '08:00:00')

    def test_confirm_plan_creates_schedules_with_panelists(self):
        response = self.client.post(
            '/api/defense-schedules/confirm-plan/',
            {
                **self.schedule_payload(),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['created_count'], 1)
        self.assertEqual(DefenseSchedule.objects.count(), 1)
        self.assertEqual(SchedulePanelist.objects.count(), 2)
        self.assertEqual(DefenseSchedule.objects.get().team, self.team)

    def test_manual_schedule_create_rejects_duplicate_active_context(self):
        first = self.client.post(
            '/api/defense-schedules/',
            {**self.schedule_payload(), 'team_id': self.team.id},
            format='json',
        )
        duplicate = self.client.post(
            '/api/defense-schedules/',
            {
                **self.schedule_payload(start_time='09:00'),
                'team_id': self.team.id,
            },
            format='json',
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(duplicate.status_code, 400)
        self.assertIn('team_id', duplicate.data)

    def test_schedule_status_can_be_cancelled(self):
        create = self.client.post(
            '/api/defense-schedules/',
            {**self.schedule_payload(), 'team_id': self.team.id},
            format='json',
        )
        schedule_id = create.data['schedule']['id']

        response = self.client.patch(
            f'/api/defense-schedules/{schedule_id}/',
            {'status': DefenseSchedule.STATUS_CANCELLED},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['schedule']['status'], DefenseSchedule.STATUS_CANCELLED)

    def test_admin_dashboard_counts_scheduled_defenses_and_phase_nine(self):
        self.client.post(
            '/api/defense-schedules/',
            {**self.schedule_payload(), 'team_id': self.team.id},
            format='json',
        )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['upcoming_defenses'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)
