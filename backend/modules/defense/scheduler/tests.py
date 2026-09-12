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

    def test_delete_schedule_reverts_stage_progress_to_ready(self):
        # Create a scheduled defense
        schedule = self.create_scheduled_defense()
        schedule.scheduled_date = '2099-05-15'
        schedule.save()
        progress = TeamStageProgress.objects.get(team=self.team, defense_stage=self.stage)
        # Update progress to scheduled since we just manually created schedule
        from student_teams.services import mark_stage_scheduled
        mark_stage_scheduled(self.team, self.stage)
        progress.refresh_from_db()
        self.assertEqual(progress.status, TeamStageProgress.STATUS_SCHEDULED)

        # Delete the schedule
        response = self.client.delete(f'/api/defense/schedules/{schedule.id}/')
        self.assertEqual(response.status_code, 200)

        # Verify progress reverted to ready
        progress.refresh_from_db()
        self.assertEqual(progress.status, TeamStageProgress.STATUS_READY)

    def test_delete_schedule_blocked_when_ongoing_or_completed(self):
        schedule = self.create_scheduled_defense()
        schedule.scheduled_date = '2020-01-01'
        schedule.save()
        response = self.client.delete(f'/api/defense/schedules/{schedule.id}/')
        self.assertEqual(response.status_code, 409)

        schedule.scheduled_date = '2099-05-15'
        schedule.status = DefenseSchedule.STATUS_DONE
        schedule.save()
        response = self.client.delete(f'/api/defense/schedules/{schedule.id}/')
        self.assertEqual(response.status_code, 409)

    def test_delete_schedule_blocked_when_has_grade_submissions(self):
        # Create a scheduled defense
        schedule = self.create_scheduled_defense()
        schedule.scheduled_date = '2099-05-15'
        schedule.save()
        
        # Create a grade submission for this schedule
        from grading.grades.models import TeamGrade, PanelistGradeSubmission
        grade = TeamGrade.objects.create(
            team=self.team,
            semester=self.semester,
            defense_stage=self.stage,
            schedule=schedule,
            scope=TeamGrade.SCOPE_CAPSTONE,
        )
        submission = PanelistGradeSubmission.objects.create(
            team_grade=grade,
            schedule=schedule,
            panelist=self.panelist,
        )
        
        # Verify deleting the schedule returns 409 Conflict
        response = self.client.delete(f'/api/defense/schedules/{schedule.id}/')
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'has_grade_data')
        self.assertIn('panelist grades already submitted', response.data['detail'])
        
        # Ensure schedule still exists
        self.assertTrue(DefenseSchedule.objects.filter(id=schedule.id).exists())

    def test_board_delete_schedule_blocked_when_has_grade_submissions(self):
        # Create a scheduled defense
        schedule = self.create_scheduled_defense()
        
        # Create a grade submission for this schedule
        from grading.grades.models import TeamGrade, PanelistGradeSubmission
        grade = TeamGrade.objects.create(
            team=self.team,
            semester=self.semester,
            defense_stage=self.stage,
            schedule=schedule,
            scope=TeamGrade.SCOPE_CAPSTONE,
        )
        submission = PanelistGradeSubmission.objects.create(
            team_grade=grade,
            schedule=schedule,
            panelist=self.panelist,
        )
        
        # Verify deleting the schedule via Board endpoint returns 409 Conflict
        response = self.client.delete(f'/api/defense/board/{schedule.id}/')
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'has_grade_data')
        self.assertIn('panelist grades already submitted', response.data['detail'])
        
        # Ensure schedule still exists
        self.assertTrue(DefenseSchedule.objects.filter(id=schedule.id).exists())

    def test_cancel_schedule_reverts_stage_progress_to_ready(self):
        # Create a scheduled defense
        schedule = self.create_scheduled_defense()
        progress = TeamStageProgress.objects.get(team=self.team, defense_stage=self.stage)
        from student_teams.services import mark_stage_scheduled
        mark_stage_scheduled(self.team, self.stage)
        progress.refresh_from_db()
        self.assertEqual(progress.status, TeamStageProgress.STATUS_SCHEDULED)

        # Cancel the schedule
        response = self.client.patch(
            f'/api/defense/schedules/{schedule.id}/',
            {'status': DefenseSchedule.STATUS_CANCELLED},
            format='json',
        )
        self.assertEqual(response.status_code, 200)

        # Verify progress reverted to ready
        progress.refresh_from_db()
        self.assertEqual(progress.status, TeamStageProgress.STATUS_READY)

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

    def test_manual_schedule_create_requires_scope(self):
        payload = {**self.schedule_payload(), 'team_id': self.team.id}
        payload.pop('scope')

        response = self.client.post(
            '/api/defense/schedules/',
            payload,
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('scope', response.data)
        self.assertEqual(DefenseSchedule.objects.count(), 0)

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

    def test_panelist_assignments_reflects_posted_status_after_grading(self):
        self.create_scheduled_defense()
        self.client.force_authenticate(user=self.panelist)

        res_before = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(res_before.status_code, 200)
        self.assertFalse(res_before.data['teams'][0]['is_posted'])

        schedule = DefenseSchedule.objects.get()
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

        res_after = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(res_after.status_code, 200)
        self.assertTrue(res_after.data['teams'][0]['is_posted'])
        self.assertEqual(len(res_after.data['teams'][0]['submissions']), 1)

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

    def test_submit_grades_before_scheduled_date_is_blocked(self):
        from django.utils import timezone
        import datetime
        tomorrow = timezone.localtime(timezone.now()).date() + datetime.timedelta(days=1)
        
        schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_CAPSTONE,
            semester=self.semester,
            team=self.team,
            defense_stage=self.stage,
            rubric=self.rubric,
            scheduled_date=tomorrow,
            start_time='08:00',
            slot_duration=60,
            room='Room 301',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.panelist, order=0)
        
        submit_url = '/api/defense/schedules/submit-grades/'
        payload = {
            'team_id': self.team.id,
            'schedule_id': schedule.id,
            'criteria_scores': self.criteria_scores(8),
        }
        
        self.client.force_authenticate(user=self.panelist)
        response = self.client.post(submit_url, payload, format='json')
        
        self.assertEqual(response.status_code, 400)
        self.assertIn('Grading is locked until the scheduled date', response.data['detail'])

    def test_documenter_validation_rules(self):
        from .serializers import display_name

        # 1. Create a valid documenter
        documenter = User.objects.create_user(
            username='doc-user',
            password='pass12345',
            role='faculty',
            first_name='Margaret',
            last_name='Hamilton',
            is_documenter=True,
        )

        # 2. Test successful creation with documenter
        payload = self.schedule_payload(documenter_id=documenter.id, team_id=self.team.id)
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['schedule']['documenter'], documenter.id)
        self.assertEqual(response.data['schedule']['documenter_name'], display_name(documenter))

        # Clean up schedule to restore team ready state
        schedule_id = response.data['schedule']['id']
        DefenseSchedule.objects.get(id=schedule_id).delete()

        # 3. Test validation error: documenter cannot be a student
        student_doc = User.objects.create_user(
            username='student-doc',
            password='pass12345',
            role='student',
            is_documenter=True,
        )
        payload = self.schedule_payload(documenter_id=student_doc.id, team_id=self.team.id)
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('documenter_id', response.data)

        # 4. Test auto-promotion: active faculty with is_documenter = False is auto-promoted upon assignment
        non_doc = User.objects.create_user(
            username='non-doc',
            password='pass12345',
            role='faculty',
            first_name='Evelyn',
            last_name='Boyd',
            is_documenter=False,
        )
        payload = self.schedule_payload(documenter_id=non_doc.id, team_id=self.team.id)
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        non_doc.refresh_from_db()
        self.assertTrue(non_doc.is_documenter)
        from user_management.models import FacultyRoleAssignment
        self.assertTrue(
            FacultyRoleAssignment.objects.filter(
                user=non_doc,
                role_key=FacultyRoleAssignment.ROLE_DOCUMENTER,
                action=FacultyRoleAssignment.ACTION_ASSIGNED,
            ).exists()
        )
        # Clean up schedule to restore team ready state
        schedule_id = response.data['schedule']['id']
        DefenseSchedule.objects.get(id=schedule_id).delete()

        # 5. Test validation error: documenter cannot be the team's adviser
        payload = self.schedule_payload(documenter_id=self.adviser.id, team_id=self.team.id)
        self.adviser.is_documenter = True
        self.adviser.save()
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('documenter_id', response.data)
        # Restore adviser
        self.adviser.is_documenter = False
        self.adviser.save()

        # 6. Test validation error: documenter cannot be a panelist
        payload = self.schedule_payload(documenter_id=self.panelist.id, team_id=self.team.id)
        self.panelist.is_documenter = True
        self.panelist.save()
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('documenter_id', response.data)
        # Restore panelist
        self.panelist.is_documenter = False
        self.panelist.save()

        # 7. Test validation error: documenter cannot be assigned on PIT schedules
        pit_panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric Temp',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        pit_peer_rubric = Rubric.objects.create(
            name='PIT Peer Rubric Temp',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Expo',
            panel_rubric=pit_panel_rubric,
            peer_rubric=pit_peer_rubric,
            panel_weight=75,
            peer_weight=25,
        )
        pit_student = User.objects.create_user(
            username='pit-std-1',
            password='pass12345',
            role='student',
        )
        pit_team = StudentTeam.objects.create(
            name='PIT Team Delta',
            project_title='PIT Project',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.semester,
            leader=pit_student,
        )
        TeamMembership.objects.create(team=pit_team, student=pit_student, is_leader=True, order=0)
        
        pit_payload = {
            'scope': DefenseSchedule.SCOPE_PIT,
            'semester_id': self.semester.id,
            'event_name': '2nd Year PIT Expo',
            'rubric_id': pit_panel_rubric.id,
            'peer_rubric_id': pit_peer_rubric.id,
            'panel_weight': 75,
            'peer_weight': 25,
            'scheduled_date': '2026-05-20',
            'start_time': '09:00',
            'slot_duration': 60,
            'room': 'Room 201',
            'panelist_ids': [self.panelist.id],
            'documenter_id': documenter.id,
            'team_id': pit_team.id,
        }
        response = self.client.post('/api/defense/schedules/', pit_payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('documenter_id', response.data)

    def test_schedule_panelist_chair_validation(self):
        from django.core.exceptions import ValidationError
        schedule = self.create_scheduled_defense()
        sp1 = SchedulePanelist.objects.get(schedule=schedule, panelist=self.panelist)
        sp2 = SchedulePanelist.objects.get(schedule=schedule, panelist=self.second_panelist)
        self.assertFalse(sp1.is_chair)
        self.assertFalse(sp2.is_chair)

        # Mark sp1 as chair
        sp1.is_chair = True
        sp1.save()

        # Attempt to mark sp2 as chair
        sp2.is_chair = True
        with self.assertRaises(ValidationError):
            sp2.save()

        # Ensure we can save sp1 again (updating other things or just saving) without validation error
        sp1.order = 5
        sp1.save()

    def test_schedule_panelist_chair_serializer(self):
        schedule = self.create_scheduled_defense()
        sp1 = SchedulePanelist.objects.get(schedule=schedule, panelist=self.panelist)
        sp1.is_chair = True
        sp1.save()

        response = self.client.get('/api/defense/schedules/')
        self.assertEqual(response.status_code, 200)
        schedules = response.data.get('schedules', [])
        match = next(s for s in schedules if s['id'] == schedule.id)
        panelists = match['panelists']
        self.assertTrue(any(p['is_chair'] is True for p in panelists))
        self.assertTrue(any(p['is_chair'] is False for p in panelists))

    def test_create_schedule_with_documenter(self):
        documenter = User.objects.create_user(
            username='doc-1',
            password='pass12345',
            role='faculty',
            is_documenter=True,
        )
        payload = self.schedule_payload(documenter_id=documenter.id, team_id=self.team.id)
        
        from notifications.models import Notification
        Notification.objects.all().delete()
        
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        schedule = DefenseSchedule.objects.get(pk=response.data['schedule']['id'])
        self.assertEqual(schedule.documenter_id, documenter.id)
        
        notifications = Notification.objects.filter(recipient=documenter)
        self.assertEqual(notifications.count(), 1)
        notif = notifications.first()
        self.assertEqual(notif.title, "Documenter Assignment")
        self.assertEqual(notif.message, "You have been assigned as documenter for Team VaultSync's Project Proposal defense on May 15, 2026 at 8:00 AM")

    def test_patch_schedule_status_and_documenter(self):
        schedule = self.create_scheduled_defense()
        documenter = User.objects.create_user(
            username='doc-2',
            password='pass12345',
            role='faculty',
            is_documenter=True,
        )
        
        from notifications.models import Notification
        Notification.objects.all().delete()
        
        response = self.client.patch(
            f'/api/defense/schedules/{schedule.id}/',
            {'documenter_id': documenter.id},
            format='json'
        )
        self.assertEqual(response.status_code, 200)
        schedule.refresh_from_db()
        self.assertEqual(schedule.documenter_id, documenter.id)
        
        notifications = Notification.objects.filter(recipient=documenter)
        self.assertEqual(notifications.count(), 1)
        
        response = self.client.patch(
            f'/api/defense/schedules/{schedule.id}/',
            {'documenter_id': None},
            format='json'
        )
        self.assertEqual(response.status_code, 200)
        schedule.refresh_from_db()
        self.assertIsNone(schedule.documenter_id)

    def test_patch_schedule_invalid_documenter(self):
        schedule = self.create_scheduled_defense()
        
        adviser_user = self.adviser
        response = self.client.patch(
            f'/api/defense/schedules/{schedule.id}/',
            {'documenter_id': adviser_user.id},
            format='json'
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('documenter_id', response.data)
        
        panelist_user = self.panelist
        response = self.client.patch(
            f'/api/defense/schedules/{schedule.id}/',
            {'documenter_id': panelist_user.id},
            format='json'
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('documenter_id', response.data)

    def test_auto_promote_faculty_to_panelist_on_schedule_create(self):
        non_panelist = User.objects.create_user(
            username='non-panelist-faculty',
            password='pass12345',
            role='faculty',
            first_name='Claude',
            last_name='Shannon',
            is_panelist=False,
        )
        payload = self.schedule_payload(
            team_id=self.team.id,
            panelist_ids=[non_panelist.id, self.second_panelist.id],
        )
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        non_panelist.refresh_from_db()
        self.assertTrue(non_panelist.is_panelist)
        from user_management.models import FacultyRoleAssignment
        self.assertTrue(
            FacultyRoleAssignment.objects.filter(
                user=non_panelist,
                role_key=FacultyRoleAssignment.ROLE_PANELIST,
                action=FacultyRoleAssignment.ACTION_ASSIGNED,
            ).exists()
        )

    def test_student_as_panelist_rejected(self):
        payload = self.schedule_payload(
            team_id=self.team.id,
            panelist_ids=[self.student.id, self.second_panelist.id],
        )
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('panelist_ids', response.data)

    def test_redefense_schedule_creation_allowed_when_verdict_for_redefense(self):
        from decimal import Decimal
        from grading.grades.models import TeamGrade, GradeAttemptHistory
        from grading.grades.services import GradeContextService
        from student_teams.services import mark_stage_ready, mark_stage_result

        # 1. Team is ready and scheduled for Attempt 1
        mark_stage_ready(self.team, self.stage, user=self.admin)
        schedule_1 = self.create_scheduled_defense()

        # 2. Complete Attempt 1 with verdict 'for_redefense'
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule_1)
        grade.panel_score = Decimal('65.00')
        grade.final_grade = Decimal('65.00')
        grade.verdict = TeamGrade.VERDICT_FOR_REDEFENSE
        grade.verdict_remarks = 'Needs rework'
        grade.save()
        schedule_1.status = DefenseSchedule.STATUS_DONE
        schedule_1.save()
        mark_stage_result(grade, user=self.admin)

        # 3. Schedule Attempt 2 (redefense)
        self.client.force_authenticate(user=self.admin)
        payload = self.schedule_payload(
            team_id=self.team.id,
            scheduled_date='2026-06-25',
            start_time='09:00:00',
            room='Room 302',
        )
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)

        # 4. Verify snapshot was created for Attempt 1 and grade reset for Attempt 2
        grade.refresh_from_db()
        self.assertEqual(grade.attempt_count, 2)
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)
        self.assertIsNone(grade.panel_score)
        self.assertEqual(grade.verdict, '')

        history = GradeAttemptHistory.objects.filter(team_grade=grade)
        self.assertEqual(history.count(), 1)
        self.assertEqual(history.first().attempt_number, 1)
        self.assertEqual(history.first().verdict, TeamGrade.VERDICT_FOR_REDEFENSE)

    def test_schedule_creation_blocked_when_already_passed(self):
        from decimal import Decimal
        from grading.grades.models import TeamGrade
        from grading.grades.services import GradeContextService
        from student_teams.services import mark_stage_ready, mark_stage_result

        # 1. Team is ready and scheduled for Attempt 1
        mark_stage_ready(self.team, self.stage, user=self.admin)
        schedule_1 = self.create_scheduled_defense()

        # 2. Complete Attempt 1 with verdict 'approved' (passed)
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule_1)
        grade.panel_score = Decimal('88.00')
        grade.final_grade = Decimal('88.00')
        grade.verdict = TeamGrade.VERDICT_APPROVED
        grade.save()
        schedule_1.status = DefenseSchedule.STATUS_DONE
        schedule_1.save()
        mark_stage_result(grade, user=self.admin)

        # 3. Attempting to schedule again should be rejected
        self.client.force_authenticate(user=self.admin)
        payload = self.schedule_payload(
            team_id=self.team.id,
            scheduled_date='2026-06-25',
            start_time='09:00:00',
            room='Room 302',
        )
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('already completed and passed this stage', str(response.data))

    def test_panelist_assignments_includes_is_chair_and_verdict(self):
        from decimal import Decimal
        from grading.grades.models import TeamGrade
        from grading.grades.services import GradeContextService
        from student_teams.services import mark_stage_ready

        mark_stage_ready(self.team, self.stage, user=self.admin)
        schedule = self.create_scheduled_defense()

        # Set panelist as chair and second_panelist as non-chair
        SchedulePanelist.objects.filter(schedule=schedule, panelist=self.panelist).update(is_chair=True)
        SchedulePanelist.objects.filter(schedule=schedule, panelist=self.second_panelist).update(is_chair=False)

        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        grade.panel_score = Decimal('85.00')
        grade.verdict = TeamGrade.VERDICT_APPROVED_WITH_REVISIONS
        grade.verdict_remarks = 'Fix manuscript chapter 3'
        grade.verdict_by = self.panelist
        grade.save()

        # 1. As panelist (Chair)
        self.client.force_authenticate(user=self.panelist)
        res1 = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(res1.status_code, 200)
        teams1 = res1.data['teams']
        self.assertEqual(len(teams1), 1)
        self.assertTrue(teams1[0]['is_chair'])
        self.assertEqual(teams1[0]['verdict'], TeamGrade.VERDICT_APPROVED_WITH_REVISIONS)
        self.assertEqual(teams1[0]['verdict_remarks'], 'Fix manuscript chapter 3')
        self.assertEqual(teams1[0]['attempt_count'], 1)

        # 2. As second_panelist (Member)
        self.client.force_authenticate(user=self.second_panelist)
        res2 = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(res2.status_code, 200)
        teams2 = res2.data['teams']
        self.assertEqual(len(teams2), 1)
        self.assertFalse(teams2[0]['is_chair'])
        self.assertEqual(teams2[0]['verdict'], TeamGrade.VERDICT_APPROVED_WITH_REVISIONS)

    def test_chair_can_submit_for_redefense_and_regular_panelist_blocked(self):
        from decimal import Decimal
        from grading.grades.models import TeamGrade, GradeAttemptHistory
        from grading.grades.services import GradeContextService
        from student_teams.services import mark_stage_ready, mark_stage_result

        mark_stage_ready(self.team, self.stage, user=self.admin)
        schedule = self.create_scheduled_defense()

        SchedulePanelist.objects.filter(schedule=schedule, panelist=self.panelist).update(is_chair=True)
        SchedulePanelist.objects.filter(schedule=schedule, panelist=self.second_panelist).update(is_chair=False)

        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        grade.panel_score = Decimal('60.00')
        grade.save()

        # Non-chair panelist tries to submit verdict -> 403
        self.client.force_authenticate(user=self.second_panelist)
        res_fail = self.client.patch(f'/api/defense/schedules/{schedule.id}/verdict/', {
            'verdict': 'for_redefense',
            'verdict_remarks': 'Needs substantial rework',
        }, format='json')
        self.assertEqual(res_fail.status_code, 403)

        # Chair submits verdict -> 200
        self.client.force_authenticate(user=self.panelist)
        res_ok = self.client.patch(f'/api/defense/schedules/{schedule.id}/verdict/', {
            'verdict': 'for_redefense',
            'verdict_remarks': 'Needs substantial rework on backend security',
        }, format='json')
        self.assertEqual(res_ok.status_code, 200)
        self.assertTrue(res_ok.data['success'])

        grade.refresh_from_db()
        self.assertEqual(grade.verdict, TeamGrade.VERDICT_FOR_REDEFENSE)
        self.assertEqual(grade.verdict_remarks, 'Needs substantial rework on backend security')
        self.assertEqual(grade.verdict_by, self.panelist)

    def test_schedule_creation_with_explicit_chair_panelist(self):
        from student_teams.services import mark_stage_ready
        mark_stage_ready(self.team, self.stage, user=self.admin)
        self.client.force_authenticate(user=self.admin)
        payload = self.schedule_payload(
            team_id=self.team.id,
            panelist_ids=[self.panelist.id, self.second_panelist.id],
            chair_panelist_id=self.second_panelist.id,
        )
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        schedule_id = response.data['schedule']['id']
        sp_first = SchedulePanelist.objects.get(schedule_id=schedule_id, panelist=self.panelist)
        sp_second = SchedulePanelist.objects.get(schedule_id=schedule_id, panelist=self.second_panelist)
        self.assertFalse(sp_first.is_chair)
        self.assertTrue(sp_second.is_chair)

    def test_schedule_creation_defaults_first_panelist_as_chair(self):
        from student_teams.services import mark_stage_ready
        mark_stage_ready(self.team, self.stage, user=self.admin)
        self.client.force_authenticate(user=self.admin)
        payload = self.schedule_payload(
            team_id=self.team.id,
            panelist_ids=[self.panelist.id, self.second_panelist.id],
        )
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)
        schedule_id = response.data['schedule']['id']
        sp_first = SchedulePanelist.objects.get(schedule_id=schedule_id, panelist=self.panelist)
        sp_second = SchedulePanelist.objects.get(schedule_id=schedule_id, panelist=self.second_panelist)
        self.assertTrue(sp_first.is_chair)
        self.assertFalse(sp_second.is_chair)

    def test_patch_schedule_updates_chair_panelist(self):
        from student_teams.services import mark_stage_ready
        mark_stage_ready(self.team, self.stage, user=self.admin)
        schedule = self.create_scheduled_defense()
        SchedulePanelist.objects.filter(schedule=schedule, panelist=self.panelist).update(is_chair=True)
        SchedulePanelist.objects.filter(schedule=schedule, panelist=self.second_panelist).update(is_chair=False)

        self.client.force_authenticate(user=self.admin)
        patch_res = self.client.patch(f'/api/defense/schedules/{schedule.id}/', {
            'chair_panelist_id': self.second_panelist.id,
        }, format='json')
        self.assertEqual(patch_res.status_code, 200)

        sp_first = SchedulePanelist.objects.get(schedule=schedule, panelist=self.panelist)
        sp_second = SchedulePanelist.objects.get(schedule=schedule, panelist=self.second_panelist)
        self.assertFalse(sp_first.is_chair)
        self.assertTrue(sp_second.is_chair)

    def test_patch_schedule_rejects_chair_not_in_schedule_panelists(self):
        other_faculty = User.objects.create_user(
            username='other_fac_user',
            password='pass12345',
            role='faculty',
        )
        schedule = self.create_scheduled_defense()
        self.client.force_authenticate(user=self.admin)
        patch_res = self.client.patch(f'/api/defense/schedules/{schedule.id}/', {
            'chair_panelist_id': other_faculty.id,
        }, format='json')
        self.assertEqual(patch_res.status_code, 400)
        self.assertIn('chair_panelist_id', patch_res.data)


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
            'archive_file_template': 'test-template-{project}'
        }
        response = self.client.post(
            '/api/defense/schedules/pit-event-config/',
            payload,
            format='json'
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['config']['panel_weight'], 70)
        self.assertEqual(response.data['config']['peer_weight'], 30)
        self.assertEqual(response.data['config']['archive_file_template'], 'test-template-{project}')
        
        # Verify db
        config = PitEventGradingConfig.objects.get(event_name='New PIT Expo', semester=self.semester)
        self.assertEqual(config.panel_weight, 70)
        self.assertEqual(config.archive_file_template, 'test-template-{project}')

        # Update post (update)
        payload['panel_weight'] = 80
        payload['peer_weight'] = 20
        payload['archive_file_template'] = 'updated-template-{project}'
        response = self.client.post(
            '/api/defense/schedules/pit-event-config/',
            payload,
            format='json'
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['config']['panel_weight'], 80)
        self.assertEqual(response.data['config']['archive_file_template'], 'updated-template-{project}')

    def test_pit_event_peer_grading_smart_default_and_toggle(self):
        # 1. Creation without explicit peer_grading_enabled defaults to True when rubric and weight > 0
        payload = {
            'event_name': 'Smart Default PIT Expo',
            'semester_id': self.semester.id,
            'panel_rubric_id': self.panel_rubric.id,
            'peer_rubric_id': self.peer_rubric.id,
            'panel_weight': 80,
            'peer_weight': 20,
        }
        res = self.client.post('/api/defense/schedules/pit-event-config/', payload, format='json')
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data['config']['peer_grading_enabled'])
        config = PitEventGradingConfig.objects.get(event_name='Smart Default PIT Expo', semester=self.semester)
        self.assertTrue(config.peer_grading_enabled)

        # 2. Explicitly setting peer_grading_enabled to False
        payload['peer_grading_enabled'] = False
        res2 = self.client.post('/api/defense/schedules/pit-event-config/', payload, format='json')
        self.assertEqual(res2.status_code, 200)
        self.assertFalse(res2.data['config']['peer_grading_enabled'])
        config.refresh_from_db()
        self.assertFalse(config.peer_grading_enabled)

        # 3. Explicitly setting peer_grading_enabled to True
        payload['peer_grading_enabled'] = True
        res3 = self.client.post('/api/defense/schedules/pit-event-config/', payload, format='json')
        self.assertEqual(res3.status_code, 200)
        self.assertTrue(res3.data['config']['peer_grading_enabled'])
        config.refresh_from_db()
        self.assertTrue(config.peer_grading_enabled)

        # 4. Setting peer_weight = 0 automatically disables peer_grading_enabled
        payload['panel_weight'] = 100
        payload['peer_weight'] = 0
        res4 = self.client.post('/api/defense/schedules/pit-event-config/', payload, format='json')
        self.assertEqual(res4.status_code, 200)
        self.assertFalse(res4.data['config']['peer_grading_enabled'])
        config.refresh_from_db()
        self.assertFalse(config.peer_grading_enabled)

        # 5. GET template defaults peer_grading_enabled to True
        res5 = self.client.get(
            '/api/defense/schedules/pit-event-config/',
            {'event_name': 'Brand New Unconfigured Event', 'semester_id': self.semester.id}
        )
        self.assertEqual(res5.status_code, 200)
        self.assertTrue(res5.data['config']['peer_grading_enabled'])

    def test_pit_lead_can_only_access_their_own_year_level_event_configs(self):
        # Create a 1st Year PIT configuration and a 2nd Year PIT configuration
        config_1st = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='1st Year PIT Expo',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=80,
            peer_weight=20,
        )
        config_2nd = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Expo',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=80,
            peer_weight=20,
        )

        # Create a PIT lead for 2nd Year
        pit_lead_2nd = User.objects.create_user(
            username='pit-lead-2nd-year-test',
            password='pass12345',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )

        self.client.force_authenticate(user=pit_lead_2nd)

        # GET configurations list - should only return 2nd Year configs
        response_list = self.client.get('/api/defense/schedules/pit-event-config/')
        self.assertEqual(response_list.status_code, 200)
        configs = response_list.data['configs']
        self.assertEqual(len(configs), 1)
        self.assertEqual(configs[0]['event_name'], '2nd Year PIT Expo')

        # GET lookup of 1st Year config - should be forbidden (403)
        response_lookup_1st = self.client.get(
            '/api/defense/schedules/pit-event-config/',
            {'event_name': '1st Year PIT Expo', 'semester_id': self.semester.id},
        )
        self.assertEqual(response_lookup_1st.status_code, 403)

        # GET lookup of 2nd Year config - should be allowed (200)
        response_lookup_2nd = self.client.get(
            '/api/defense/schedules/pit-event-config/',
            {'event_name': '2nd Year PIT Expo', 'semester_id': self.semester.id},
        )
        self.assertEqual(response_lookup_2nd.status_code, 200)

        # POST (save) 1st Year config - should be forbidden (403)
        response_post_1st = self.client.post(
            '/api/defense/schedules/pit-event-config/',
            {
                'event_name': '1st Year New Expo',
                'semester_id': self.semester.id,
                'panel_rubric_id': self.panel_rubric.id,
                'peer_rubric_id': self.peer_rubric.id,
                'panel_weight': 70,
                'peer_weight': 30,
            },
            format='json'
        )
        self.assertEqual(response_post_1st.status_code, 403)

        # DELETE 1st Year config - should be forbidden (403)
        response_delete_1st = self.client.delete(
            f'/api/defense/schedules/pit-event-config/?config_id={config_1st.id}'
        )
        self.assertEqual(response_delete_1st.status_code, 403)

        # DELETE 2nd Year config - should be allowed (200)
        response_delete_2nd = self.client.delete(
            f'/api/defense/schedules/pit-event-config/?config_id={config_2nd.id}'
        )
        self.assertEqual(response_delete_2nd.status_code, 200)

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
            archive_file_template='{year}-{course}-{project}-{event}-{semester}'
        )

        from repository.project_archive.services import suggested_pit_file_name
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

    def test_delete_pit_event_config(self):
        config = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Expo Delete',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=75,
            peer_weight=25,
        )
        response = self.client.delete(
            f'/api/defense/schedules/pit-event-config/?config_id={config.id}'
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(PitEventGradingConfig.objects.filter(id=config.id).exists())

    def test_scheduling_gated_by_pre_defense_deliverables(self):
        config = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Expo Gated',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=75,
            peer_weight=25,
        )
        from .models import PitEventDeliverable
        PitEventDeliverable.objects.create(
            pit_event_config=config,
            deliverable_id='PROPOSAL_PDF',
            label='Proposal PDF',
            deliverable_type=PitEventDeliverable.TYPE_PRE,
            required=True,
        )

        self.team.ready_for_stage = ''
        self.team.save()

        payload = self.pit_payload(event_name='2nd Year PIT Expo Gated', team_id=self.team.id)
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('team_id', response.data)

        confirm_payload = {
            **self.pit_payload(event_name='2nd Year PIT Expo Gated'),
            'slots': [{'team_id': self.team.id}],
        }
        response = self.client.post('/api/defense/schedules/confirm-plan/', confirm_payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('slots', response.data)

        self.team.ready_for_stage = '2nd Year PIT Expo Gated'
        self.team.save()

        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)

    def test_scheduling_allowed_if_no_pre_defense_deliverables(self):
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='2nd Year PIT Expo Open',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=75,
            peer_weight=25,
        )
        self.team.ready_for_stage = ''
        self.team.save()

        payload = self.pit_payload(event_name='2nd Year PIT Expo Open', team_id=self.team.id)
        response = self.client.post('/api/defense/schedules/', payload, format='json')
        self.assertEqual(response.status_code, 201)

    def test_retroactive_pit_weights_sync(self):
        from grading.grades.models import TeamGrade

        # Create another student and team for published grade
        student_other = User.objects.create_user(
            username='pit-student-other',
            password='pass12345',
            role='student',
        )
        team_published = StudentTeam.objects.create(
            name='PIT Team Beta',
            project_title='IoT Security',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.semester,
            leader=student_other,
        )

        # Create two TeamGrade records for this PIT event
        pending_grade = TeamGrade.objects.create(
            team=self.team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_PIT,
            stage_label='PIT Test Event',
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
            status=TeamGrade.STATUS_PENDING,
        )
        published_grade = TeamGrade.objects.create(
            team=team_published,
            semester=self.semester,
            scope=TeamGrade.SCOPE_PIT,
            stage_label='PIT Test Event',
            panel_score=85,
            peer_score=85,
            final_grade=85,
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
            status=TeamGrade.STATUS_PUBLISHED,
        )

        # Create the PitEventGradingConfig with different weights
        config = PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='PIT Test Event',
            panel_rubric=self.panel_rubric,
            peer_rubric=self.peer_rubric,
            panel_weight=70,
            peer_weight=30,
        )

        # Check pending grade has updated weights & is linked
        pending_grade.refresh_from_db()
        self.assertEqual(pending_grade.panel_weight, 70)
        self.assertEqual(pending_grade.peer_weight, 30)
        self.assertEqual(pending_grade.pit_event_config_id, config.id)

        # Check published grade has NOT updated weights and is not linked
        published_grade.refresh_from_db()
        self.assertEqual(published_grade.panel_weight, 80)
        self.assertEqual(published_grade.peer_weight, 20)
        self.assertIsNone(published_grade.pit_event_config_id)

        # Update the PitEventGradingConfig weights
        config.panel_weight = 60
        config.peer_weight = 40
        config.save()

        # Check pending grade weights are updated again
        pending_grade.refresh_from_db()
        self.assertEqual(pending_grade.panel_weight, 60)
        self.assertEqual(pending_grade.peer_weight, 40)

    def test_schedule_team_serializer_includes_instructor_name(self):
        from .serializers import ScheduleTeamSerializer
        from user_management.models import SectionInstructorAssignment
        
        instructor = User.objects.create_user(
            username='pit_inst_1',
            first_name='Maria',
            last_name='Santos',
            role='faculty'
        )
        SectionInstructorAssignment.objects.create(
            faculty=instructor,
            semester=self.semester,
            year_level='1st Year',
            section='BSIT-1A',
            is_active=True
        )
        team = StudentTeam.objects.create(
            name='Team Test PIT',
            level=StudentTeam.LEVEL_1_PIT,
            year_level='1st Year',
            section='BSIT-1A',
            semester=self.semester,
            leader=self.student,
            status=StudentTeam.STATUS_APPROVED
        )
        data = ScheduleTeamSerializer(team).data
        self.assertIn('instructor_name', data)
        self.assertEqual(data['instructor_name'], 'Maria Santos')

    def test_pit_rubrics_scoped_by_year_level(self):
        from grading.rubrics.models import Rubric
        from defense.scheduler.serializers import schedule_options_payload as defense_scheduler_options_payload
        
        lead_1st = User.objects.create_user(
            username='lead_1st_year',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='1st Year',
        )
        lead_2nd = User.objects.create_user(
            username='lead_2nd_year',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )

        rubric_1st = Rubric.objects.create(
            name='1st Year Panel Rubric',
            scope=Rubric.SCOPE_PIT,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            semester=self.semester,
            created_by=lead_1st,
        )
        rubric_2nd = Rubric.objects.create(
            name='2nd Year Panel Rubric',
            scope=Rubric.SCOPE_PIT,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            semester=self.semester,
            created_by=lead_2nd,
        )

        payload_2nd = defense_scheduler_options_payload(lead_2nd, semester=self.semester, pit_lead_only=True)
        rubric_ids = [r['id'] for r in payload_2nd['rubrics']]
        self.assertIn(rubric_2nd.id, rubric_ids)
        self.assertNotIn(rubric_1st.id, rubric_ids)

    def test_pit_event_config_rejects_cross_year_rubric(self):
        from grading.rubrics.models import Rubric

        lead_1st = User.objects.create_user(
            username='lead_1st_year_b',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='1st Year',
        )
        lead_2nd = User.objects.create_user(
            username='lead_2nd_year_b',
            role='faculty',
            is_pit_lead=True,
            pit_lead_year='2nd Year',
        )

        rubric_1st_panel = Rubric.objects.create(
            name='1st Year Panel Rubric B',
            scope=Rubric.SCOPE_PIT,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            semester=self.semester,
            created_by=lead_1st,
        )
        rubric_2nd_peer = Rubric.objects.create(
            name='2nd Year Peer Rubric B',
            scope=Rubric.SCOPE_PIT,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            semester=self.semester,
            created_by=lead_2nd,
        )

        self.client.force_authenticate(user=lead_2nd)
        response = self.client.post('/api/defense/schedules/pit-event-config/', {
            'event_name': '2nd Year Expo',
            'panel_rubric_id': rubric_1st_panel.id,
            'peer_rubric_id': rubric_2nd_peer.id,
            'panel_weight': 80,
            'peer_weight': 20,
            'semester_id': self.semester.id,
        }, format='json')

        self.assertEqual(response.status_code, 400)
        self.assertIn('not permitted for your PIT year level', response.data.get('detail', ''))

    def test_pit_event_deliverable_defense_material_default_and_config(self):
        from .models import PitEventDeliverable
        from defense.stages.models import StageDeliverable
        from repository.deliverables.services import get_deliverable_definitions_for_team

        # 1. Check default value on StageDeliverable
        stage_deliv = StageDeliverable(deliverable_id='D1', label='Proposal Draft')
        self.assertFalse(stage_deliv.is_defense_material)

        # 2. Check default value on PitEventDeliverable
        pit_deliv = PitEventDeliverable(deliverable_id='D1', label='Pitch Deck')
        self.assertFalse(pit_deliv.is_defense_material)

        # 3. Test saving PIT event config with deliverables having is_defense_material
        config_payload = {
            'event_name': '1st Year Concept Pitch',
            'semester_id': self.semester.id,
            'panel_weight': 80,
            'peer_weight': 20,
            'deliverables': [
                {
                    'deliverable_id': 'D1',
                    'label': 'Pitch Deck Presentation',
                    'deliverable_type': 'pre',
                    'required': True,
                    'is_defense_material': True,
                },
                {
                    'deliverable_id': 'D2',
                    'label': 'Administrative Form',
                    'deliverable_type': 'pre',
                    'required': True,
                    'is_defense_material': False,
                },
            ]
        }
        self.client.force_authenticate(user=self.admin)
        response = self.client.post('/api/defense/schedules/pit-event-config/', config_payload, format='json')
        self.assertEqual(response.status_code, 200)

        # 4. Verify get_pit_event_config and payload
        res_config = response.data.get('config', {})
        delivs = res_config.get('deliverables', [])
        self.assertEqual(len(delivs), 2)
        d1 = next(d for d in delivs if d['deliverable_id'] == 'D1')
        d2 = next(d for d in delivs if d['deliverable_id'] == 'D2')
        self.assertTrue(d1['is_defense_material'])
        self.assertFalse(d2['is_defense_material'])

        # 5. Verify get_deliverable_definitions_for_team for PIT team
        definitions = get_deliverable_definitions_for_team(self.team, '1st Year Concept Pitch')
        def1 = next(d for d in definitions if d['id'] == 'D1')
        def2 = next(d for d in definitions if d['id'] == 'D2')
        self.assertTrue(def1['is_defense_material'])
        self.assertFalse(def2['is_defense_material'])

        # 6. Verify stage_payload rows
        from repository.deliverables.services import stage_payload
        from repository.deliverables.models import DeliverableSubmission

        sp = stage_payload(self.team, '1st Year Concept Pitch')
        pre_rows = sp.get('pre', [])
        row_d1 = next(r for r in pre_rows if r['id'] == 'D1')
        row_d2 = next(r for r in pre_rows if r['id'] == 'D2')
        self.assertTrue(row_d1['is_defense_material'])
        self.assertFalse(row_d2['is_defense_material'])

        # 7. Create submissions for both D1 and D2, and verify defense_materials only includes D1
        DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='1st Year Concept Pitch',
            deliverable_id='D1',
            label='Pitch Deck',
            deliverable_type='pre',
            file_name='d1.pdf',
            status='pending',
        )
        DeliverableSubmission.objects.create(
            team=self.team,
            stage_label='1st Year Concept Pitch',
            deliverable_id='D2',
            label='Administrative Form',
            deliverable_type='pre',
            file_name='d2.pdf',
            status='pending',
        )
        sp_updated = stage_payload(self.team, '1st Year Concept Pitch')
        materials = [
            item for item in sp_updated.get('pre', [])
            if item.get('is_defense_material', False) and item.get('uploaded')
        ]
        self.assertEqual(len(materials), 1)
        self.assertEqual(materials[0]['id'], 'D1')








