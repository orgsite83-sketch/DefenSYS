from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageGradingConfig
from grading.rubrics.models import Rubric, RubricCriterion
from student_teams.models import StudentTeam, TeamMembership
from student_teams.services import mark_stage_ready
from decimal import Decimal

from grading.grades.models import PanelistCriterionScore, PanelistGradeSubmission, TeamGrade
from student_teams.models import TeamStageProgress

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
        mark_stage_ready(self.team, self.stage, user=self.adviser)
        self.rubric = Rubric.objects.create(
            name='Project Proposal Panel Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        self.adviser_rubric = Rubric.objects.create(
            name='Project Proposal Adviser Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_ADVISER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        self.peer_rubric = Rubric.objects.create(
            name='Project Proposal Peer Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=self.stage,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        StageGradingConfig.objects.create(
            defense_stage=self.stage,
            semester=self.semester,
            panel_rubric=self.rubric,
            adviser_rubric=self.adviser_rubric,
            peer_rubric=self.peer_rubric,
        )
        self.criterion = RubricCriterion.objects.create(
            rubric=self.rubric,
            name='Technical Feasibility',
            scale=Rubric.SCALE_10,
            max_score=10,
            display_order=0,
        )
        self.second_criterion = RubricCriterion.objects.create(
            rubric=self.rubric,
            name='Presentation and Defense',
            scale=Rubric.SCALE_10,
            max_score=10,
            display_order=1,
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

    def create_ready_team(self, name='Team MirrorSync', username='2024-0002'):
        student = User.objects.create_user(
            username=username,
            password='pass12345',
            role='student',
        )
        team = StudentTeam.objects.create(
            name=name,
            project_title='Backup Portal',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=student,
            adviser=self.adviser,
            ready_for_stage=self.stage.label,
        )
        TeamMembership.objects.create(team=team, student=student, is_leader=True, order=0)
        mark_stage_ready(team, self.stage, user=self.adviser)
        return team

    def criteria_scores(self, first_score, second_score=None, **first_overrides):
        second_score = first_score if second_score is None else second_score
        first = {
            'criterion_id': self.criterion.id,
            'score': first_score,
        }
        first.update(first_overrides)
        return [
            first,
            {
                'criterion_id': self.second_criterion.id,
                'score': second_score,
            },
        ]

    def create_scheduled_defense(self):
        schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            rubric=self.rubric,
            scheduled_date='2026-05-15',
            start_time='08:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.panelist, order=0)
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.second_panelist, order=1)
        return schedule

    def test_list_returns_scheduler_options(self):
        response = self.client.get('/api/defense/schedules/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_semester']['id'], self.semester.id)
        self.assertEqual(response.data['counts']['all'], 0)
        self.assertEqual(response.data['panelists'][0]['username'], 'panel-1')
        rubric_ids = {item['id'] for item in response.data['rubrics']}
        self.assertIn(self.rubric.id, rubric_ids)
        self.assertIn(self.adviser_rubric.id, rubric_ids)
        self.assertIn(self.peer_rubric.id, rubric_ids)

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

    def test_confirm_plan_requires_complete_stage_rubric_config(self):
        config = StageGradingConfig.objects.get(defense_stage=self.stage, semester=self.semester)
        config.adviser_rubric = None
        config.save(update_fields=['adviser_rubric', 'updated_at'])

        response = self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.schedule_payload(),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('rubric_id', response.data)
        self.assertIn('adviser', str(response.data['rubric_id']))

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
        progress = TeamStageProgress.objects.get(team=self.team, defense_stage=self.stage)
        self.assertEqual(progress.status, TeamStageProgress.STATUS_SCHEDULED)

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

    def test_manual_schedule_create_rejects_same_room_overlap(self):
        other_team = self.create_ready_team()
        first = self.client.post(
            '/api/defense/schedules/',
            {
                **self.schedule_payload(panelist_ids=[self.panelist.id]),
                'team_id': self.team.id,
            },
            format='json',
        )
        overlapping = self.client.post(
            '/api/defense/schedules/',
            {
                **self.schedule_payload(start_time='08:30', panelist_ids=[self.second_panelist.id]),
                'team_id': other_team.id,
            },
            format='json',
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(overlapping.status_code, 400)
        self.assertIn('start_time', overlapping.data)

    def test_manual_schedule_create_allows_adjacent_same_room_slot(self):
        other_team = self.create_ready_team()
        first = self.client.post(
            '/api/defense/schedules/',
            {
                **self.schedule_payload(panelist_ids=[self.panelist.id]),
                'team_id': self.team.id,
            },
            format='json',
        )
        adjacent = self.client.post(
            '/api/defense/schedules/',
            {
                **self.schedule_payload(start_time='09:00', panelist_ids=[self.second_panelist.id]),
                'team_id': other_team.id,
            },
            format='json',
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(adjacent.status_code, 201)

    def test_manual_schedule_create_rejects_panelist_overlap(self):
        other_team = self.create_ready_team()
        first = self.client.post(
            '/api/defense/schedules/',
            {
                **self.schedule_payload(panelist_ids=[self.panelist.id]),
                'team_id': self.team.id,
            },
            format='json',
        )
        overlapping = self.client.post(
            '/api/defense/schedules/',
            {
                **self.schedule_payload(start_time='08:30', room='Room 302', panelist_ids=[self.panelist.id]),
                'team_id': other_team.id,
            },
            format='json',
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(overlapping.status_code, 400)
        self.assertIn('panelist_ids', overlapping.data)

    def test_confirm_plan_rejects_existing_room_overlap(self):
        other_team = self.create_ready_team()
        existing = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=other_team,
            defense_stage=self.stage,
            rubric=self.rubric,
            scheduled_date='2026-05-15',
            start_time='08:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=existing, panelist=self.second_panelist)

        response = self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.schedule_payload(start_time='08:30', panelist_ids=[self.panelist.id]),
                'slots': [{'team_id': self.team.id}],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('slots', response.data)

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
            'criteria_scores': self.criteria_scores(8),
        }

        self.client.force_authenticate(user=self.panelist)
        response_a = self.client.post(submit_url, payload_base, format='json')
        self.assertEqual(response_a.status_code, 201)

        self.client.force_authenticate(user=self.second_panelist)
        response_b = self.client.post(
            submit_url,
            {
                **payload_base,
                'criteria_scores': self.criteria_scores(6),
            },
            format='json',
        )
        self.assertEqual(response_b.status_code, 201)

        grade = TeamGrade.objects.get(team=self.team, schedule=schedule)
        self.assertEqual(grade.defense_stage_id, self.stage.id)
        self.assertEqual(grade.panel_score, Decimal('70.00'))

        self.client.force_authenticate(user=self.panelist)
        response_a2 = self.client.post(
            submit_url,
            {
                **payload_base,
                'criteria_scores': self.criteria_scores(9),
            },
            format='json',
        )
        self.assertEqual(response_a2.status_code, 201)
        grade.refresh_from_db()
        self.assertEqual(grade.panel_score, Decimal('75.00'))

    def test_panelist_submission_uses_rubric_criterion_snapshots(self):
        schedule = self.create_scheduled_defense()
        self.client.force_authenticate(user=self.panelist)

        response = self.client.post(
            '/api/defense/schedules/submit-grades/',
            {
                'team_id': self.team.id,
                'schedule_id': schedule.id,
                'criteria_scores': self.criteria_scores(
                    8,
                    7,
                    name='Tampered Name',
                    max_score=999,
                ),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        submission = PanelistGradeSubmission.objects.get(panelist=self.panelist)
        criterion_scores = list(submission.criterion_scores.order_by('display_order'))
        self.assertEqual(len(criterion_scores), 2)
        self.assertEqual(criterion_scores[0].criterion_id, self.criterion.id)
        self.assertEqual(criterion_scores[0].criterion_name_snapshot, self.criterion.name)
        self.assertEqual(criterion_scores[0].max_score_snapshot, Decimal('10.00'))

        breakdown = submission.team_grade.breakdowns.get(criterion_name=self.criterion.name)
        self.assertEqual(breakdown.max_score, Decimal('10.00'))

    def test_panelist_submission_rejects_missing_extra_and_duplicate_criteria(self):
        schedule = self.create_scheduled_defense()
        self.client.force_authenticate(user=self.panelist)
        submit_url = '/api/defense/schedules/submit-grades/'
        payload_base = {
            'team_id': self.team.id,
            'schedule_id': schedule.id,
        }

        missing = self.client.post(
            submit_url,
            {
                **payload_base,
                'criteria_scores': [{'criterion_id': self.criterion.id, 'score': 8}],
            },
            format='json',
        )
        extra = self.client.post(
            submit_url,
            {
                **payload_base,
                'criteria_scores': [
                    *self.criteria_scores(8),
                    {'criterion_id': 999999, 'score': 1},
                ],
            },
            format='json',
        )
        duplicate = self.client.post(
            submit_url,
            {
                **payload_base,
                'criteria_scores': [
                    {'criterion_id': self.criterion.id, 'score': 8},
                    {'criterion_id': self.criterion.id, 'score': 9},
                ],
            },
            format='json',
        )

        self.assertEqual(missing.status_code, 400)
        self.assertEqual(extra.status_code, 400)
        self.assertEqual(duplicate.status_code, 400)

    def test_panelist_resubmission_replaces_only_that_panelist(self):
        schedule = self.create_scheduled_defense()
        submit_url = '/api/defense/schedules/submit-grades/'
        payload_base = {
            'team_id': self.team.id,
            'schedule_id': schedule.id,
        }

        self.client.force_authenticate(user=self.panelist)
        self.client.post(
            submit_url,
            {**payload_base, 'criteria_scores': self.criteria_scores(8)},
            format='json',
        )
        self.client.force_authenticate(user=self.second_panelist)
        self.client.post(
            submit_url,
            {**payload_base, 'criteria_scores': self.criteria_scores(6)},
            format='json',
        )
        self.client.force_authenticate(user=self.panelist)
        response = self.client.post(
            submit_url,
            {**payload_base, 'criteria_scores': self.criteria_scores(9)},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        grade = TeamGrade.objects.get(team=self.team, schedule=schedule)
        self.assertEqual(PanelistGradeSubmission.objects.filter(team_grade=grade).count(), 2)
        self.assertEqual(PanelistCriterionScore.objects.filter(submission__team_grade=grade).count(), 4)
        self.assertEqual(grade.panel_score, Decimal('75.00'))

    def test_guest_panelist_submission_uses_same_criterion_validation(self):
        schedule = self.create_scheduled_defense()
        token = AccessToken()
        token['guest_panelist'] = True
        token['guest_code_id'] = 123
        token['guest_code'] = 'DEF-123'
        token['guest_name'] = 'Guest Panelist'
        token['defense_schedule_id'] = schedule.id
        token['team_id'] = self.team.id

        self.client.force_authenticate(user=None)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        response = self.client.post(
            '/api/defense/schedules/guest-submit-grades/',
            {
                'team_id': self.team.id,
                'schedule_id': schedule.id,
                'criteria_scores': self.criteria_scores(8),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        submission = PanelistGradeSubmission.objects.get(guest_code_id='123')
        self.assertEqual(submission.criterion_scores.count(), 2)

    def test_panelist_assignments_include_rubric_criterion_ids(self):
        self.create_scheduled_defense()
        self.client.force_authenticate(user=self.panelist)

        response = self.client.get('/api/defense/schedules/panelist-assignments/')

        self.assertEqual(response.status_code, 200)
        criteria = response.data['teams'][0]['panel_rubric']['criteria']
        self.assertEqual(criteria[0]['id'], self.criterion.id)

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
                'criteria_scores': self.criteria_scores(8),
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
        self.assertEqual(len(result['criteria']), 2)

    def test_panelist_results_forbidden_for_student(self):
        self.client.force_authenticate(user=self.student)
        response = self.client.get('/api/defense/schedules/panelist-results/')
        self.assertEqual(response.status_code, 403)

    def test_schedule_list_is_scoped_by_requesting_role(self):
        schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            rubric=self.rubric,
            scheduled_date='2026-05-15',
            start_time='08:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.panelist)
        other_adviser = User.objects.create_user(
            username='adviser-2',
            password='pass12345',
            role='faculty',
            is_adviser=True,
        )
        other_student = User.objects.create_user(
            username='2024-0009',
            password='pass12345',
            role='student',
        )
        other_team = StudentTeam.objects.create(
            name='Team Other',
            project_title='Other Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=other_student,
            adviser=other_adviser,
        )
        TeamMembership.objects.create(team=other_team, student=other_student, is_leader=True)
        other_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=other_team,
            defense_stage=self.stage,
            rubric=self.rubric,
            scheduled_date='2026-05-15',
            start_time='10:00',
            slot_duration=60,
            room='Room 302',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=other_schedule, panelist=self.second_panelist)

        def visible_ids(user):
            self.client.force_authenticate(user=user)
            response = self.client.get('/api/defense/schedules/')
            self.assertEqual(response.status_code, 200)
            return {item['id'] for item in response.data['schedules']}

        uploader = User.objects.create_user(
            username='uploader',
            password='pass12345',
            role='faculty',
            is_uploader=True,
        )
        plain_faculty = User.objects.create_user(
            username='plain-faculty',
            password='pass12345',
            role='faculty',
        )

        self.assertEqual(visible_ids(self.admin), {schedule.id, other_schedule.id})
        self.assertEqual(visible_ids(self.adviser), {schedule.id})
        self.assertEqual(visible_ids(self.student), {schedule.id})
        self.assertEqual(visible_ids(self.panelist), {schedule.id})
        self.assertEqual(visible_ids(uploader), {schedule.id, other_schedule.id})
        self.assertEqual(visible_ids(plain_faculty), set())


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
        self.assertEqual(grade.pit_event_config_id, config.id)
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

    def test_pit_event_config_save_creates_or_updates_config(self):
        payload = {
            'event_name': 'New PIT Expo',
            'semester_id': self.semester.id,
            'panel_rubric_id': self.panel_rubric.id,
            'peer_rubric_id': self.peer_rubric.id,
            'panel_weight': 70,
            'peer_weight': 30,
            'vault_file_template': 'test-template-{project}'
        }
        response = self.client.post(
            '/api/defense/schedules/pit-event-config/',
            payload,
            format='json'
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['config']['panel_weight'], 70)
        self.assertEqual(response.data['config']['peer_weight'], 30)
        self.assertEqual(response.data['config']['vault_file_template'], 'test-template-{project}')
        
        # Verify db
        config = PitEventGradingConfig.objects.get(event_name='New PIT Expo', semester=self.semester)
        self.assertEqual(config.panel_weight, 70)
        self.assertEqual(config.vault_file_template, 'test-template-{project}')

        # Update post (update)
        payload['panel_weight'] = 80
        payload['peer_weight'] = 20
        payload['vault_file_template'] = 'updated-template-{project}'
        response = self.client.post(
            '/api/defense/schedules/pit-event-config/',
            payload,
            format='json'
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['config']['panel_weight'], 80)
        self.assertEqual(response.data['config']['vault_file_template'], 'updated-template-{project}')

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

    def test_pit_lead_schedule_list_is_limited_to_pit_year(self):
        pit_lead = User.objects.create_user(
            username='pit-lead',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        pit_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.semester,
            team=self.team,
            event_name='2nd Year PIT Expo',
            rubric=self.panel_rubric,
            scheduled_date='2026-05-20',
            start_time='09:00',
            slot_duration=60,
            room='Room 201',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        capstone_stage = DefenseStage.objects.get(label='Project Proposal')
        capstone_student = User.objects.create_user(
            username='capstone-student',
            password='pass12345',
            role='student',
        )
        capstone_team = StudentTeam.objects.create(
            name='Capstone Team',
            project_title='Capstone Project',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=capstone_student,
        )
        capstone_rubric = Rubric.objects.create(
            name='Capstone Rubric',
            scope=Rubric.SCOPE_CAPSTONE,
            semester=self.semester,
            defense_stage=capstone_stage,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        capstone_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=capstone_team,
            defense_stage=capstone_stage,
            rubric=capstone_rubric,
            scheduled_date='2026-05-21',
            start_time='10:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )

        self.client.force_authenticate(user=pit_lead)
        response = self.client.get('/api/defense/schedules/')

        self.assertEqual(response.status_code, 200)
        visible_ids = {item['id'] for item in response.data['schedules']}
        self.assertIn(pit_schedule.id, visible_ids)
        self.assertNotIn(capstone_schedule.id, visible_ids)

    def test_pit_lead_generate_plan_is_limited_to_assigned_year(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-generate',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        other_student = User.objects.create_user(
            username='pit-first-year-student',
            password='pass12345',
            role='student',
        )
        other_team = StudentTeam.objects.create(
            name='PIT Team First Year',
            project_title='First Year Project',
            level=StudentTeam.LEVEL_1_PIT,
            year_level='1st Year',
            semester=self.semester,
            leader=other_student,
        )
        TeamMembership.objects.create(team=other_team, student=other_student, is_leader=True)

        self.client.force_authenticate(user=pit_lead)
        response = self.client.post(
            '/api/defense/schedules/generate-plan/',
            self.pit_payload(),
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual({slot['team_id'] for slot in response.data['slots']}, {self.team.id})

    def test_pit_lead_cannot_schedule_team_outside_assigned_year(self):
        pit_lead = User.objects.create_user(
            username='pit-lead-write',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )
        other_student = User.objects.create_user(
            username='pit-first-year-write-student',
            password='pass12345',
            role='student',
        )
        other_team = StudentTeam.objects.create(
            name='PIT Team First Year Write',
            project_title='First Year Write Project',
            level=StudentTeam.LEVEL_1_PIT,
            year_level='1st Year',
            semester=self.semester,
            leader=other_student,
        )
        TeamMembership.objects.create(team=other_team, student=other_student, is_leader=True)

        self.client.force_authenticate(user=pit_lead)
        manual = self.client.post(
            '/api/defense/schedules/',
            {**self.pit_payload(), 'team_id': other_team.id},
            format='json',
        )
        confirm = self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.pit_payload(start_time='10:30', room='Room 202'),
                'slots': [{'team_id': other_team.id}],
            },
            format='json',
        )

        self.assertEqual(manual.status_code, 400)
        self.assertIn('team_id', manual.data)
        self.assertEqual(confirm.status_code, 400)
        self.assertIn('team_id', confirm.data)

    def _make_capstone_intake_for_third_year_pit(self):
        self.semester.label = Semester.SECOND
        self.semester.capstone_program_phase = Semester.PHASE_CAPSTONE_1
        self.semester.save(update_fields=['label', 'capstone_program_phase'])
        pit_lead = User.objects.create_user(
            username='pit-lead-third-year',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='3rd Year',
        )
        student = User.objects.create_user(
            username='pit-third-year-student',
            password='pass12345',
            role='student',
        )
        team = StudentTeam.objects.create(
            name='PIT Team Third Year',
            project_title='Third Year Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=student,
        )
        TeamMembership.objects.create(team=team, student=student, is_leader=True)
        return pit_lead, team

    def test_pit_lead_scheduler_options_are_audit_mode_in_capstone_intake(self):
        pit_lead, _team = self._make_capstone_intake_for_third_year_pit()

        self.client.force_authenticate(user=pit_lead)
        response = self.client.get('/api/defense/schedules/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['scheduler_mode'], DefenseSchedule.SCOPE_PIT)
        self.assertEqual(response.data['pit_operating_mode'], 'audit')
        self.assertFalse(response.data['can_schedule_pit'])
        self.assertFalse(response.data['can_schedule_capstone'])
        self.assertEqual(response.data['allowed_scopes'], [])
        self.assertEqual(response.data['defense_stages'], [])
        self.assertIn('Capstone intake term', response.data['operating_message'])

    def test_pit_lead_audit_mode_rejects_schedule_writes(self):
        pit_lead, team = self._make_capstone_intake_for_third_year_pit()

        self.client.force_authenticate(user=pit_lead)
        manual = self.client.post(
            '/api/defense/schedules/',
            {
                **self.pit_payload(event_name='3rd Year PIT Expo'),
                'team_id': team.id,
            },
            format='json',
        )
        generate = self.client.post(
            '/api/defense/schedules/generate-plan/',
            self.pit_payload(event_name='3rd Year PIT Expo', room='Room 202'),
            format='json',
        )
        confirm = self.client.post(
            '/api/defense/schedules/confirm-plan/',
            {
                **self.pit_payload(
                    event_name='3rd Year PIT Expo',
                    room='Room 203',
                    start_time='10:00',
                ),
                'slots': [{'team_id': team.id}],
            },
            format='json',
        )

        self.assertEqual(manual.status_code, 400)
        self.assertIn('scope', manual.data)
        self.assertEqual(generate.status_code, 400)
        self.assertIn('scope', generate.data)
        self.assertEqual(confirm.status_code, 400)
        self.assertIn('scope', confirm.data)

    def test_guest_panelist_token_remains_bound_to_single_schedule(self):
        schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.semester,
            team=self.team,
            event_name='2nd Year PIT Expo',
            rubric=self.panel_rubric,
            scheduled_date='2026-05-20',
            start_time='09:00',
            slot_duration=60,
            room='Room 201',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        other_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.semester,
            team=self.team,
            event_name='2nd Year PIT Demo',
            rubric=self.panel_rubric,
            scheduled_date='2026-05-21',
            start_time='10:00',
            slot_duration=60,
            room='Room 202',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        token = AccessToken()
        token['guest_panelist'] = True
        token['guest_code_id'] = 123
        token['guest_code'] = 'DEF-123'
        token['guest_name'] = 'Guest Panelist'
        token['defense_schedule_id'] = schedule.id
        token['team_id'] = self.team.id

        self.client.force_authenticate(user=None)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        assignments = self.client.get('/api/defense/schedules/guest-assignments/')
        blocked_submit = self.client.post(
            '/api/defense/schedules/guest-submit-grades/',
            {
                'team_id': self.team.id,
                'schedule_id': other_schedule.id,
                'criteria_scores': [{'name': 'Test', 'score': 8, 'max_score': 10}],
            },
            format='json',
        )

        self.assertEqual(assignments.status_code, 200)
        self.assertEqual(assignments.data['schedules_count'], 1)
        self.assertEqual(assignments.data['teams'][0]['schedule_id'], schedule.id)
        self.assertEqual(blocked_submit.status_code, 403)

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
                'criteria_scores': [{'criterion_id': 1, 'score': 8}],
            },
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_pit_suggested_filename_uses_config_template(self):
        config = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Expo',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=75,
            peer_weight=25,
            vault_file_template='{year}-{course}-{project}-{event}-{semester}'
        )

        from repository.audit.services import suggested_pit_file_name
        filename = suggested_pit_file_name(
            team=self.team,
            year_level='2nd Year',
            semester_label='1st Semester',
            event_name='2nd Year PIT Expo'
        )

        self.assertEqual(
            filename,
            '2ndYear-PIT201-IoTMonitor-2ndYearPITExpo-1stSemester.pdf'
        )

