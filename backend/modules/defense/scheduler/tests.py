from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage
from grading.rubrics.models import Rubric, RubricCriterion
from student_teams.models import StudentTeam, TeamMembership
from decimal import Decimal

from grading.grades.models import TeamGrade

from .models import DefenseSchedule, PitEventGradingConfig, SchedulePanelist


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
        response = self.client.get('/api/defense/schedules/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_semester']['id'], self.semester.id)
        self.assertEqual(response.data['counts']['all'], 0)
        self.assertEqual(response.data['panelists'][0]['username'], 'panel-1')
        self.assertEqual(response.data['rubrics'][0]['id'], self.rubric.id)

    def test_generate_plan_returns_ready_capstone_teams(self):
        response = self.client.post(
            '/api/defense/schedules/generate-plan/',
            self.schedule_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['slot_count'], 1)
        self.assertEqual(response.data['slots'][0]['team_id'], self.team.id)
        self.assertEqual(str(response.data['slots'][0]['start_time']), '08:00:00')

    def test_confirm_plan_creates_schedules_with_panelists(self):
        response = self.client.post(
            '/api/defense/schedules/confirm-plan/',
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
            '/api/defense/schedules/',
            {**self.schedule_payload(), 'team_id': self.team.id},
            format='json',
        )
        duplicate = self.client.post(
            '/api/defense/schedules/',
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
            '/api/defense/schedules/',
            {**self.schedule_payload(), 'team_id': self.team.id},
            format='json',
        )
        schedule_id = create.data['schedule']['id']

        response = self.client.patch(
            f'/api/defense/schedules/{schedule_id}/',
            {'status': DefenseSchedule.STATUS_CANCELLED},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['schedule']['status'], DefenseSchedule.STATUS_CANCELLED)

    def test_admin_dashboard_counts_scheduled_defenses_and_phase_nine(self):
        self.client.post(
            '/api/defense/schedules/',
            {**self.schedule_payload(), 'team_id': self.team.id},
            format='json',
        )

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['upcoming_defenses'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)

    def test_two_panelists_panel_score_is_mean_of_percentages(self):
        """
        panel_score = mean(panelist_i percentage).
        Panelist A: 8/10 = 80%, Panelist B: 6/10 = 60% -> 70.00.
        Re-submit from A: 9/10 = 90% -> mean(90%, 60%) = 75.00.
        """
        self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.schedule_payload(),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )
        schedule = DefenseSchedule.objects.get()
        submit_url = '/api/defense/schedules/submit-grades/'
        payload_base = {
            'team_id': self.team.id,
            'schedule_id': schedule.id,
            'criteria_scores': [
                {'name': 'Technical Feasibility', 'score': 8, 'max_score': 10},
            ],
        }

        self.client.force_authenticate(user=self.panelist)
        response_a = self.client.post(submit_url, payload_base, format='json')
        self.assertEqual(response_a.status_code, 201)

        self.client.force_authenticate(user=self.second_panelist)
        response_b = self.client.post(
            submit_url,
            {
                **payload_base,
                'criteria_scores': [
                    {'name': 'Technical Feasibility', 'score': 6, 'max_score': 10},
                ],
            },
            format='json',
        )
        self.assertEqual(response_b.status_code, 201)

        grade = TeamGrade.objects.get(team=self.team, schedule=schedule)
        self.assertEqual(grade.panel_score, Decimal('70.00'))

        self.client.force_authenticate(user=self.panelist)
        response_a2 = self.client.post(
            submit_url,
            {
                **payload_base,
                'criteria_scores': [
                    {'name': 'Technical Feasibility', 'score': 9, 'max_score': 10},
                ],
            },
            format='json',
        )
        self.assertEqual(response_a2.status_code, 201)
        grade.refresh_from_db()
        self.assertEqual(grade.panel_score, Decimal('75.00'))

    def test_panelist_results_lists_submitted_teams(self):
        self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.schedule_payload(),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )
        schedule = DefenseSchedule.objects.get()
        self.client.force_authenticate(user=self.panelist)
        submit = self.client.post(
            '/api/defense/schedules/submit-grades/',
            {
                'team_id': self.team.id,
                'schedule_id': schedule.id,
                'criteria_scores': [
                    {'name': 'Technical Feasibility', 'score': 8, 'max_score': 10},
                ],
            },
            format='json',
        )
        self.assertEqual(submit.status_code, 201)

        response = self.client.get('/api/defense/schedules/panelist-results/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['results']), 1)
        result = response.data['results'][0]
        self.assertEqual(result['teamName'], self.team.name)
        self.assertEqual(result['percentage'], 80.0)
        self.assertEqual(len(result['criteria']), 1)

    def test_panelist_results_forbidden_for_student(self):
        self.client.force_authenticate(user=self.student)
        response = self.client.get('/api/defense/schedules/panelist-results/')
        self.assertEqual(response.status_code, 403)


class PitEventGradingConfigTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='pit-admin',
            password='pass12345',
            role='admin',
            is_staff=True,
        )
        self.panelist = User.objects.create_user(
            username='pit-panel',
            password='pass12345',
            role='faculty',
            is_panelist=True,
        )
        self.student = User.objects.create_user(
            username='pit-student',
            password='pass12345',
            role='student',
        )
        self.school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(
            school_year=self.school_year,
            label=Semester.FIRST,
            is_active=True,
        )
        self.team = StudentTeam.objects.create(
            name='PIT Team Alpha',
            project_title='IoT Monitor',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.semester,
            leader=self.student,
        )
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True, order=0)
        self.panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        self.peer_rubric = Rubric.objects.create(
            name='PIT Peer Rubric',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        self.client.force_authenticate(user=self.admin)

    def pit_payload(self, **overrides):
        payload = {
            'scope': DefenseSchedule.SCOPE_PIT,
            'semester_id': self.semester.id,
            'event_name': '2nd Year PIT Expo',
            'rubric_id': self.panel_rubric.id,
            'peer_rubric_id': self.peer_rubric.id,
            'panel_weight': 75,
            'peer_weight': 25,
            'scheduled_date': '2026-05-20',
            'start_time': '09:00',
            'slot_duration': 60,
            'room': 'Room 201',
            'panelist_ids': [self.panelist.id],
        }
        payload.update(overrides)
        return payload

    def test_list_includes_peer_rubrics(self):
        response = self.client.get('/api/defense/schedules/')

        self.assertEqual(response.status_code, 200)
        peer_ids = [item['id'] for item in response.data['peer_rubrics']]
        self.assertIn(self.peer_rubric.id, peer_ids)

    def test_confirm_plan_upserts_pit_event_config_and_grade_weights(self):
        response = self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.pit_payload(),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        config = PitEventGradingConfig.objects.get()
        self.assertEqual(config.panel_weight, 75)
        self.assertEqual(config.peer_weight, 25)
        self.assertEqual(config.panel_rubric_id, self.panel_rubric.id)
        self.assertEqual(config.peer_rubric_id, self.peer_rubric.id)

        grade = TeamGrade.objects.get(team=self.team, scope=TeamGrade.SCOPE_PIT)
        self.assertEqual(grade.panel_weight, 75)
        self.assertEqual(grade.peer_weight, 25)
        self.assertEqual(grade.stage_label, '2nd Year PIT Expo')

    def test_pit_event_config_lookup_prefills_existing_event(self):
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Expo',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=60,
            peer_weight=40,
        )

        response = self.client.get(
            '/api/defense/schedules/pit-event-config/',
            {'event_name': '2nd Year PIT Expo', 'semester_id': self.semester.id},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['config']['panel_weight'], 60)
        self.assertEqual(response.data['config']['peer_rubric_id'], self.peer_rubric.id)

    def test_panelist_assignments_returns_pit_grade_weights_without_adviser(self):
        self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.pit_payload(),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )

        self.client.force_authenticate(user=self.panelist)
        response = self.client.get('/api/defense/schedules/panelist-assignments/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['schedules_count'], 1)
        team = response.data['teams'][0]
        self.assertEqual(team['scope'], DefenseSchedule.SCOPE_PIT)
        self.assertFalse(team['is_capstone'])
        self.assertEqual(team['grade_weights']['panel'], 75)
        self.assertEqual(team['grade_weights']['peer'], 25)
        self.assertNotIn('adviser', team['grade_weights'])
        self.assertEqual(team['panel_rubric']['id'], self.panel_rubric.id)

    def test_panelist_assignments_requires_authentication(self):
        self.client.force_authenticate(user=None)
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(response.status_code, 401)

    def test_panelist_assignments_forbidden_for_student(self):
        self.client.force_authenticate(user=self.student)
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(response.status_code, 403)

    def test_panelist_cannot_view_other_panelist_assignments(self):
        other_panelist = User.objects.create_user(
            username='panel-other',
            password='pass12345',
            role='faculty',
            is_panelist=True,
        )
        self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.pit_payload(),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )
        self.client.force_authenticate(user=self.panelist)
        response = self.client.get(
            '/api/defense/schedules/panelist-assignments/',
            {'panelist_id': other_panelist.id},
        )
        self.assertEqual(response.status_code, 403)

    def test_panelist_cannot_submit_grades_for_unassigned_team(self):
        other_team = StudentTeam.objects.create(
            name='Other Team',
            project_title='Other',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
        )
        self.client.force_authenticate(user=self.panelist)
        response = self.client.post(
            '/api/defense/schedules/submit-grades/',
            {
                'team_id': other_team.id,
                'criteria_scores': [{'name': 'Test', 'score': 8, 'max_score': 10}],
            },
            format='json',
        )
        self.assertEqual(response.status_code, 403)
