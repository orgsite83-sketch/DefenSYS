from decimal import Decimal
from unittest.mock import patch

from django.core.exceptions import ValidationError as DjangoValidationError
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig, SchedulePanelist
from defense.stages.grading_config import get_or_create_stage_grading_config
from defense.stages.models import DefenseStage
from grading.rubrics.models import Rubric, RubricCriterion
from repository.audit.services import repository_scope
from student_teams.models import StudentTeam, TeamMembership, TeamStageProgress
from .models import GradeBreakdown, PeerEvaluationSubmission, StudentPeerGrade, TeamGrade
from .services import (
    find_matching_rubric,
    rebuild_component_breakdown,
    sync_missing_grade_rows,
    update_group_settings,
    _sync_unscheduled_team,
)


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
        stage_config = get_or_create_stage_grading_config(self.stage, self.semester)
        stage_config.panel_rubric = self.panel_rubric
        stage_config.adviser_rubric = self.adviser_rubric
        stage_config.peer_rubric = self.peer_rubric
        stage_config.save(
            update_fields=['panel_rubric', 'adviser_rubric', 'peer_rubric', 'updated_at']
        )
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
        sync_missing_grade_rows(user=self.admin)
        return TeamGrade.objects.get(team=self.capstone_team)

    def _enable_capstone_peer_grading(self):
        self.semester.capstone_peer_evaluation_enabled = True
        self.semester.save(update_fields=['capstone_peer_evaluation_enabled'])

    def _disable_capstone_peer_grading(self):
        self.semester.capstone_peer_evaluation_enabled = False
        self.semester.save(update_fields=['capstone_peer_evaluation_enabled'])

    def _peer_eval_payload(self, evaluatee, total='4.00'):
        return {
            'teamId': self.capstone_team.id,
            'evaluateeId': evaluatee.id,
            'breakdown': [
                {'criteriaName': 'Technical Quality', 'score': 4, 'max': 5},
            ],
            'total': total,
            'max': '5.00',
        }

    def _submit_all_capstone_peer_evaluations(self):
        self._enable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)
        self.client.post(
            '/api/grading/grades/peer-evaluations/',
            self._peer_eval_payload(self.second_student),
            format='json',
        )
        self.client.force_authenticate(user=self.second_student)
        self.client.post(
            '/api/grading/grades/peer-evaluations/',
            self._peer_eval_payload(self.student),
            format='json',
        )
        self.client.force_authenticate(user=self.admin)

    def _make_capstone_grade_ready_for_close(self, grade):
        self._enable_capstone_peer_grading()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '100.00', 'adviser_score': '100.00'},
            format='json',
        )
        self._submit_all_capstone_peer_evaluations()

    def test_sync_endpoint_syncs_schedules_into_grade_rows(self):
        response = self.client.post('/api/grading/grades/sync/', {'scope': 'capstone'})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['filtered'], 1)
        self.assertEqual(response.data['grades'][0]['team_name'], 'Team VaultSync')
        self.assertEqual(response.data['grades'][0]['weights']['panel'], 50)
        self.assertEqual(TeamGrade.objects.count(), 2)

    def test_list_does_not_sync_schedules_into_grade_rows(self):
        response = self.client.get('/api/grading/grades/', {'scope': 'capstone'})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['filtered'], 0)
        self.assertEqual(response.data['grades'], [])
        self.assertEqual(TeamGrade.objects.count(), 0)

    def test_admin_default_scope_is_capstone_when_param_omitted(self):
        sync_missing_grade_rows(user=self.admin)

        response = self.client.get('/api/grading/grades/')

        self.assertEqual(response.status_code, 200)
        scopes = {grade['scope'] for grade in response.data['grades']}
        self.assertEqual(scopes, {TeamGrade.SCOPE_CAPSTONE})

    def test_admin_scope_pit_returns_only_pit(self):
        sync_missing_grade_rows(user=self.admin)

        response = self.client.get('/api/grading/grades/', {'scope': 'pit'})

        self.assertEqual(response.status_code, 200)
        self.assertGreaterEqual(response.data['counts']['filtered'], 1)
        self.assertTrue(
            all(grade['scope'] == TeamGrade.SCOPE_PIT for grade in response.data['grades']),
        )

    def test_admin_scope_all_returns_capstone_and_pit(self):
        sync_missing_grade_rows(user=self.admin)

        response = self.client.get('/api/grading/grades/', {'scope': 'all'})

        self.assertEqual(response.status_code, 200)
        scopes = {grade['scope'] for grade in response.data['grades']}
        self.assertIn(TeamGrade.SCOPE_CAPSTONE, scopes)
        self.assertIn(TeamGrade.SCOPE_PIT, scopes)

    def test_grade_center_records_are_scoped_by_requesting_role(self):
        sync_missing_grade_rows(user=self.admin)

        def visible_scopes(user):
            self.client.force_authenticate(user=user)
            response = self.client.get('/api/grading/grades/', {'scope': 'all'})
            self.assertEqual(response.status_code, 200)
            return {grade['scope'] for grade in response.data['grades']}

        self.assertEqual(
            visible_scopes(self.pit_lead),
            {TeamGrade.SCOPE_PIT},
        )
        self.assertEqual(
            visible_scopes(self.adviser),
            {TeamGrade.SCOPE_CAPSTONE},
        )
        self.assertEqual(
            visible_scopes(self.pit_student),
            {TeamGrade.SCOPE_PIT},
        )

    def test_pit_schedule_sync_removes_unscheduled_placeholder_grade(self):
        pit_panel_rubric = Rubric.objects.create(
            name='PIT Panel Rubric',
            scope=Rubric.SCOPE_PIT,
            semester=self.first_semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        pit_team = StudentTeam.objects.create(
            name='Team Placeholder',
            project_title='Placeholder Project',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.first_semester,
            leader=self.pit_student,
        )
        TeamMembership.objects.create(team=pit_team, student=self.pit_student, is_leader=True)

        _sync_unscheduled_team(pit_team)
        placeholder = TeamGrade.objects.get(team=pit_team, scope=TeamGrade.SCOPE_PIT)
        self.assertEqual(placeholder.stage_label, 'Unscheduled')
        self.assertIsNone(placeholder.schedule_id)

        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.first_semester,
            team=pit_team,
            event_name='2nd Year PIT Expo',
            rubric=pit_panel_rubric,
            scheduled_date='2026-05-16',
            start_time='09:00',
            slot_duration=45,
            room='Lab 2',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )

        sync_missing_grade_rows(user=self.admin)

        grades = TeamGrade.objects.filter(team=pit_team, scope=TeamGrade.SCOPE_PIT)
        self.assertEqual(grades.count(), 1)
        grade = grades.get()
        self.assertEqual(grade.stage_label, '2nd Year PIT Expo')
        self.assertIsNotNone(grade.schedule_id)

    def test_grade_center_get_does_not_delete_stale_placeholder(self):
        sync_missing_grade_rows(user=self.admin, repair_placeholders=False)
        canonical = TeamGrade.objects.get(team=self.capstone_team, schedule=self.capstone_schedule)
        stale = TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label='Unscheduled',
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
        )

        response = self.client.get('/api/grading/grades/')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(TeamGrade.objects.filter(pk=canonical.pk).exists())
        self.assertTrue(TeamGrade.objects.filter(pk=stale.pk).exists())

    def test_explicit_sync_still_repairs_stale_placeholder(self):
        sync_missing_grade_rows(user=self.admin, repair_placeholders=False)
        canonical = TeamGrade.objects.get(team=self.capstone_team, schedule=self.capstone_schedule)
        stale = TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label='Unscheduled',
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
        )

        sync_missing_grade_rows(user=self.admin)

        self.assertTrue(TeamGrade.objects.filter(pk=canonical.pk).exists())
        self.assertFalse(TeamGrade.objects.filter(pk=stale.pk).exists())

    def test_capstone_endorse_removes_unscheduled_placeholder_grade(self):
        concept_stage = DefenseStage.objects.get(label='Concept Proposal')
        team = StudentTeam.objects.create(
            name='Team Grade Dedupe',
            project_title='Dedupe Capstone',
            level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year',
            semester=self.semester,
            leader=self.student,
            adviser=self.adviser,
        )
        TeamMembership.objects.create(team=team, student=self.student, is_leader=True)

        _sync_unscheduled_team(team)
        placeholder = TeamGrade.objects.get(team=team, scope=TeamGrade.SCOPE_CAPSTONE)
        self.assertEqual(placeholder.stage_label, 'Unscheduled')
        self.assertIsNone(placeholder.schedule_id)

        team.ready_for_stage = concept_stage.label
        team.save(update_fields=['ready_for_stage', 'updated_at'])

        sync_missing_grade_rows(user=self.admin)

        grades = TeamGrade.objects.filter(team=team, scope=TeamGrade.SCOPE_CAPSTONE)
        self.assertEqual(grades.count(), 1)
        grade = grades.get()
        self.assertEqual(grade.stage_label, concept_stage.label)
        self.assertEqual(grade.defense_stage_id, concept_stage.id)
        self.assertIsNone(grade.schedule_id)

    def test_capstone_schedule_sync_preserves_previous_stage_grade(self):
        concept_stage = DefenseStage.objects.get(label='Concept Proposal')
        concept_grade = TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label=concept_stage.label,
            panel_score=Decimal('90.00'),
            adviser_score=Decimal('88.00'),
            peer_score=Decimal('92.00'),
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
            status=TeamGrade.STATUS_PUBLISHED,
        )

        sync_missing_grade_rows(user=self.admin)

        grades = TeamGrade.objects.filter(
            team=self.capstone_team,
            scope=TeamGrade.SCOPE_CAPSTONE,
        )
        self.assertEqual(grades.count(), 2)
        concept_grade.refresh_from_db()
        project_grade = grades.get(stage_label=self.stage.label)
        self.assertEqual(project_grade.defense_stage_id, self.stage.id)
        self.assertEqual(concept_grade.stage_label, concept_stage.label)
        self.assertEqual(concept_grade.status, TeamGrade.STATUS_PUBLISHED)
        self.assertIsNone(project_grade.panel_score)
        self.assertIsNone(project_grade.adviser_score)
        self.assertIsNone(project_grade.peer_score)

    def test_schedule_sync_and_panel_submission_use_same_grade_row(self):
        sync_missing_grade_rows(user=self.admin)
        grade = TeamGrade.objects.get(team=self.capstone_team, schedule=self.capstone_schedule)
        self.client.force_authenticate(user=self.panelist)

        response = self.client.post(
            '/api/defense/schedules/submit-grades/',
            {
                'team_id': self.capstone_team.id,
                'schedule_id': self.capstone_schedule.id,
                'criteria_scores': [
                    {
                        'criterion_id': self.panel_rubric.criteria.get().id,
                        'score': 8,
                    },
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['team_grade_id'], grade.id)
        self.assertEqual(
            TeamGrade.objects.filter(
                team=self.capstone_team,
                defense_stage=self.stage,
            ).count(),
            1,
        )

    def test_capstone_grade_uses_stage_identity_after_stage_rename(self):
        grade = self._capstone_grade()
        self.assertEqual(grade.defense_stage_id, self.stage.id)

        self.stage.label = 'Renamed Project Proposal'
        self.stage.save(update_fields=['label'])
        grade.refresh_from_db()

        rubric = find_matching_rubric(grade, Rubric.EVAL_ADVISER)
        self.assertEqual(rubric.id, self.adviser_rubric.id)
        self.assertEqual(grade.defense_stage_id, self.stage.id)

    def test_capstone_grade_uniqueness_uses_stage_identity(self):
        other_stage = DefenseStage.objects.create(
            label='Final Defense Identity',
            display_order=98,
            is_active=True,
        )
        TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            defense_stage=self.stage,
        )
        TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            defense_stage=other_stage,
        )

        with self.assertRaises(DjangoValidationError):
            TeamGrade.objects.create(
                team=self.capstone_team,
                semester=self.semester,
                scope=TeamGrade.SCOPE_CAPSTONE,
                defense_stage=self.stage,
            )

    def test_pit_grade_uniqueness_uses_event_identity(self):
        config = self._ensure_pit_event_config('PIT Identity', semester=self.first_semester)
        other_config = self._ensure_pit_event_config('PIT Identity 2', semester=self.first_semester)
        TeamGrade.objects.create(
            team=self.pit_team,
            semester=self.first_semester,
            scope=TeamGrade.SCOPE_PIT,
            pit_event_config=config,
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
        )
        TeamGrade.objects.create(
            team=self.pit_team,
            semester=self.first_semester,
            scope=TeamGrade.SCOPE_PIT,
            pit_event_config=other_config,
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
        )

        with self.assertRaises(DjangoValidationError):
            TeamGrade.objects.create(
                team=self.pit_team,
                semester=self.first_semester,
                scope=TeamGrade.SCOPE_PIT,
                pit_event_config=config,
                panel_weight=80,
                peer_weight=20,
                adviser_weight=0,
            )

    def test_pit_peer_submit_rejects_ambiguous_event_context(self):
        second_pit = User.objects.create_user(
            username='2025-0002-ambiguous',
            password='pass12345',
            role='student',
            first_name='Ana',
            last_name='Lopez',
        )
        TeamMembership.objects.create(team=self.pit_team, student=second_pit, order=1)
        config = self._ensure_pit_event_config('PIT Identity', semester=self.first_semester)
        other_config = self._ensure_pit_event_config('PIT Identity 2', semester=self.first_semester)
        for event_config in (config, other_config):
            event_config.peer_grading_enabled = True
            event_config.save(update_fields=['peer_grading_enabled', 'updated_at'])
            RubricCriterion.objects.create(
                rubric=event_config.peer_rubric,
                name=f'Teamwork {event_config.event_name}',
                scale=Rubric.SCALE_5,
                max_score=5,
                display_order=0,
            )
            TeamGrade.objects.create(
                team=self.pit_team,
                semester=self.first_semester,
                scope=TeamGrade.SCOPE_PIT,
                pit_event_config=event_config,
                panel_weight=80,
                peer_weight=20,
                adviser_weight=0,
            )

        self.client.force_authenticate(user=self.pit_student)
        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.pit_team.id,
                'evaluateeId': second_pit.id,
                'breakdown': [{'criteriaName': 'Teamwork', 'score': 4, 'max': 5}],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('pit_event_config_id', response.data)
        self.assertFalse(PeerEvaluationSubmission.objects.filter(team_grade__team=self.pit_team).exists())

    def test_pit_peer_submit_uses_only_open_event_when_multiple_grades_exist(self):
        second_pit = User.objects.create_user(
            username='2025-0002-open',
            password='pass12345',
            role='student',
            first_name='Ana',
            last_name='Lopez',
        )
        TeamMembership.objects.create(team=self.pit_team, student=second_pit, order=1)
        config = self._ensure_pit_event_config('PIT Identity', semester=self.first_semester)
        other_config = self._ensure_pit_event_config('PIT Identity 2', semester=self.first_semester)
        config.peer_grading_enabled = True
        config.save(update_fields=['peer_grading_enabled', 'updated_at'])
        RubricCriterion.objects.create(
            rubric=config.peer_rubric,
            name='Teamwork',
            scale=Rubric.SCALE_5,
            max_score=5,
            display_order=0,
        )
        open_grade = TeamGrade.objects.create(
            team=self.pit_team,
            semester=self.first_semester,
            scope=TeamGrade.SCOPE_PIT,
            pit_event_config=config,
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
        )
        closed_grade = TeamGrade.objects.create(
            team=self.pit_team,
            semester=self.first_semester,
            scope=TeamGrade.SCOPE_PIT,
            pit_event_config=other_config,
            panel_weight=80,
            peer_weight=20,
            adviser_weight=0,
        )

        self.client.force_authenticate(user=self.pit_student)
        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.pit_team.id,
                'evaluateeId': second_pit.id,
                'breakdown': [{'criteriaName': 'Teamwork', 'score': 4, 'max': 5}],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            PeerEvaluationSubmission.objects.filter(
                team_grade=open_grade,
                evaluator=self.pit_student,
                evaluatee=second_pit,
            ).count(),
            1,
        )
        self.assertFalse(PeerEvaluationSubmission.objects.filter(team_grade=closed_grade).exists())

    def test_update_scores_calculates_status_and_final_grade(self):
        grade = self._capstone_grade()

        awaiting = self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '88.00', 'adviser_score': '90.00'},
            format='json',
        )
        complete = self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'peer_score': '86.00'},
            format='json',
        )

        self.assertEqual(awaiting.status_code, 200)
        self.assertEqual(awaiting.data['grade']['status'], TeamGrade.STATUS_AWAITING_PEERS)
        self.assertIsNone(awaiting.data['grade']['final_grade'])
        self.assertEqual(complete.status_code, 200)
        self.assertEqual(complete.data['grade']['status'], TeamGrade.STATUS_PENDING)
        self.assertEqual(complete.data['grade']['final_grade'], '88.20')

    def test_publish_sets_team_result_and_schedule_done(self):
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '70.00', 'adviser_score': '70.00', 'peer_score': '70.00'},
            format='json',
        )

        response = self.client.post(f'/api/grading/grades/{grade.id}/publish/')
        self.capstone_team.refresh_from_db()
        self.capstone_schedule.refresh_from_db()

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['grade']['status'], TeamGrade.STATUS_PUBLISHED)
        self.assertEqual(self.capstone_team.status, StudentTeam.STATUS_FAILED)
        self.assertEqual(self.capstone_schedule.status, DefenseSchedule.STATUS_DONE)
        progress = TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage)
        self.assertEqual(progress.status, TeamStageProgress.STATUS_FAILED)
        self.assertEqual(progress.grade, grade)

    def test_pit_lead_scope_only_returns_assigned_pit_year(self):
        sync_missing_grade_rows(user=self.pit_lead)
        self.client.force_authenticate(user=self.pit_lead)

        response = self.client.get('/api/grading/grades/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['all'], 1)
        self.assertEqual(response.data['grades'][0]['team_name'], 'Team Circuit')

    def test_admin_dashboard_counts_grades_and_reports_phase_eleven(self):
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '88.00', 'adviser_score': '90.00', 'peer_score': '87.00'},
            format='json',
        )
        self.client.post(f'/api/grading/grades/{grade.id}/publish/')

        response = self.client.get('/api/dashboards/admin/')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['stats']['published_grades'], 1)
        self.assertEqual(response.data['migration']['phase'], 15)

    def test_list_includes_group_settings(self):
        sync_missing_grade_rows(user=self.admin)
        response = self.client.get('/api/grading/grades/')

        self.assertEqual(response.status_code, 200)
        self.assertIn('group_settings', response.data)
        capstone_key = f'capstone|{self.stage.label}'
        self.assertIn(capstone_key, response.data['group_settings'])

    def test_group_settings_includes_zero_team_capstone_stage_after_complete(self):
        empty_stage = DefenseStage.objects.create(
            label='Zero Team Stage',
            display_order=99,
            is_active=True,
        )
        patch_response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': empty_stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )
        self.assertEqual(patch_response.status_code, 200)

        list_response = self.client.get('/api/grading/grades/')
        self.assertEqual(list_response.status_code, 200)
        key = f'capstone|{empty_stage.label}'
        self.assertIn(key, list_response.data['group_settings'])
        self.assertTrue(list_response.data['group_settings'][key]['is_officially_complete'])

    def test_list_includes_capstone_stages_for_admin(self):
        response = self.client.get('/api/grading/grades/')

        self.assertEqual(response.status_code, 200)
        self.assertIn('capstone_stages', response.data)
        labels = [stage['label'] for stage in response.data['capstone_stages']]
        self.assertIn(self.stage.label, labels)

    def test_patch_pit_group_settings(self):
        pit_panel = Rubric.objects.create(
            name='PIT Panel Active',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        pit_peer = Rubric.objects.create(
            name='PIT Peer Active',
            scope=Rubric.SCOPE_PIT,
            semester=self.semester,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        RubricCriterion.objects.create(
            rubric=pit_peer,
            name='Teamwork',
            scale=Rubric.SCALE_5,
            max_score=5,
            display_order=0,
        )
        PitEventGradingConfig.objects.create(
            semester=self.semester,
            event_name='PIT Expo',
            panel_rubric=pit_panel,
            peer_rubric=pit_peer,
        )

        response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo',
                'peer_grading_enabled': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        key = 'pit|PIT Expo'
        self.assertTrue(response.data['group_settings'][key]['peer_grading_enabled'])

    def _ensure_pit_event_config(self, event_name='PIT Expo', semester=None):
        semester = semester or self.semester
        existing = PitEventGradingConfig.objects.filter(
            semester=semester,
            event_name__iexact=event_name,
        ).first()
        if existing:
            return existing
        pit_panel = Rubric.objects.create(
            name=f'PIT Panel {event_name}',
            scope=Rubric.SCOPE_PIT,
            semester=semester,
            evaluation_type=Rubric.EVAL_PANEL,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        pit_peer = Rubric.objects.create(
            name=f'PIT Peer {event_name}',
            scope=Rubric.SCOPE_PIT,
            semester=semester,
            evaluation_type=Rubric.EVAL_PEER,
            status=Rubric.STATUS_PUBLISHED,
            created_by=self.admin,
        )
        return PitEventGradingConfig.objects.create(
            semester=semester,
            event_name=event_name,
            panel_rubric=pit_panel,
            peer_rubric=pit_peer,
        )

    def test_pit_official_complete_auto_publishes_passed_grades(self):
        self.pit_team.semester = self.semester
        self.pit_team.save(update_fields=['semester'])
        self.pit_schedule.semester = self.semester
        self.pit_schedule.save(update_fields=['semester'])
        self._ensure_pit_event_config(event_name='PIT Expo', semester=self.semester)
        sync_missing_grade_rows(user=self.admin)
        grade = TeamGrade.objects.get(team=self.pit_team, scope=TeamGrade.SCOPE_PIT)
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '90.00', 'peer_score': '80.00'},
            format='json',
        )
        grade.refresh_from_db()
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)
        self.assertGreaterEqual(grade.final_grade, Decimal('75.00'))

        response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo',
                'is_officially_complete': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['auto_publish']['ready_for_archive_count'], 1)
        grade.refresh_from_db()
        self.pit_team.refresh_from_db()
        self.pit_schedule.refresh_from_db()
        config = PitEventGradingConfig.objects.get(semester=self.semester, event_name='PIT Expo')
        self.assertTrue(config.is_officially_complete)
        self.assertEqual(grade.status, TeamGrade.STATUS_PUBLISHED)
        self.assertEqual(self.pit_schedule.status, DefenseSchedule.STATUS_DONE)
        self.assertEqual(self.pit_team.status, StudentTeam.STATUS_APPROVED)

    def test_pit_official_complete_skips_failed_grade(self):
        self._ensure_pit_event_config(event_name='PIT Expo Fail', semester=self.semester)
        failed_team = StudentTeam.objects.create(
            name='Team Fail',
            project_title='Fail Project',
            level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year',
            semester=self.semester,
            leader=self.pit_student,
        )
        TeamMembership.objects.create(team=failed_team, student=self.pit_student, is_leader=True)
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.semester,
            team=failed_team,
            event_name='PIT Expo Fail',
            scheduled_date='2026-05-17',
            start_time='10:00',
            slot_duration=45,
            room='Lab 3',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        sync_missing_grade_rows(user=self.admin)
        grade = TeamGrade.objects.get(team=failed_team, scope=TeamGrade.SCOPE_PIT)
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '50.00', 'peer_score': '50.00'},
            format='json',
        )

        response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo Fail',
                'is_officially_complete': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['auto_publish']['published_count'], 0)
        self.assertGreaterEqual(response.data['auto_publish']['skipped_below_threshold'], 1)
        grade.refresh_from_db()
        self.assertNotEqual(grade.status, TeamGrade.STATUS_PUBLISHED)

    def test_capstone_official_complete_auto_finalizes_passed_grades(self):
        grade = self._capstone_grade()
        self._make_capstone_grade_ready_for_close(grade)
        grade.refresh_from_db()
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)
        self.assertGreaterEqual(grade.final_grade, Decimal('75.00'))

        response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['auto_finalize']['ready_for_archive_count'], 1)
        grade.refresh_from_db()
        self.capstone_team.refresh_from_db()
        self.capstone_schedule.refresh_from_db()
        stage_config = get_or_create_stage_grading_config(self.stage, self.semester)
        self.assertTrue(stage_config.is_officially_complete)
        self.assertEqual(grade.status, TeamGrade.STATUS_PUBLISHED)
        self.assertEqual(self.capstone_schedule.status, DefenseSchedule.STATUS_DONE)
        self.assertEqual(self.capstone_team.status, StudentTeam.STATUS_APPROVED)
        progress = TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage)
        self.assertEqual(progress.status, TeamStageProgress.STATUS_PASSED)
        self.assertEqual(progress.grade, grade)

    def test_pit_lead_completion_finalizes_only_assigned_year(self):
        self.pit_team.semester = self.semester
        self.pit_team.save(update_fields=['semester'])
        self.pit_schedule.semester = self.semester
        self.pit_schedule.save(update_fields=['semester'])
        self._ensure_pit_event_config(event_name='PIT Expo', semester=self.semester)
        third_student = User.objects.create_user(
            username='2025-0003',
            password='pass12345',
            role='student',
        )
        third_team = StudentTeam.objects.create(
            name='Team Other PIT',
            project_title='Other PIT Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=third_student,
        )
        TeamMembership.objects.create(team=third_team, student=third_student, is_leader=True)
        third_schedule = DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.semester,
            team=third_team,
            event_name='PIT Expo',
            scheduled_date='2026-05-17',
            start_time='10:00',
            slot_duration=45,
            room='Lab 3',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        sync_missing_grade_rows(user=self.admin)
        own_grade = TeamGrade.objects.get(team=self.pit_team, scope=TeamGrade.SCOPE_PIT)
        other_grade = TeamGrade.objects.get(team=third_team, scope=TeamGrade.SCOPE_PIT)
        own_grade.panel_score = Decimal('90.00')
        own_grade.peer_score = Decimal('85.00')
        own_grade.save()
        other_grade.panel_score = Decimal('95.00')
        other_grade.peer_score = Decimal('95.00')
        other_grade.save()

        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo',
                'is_officially_complete': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['auto_publish']['ready_for_archive_count'], 1)
        own_grade.refresh_from_db()
        other_grade.refresh_from_db()
        self.pit_schedule.refresh_from_db()
        third_schedule.refresh_from_db()
        self.assertEqual(own_grade.status, TeamGrade.STATUS_PUBLISHED)
        self.assertEqual(self.pit_schedule.status, DefenseSchedule.STATUS_DONE)
        self.assertEqual(other_grade.status, TeamGrade.STATUS_PENDING)
        self.assertEqual(third_schedule.status, DefenseSchedule.STATUS_SCHEDULED)
        self.assertTrue(repository_scope(self.pit_lead)['can_upload_pit'])

    def test_pit_lead_completion_without_assigned_year_grades_is_blocked(self):
        self._ensure_pit_event_config(event_name='PIT Expo Other Year', semester=self.semester)
        third_student = User.objects.create_user(
            username='2025-0004',
            password='pass12345',
            role='student',
        )
        third_team = StudentTeam.objects.create(
            name='Team Third Year Only',
            project_title='Third Year PIT Project',
            level=StudentTeam.LEVEL_3_PIT,
            year_level='3rd Year',
            semester=self.semester,
            leader=third_student,
        )
        TeamMembership.objects.create(team=third_team, student=third_student, is_leader=True)
        DefenseSchedule.objects.create(
            scope=DefenseSchedule.SCOPE_PIT,
            semester=self.semester,
            team=third_team,
            event_name='PIT Expo Other Year',
            scheduled_date='2026-05-18',
            start_time='11:00',
            slot_duration=45,
            room='Lab 4',
            status=DefenseSchedule.STATUS_SCHEDULED,
            created_by=self.admin,
        )
        sync_missing_grade_rows(user=self.admin)
        other_grade = TeamGrade.objects.get(team=third_team, scope=TeamGrade.SCOPE_PIT)
        other_grade.panel_score = Decimal('90.00')
        other_grade.peer_score = Decimal('90.00')
        other_grade.save()

        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo Other Year',
                'is_officially_complete': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        config = PitEventGradingConfig.objects.get(
            semester=self.semester,
            event_name='PIT Expo Other Year',
        )
        other_grade.refresh_from_db()
        self.assertFalse(config.is_officially_complete)
        self.assertEqual(other_grade.status, TeamGrade.STATUS_PENDING)

    def test_official_completion_rolls_back_when_finalization_fails(self):
        grade = self._capstone_grade()
        self._make_capstone_grade_ready_for_close(grade)
        grade.refresh_from_db()
        stage_config = get_or_create_stage_grading_config(self.stage, self.semester)

        with patch(
            'grading.grades.services.GradeContextService.finalize_for_archive',
            side_effect=RuntimeError('finalization failed'),
        ):
            with self.assertRaises(RuntimeError):
                update_group_settings(
                    semester=self.semester,
                    scope=TeamGrade.SCOPE_CAPSTONE,
                    stage_label=self.stage.label,
                    is_officially_complete=True,
                    user=self.admin,
                )

        stage_config.refresh_from_db()
        grade.refresh_from_db()
        self.capstone_schedule.refresh_from_db()
        self.capstone_team.refresh_from_db()
        self.assertFalse(stage_config.is_officially_complete)
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)
        self.assertEqual(self.capstone_schedule.status, DefenseSchedule.STATUS_SCHEDULED)
        self.assertEqual(self.capstone_team.status, StudentTeam.STATUS_PENDING)

    def test_capstone_official_complete_skips_below_threshold(self):
        grade = self._capstone_grade()
        self._disable_capstone_peer_grading()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '70.00', 'adviser_score': '70.00', 'peer_score': '70.00'},
            format='json',
        )
        grade.refresh_from_db()
        self.assertLess(grade.final_grade, Decimal('75.00'))

        response = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['auto_finalize']['ready_for_archive_count'], 0)
        self.assertGreaterEqual(response.data['auto_finalize']['skipped_below_threshold'], 1)
        grade.refresh_from_db()
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)

    def test_capstone_list_does_not_repair_pending_passed_when_stage_complete(self):
        grade = self._capstone_grade()
        self._make_capstone_grade_ready_for_close(grade)
        self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )
        grade.refresh_from_db()
        grade.status = TeamGrade.STATUS_PENDING
        grade.save(update_fields=['status', 'updated_at'])

        response = self.client.get('/api/grading/grades/')
        self.assertEqual(response.status_code, 200)
        grade.refresh_from_db()
        self.assertEqual(grade.status, TeamGrade.STATUS_PENDING)

    def test_capstone_peer_sync_auto_finalizes_when_stage_complete(self):
        grade = self._capstone_grade()
        self._make_capstone_grade_ready_for_close(grade)
        grade.refresh_from_db()
        self.assertIsNotNone(grade.peer_score)
        self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )
        grade.refresh_from_db()
        self.assertGreaterEqual(grade.final_grade, Decimal('75.00'))
        self.assertEqual(grade.status, TeamGrade.STATUS_PUBLISHED)

    def test_partial_peer_submission_does_not_set_peer_score(self):
        grade = self._capstone_grade()
        self._enable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)
        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            self._peer_eval_payload(self.second_student),
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        grade.refresh_from_db()
        self.assertIsNone(grade.peer_score)
        self.assertFalse(StudentPeerGrade.objects.filter(team_grade=grade).exists())

    def test_full_peer_submission_sets_peer_score(self):
        grade = self._capstone_grade()
        self._submit_all_capstone_peer_evaluations()
        grade.refresh_from_db()
        self.assertIsNotNone(grade.peer_score)
        self.assertEqual(StudentPeerGrade.objects.filter(team_grade=grade).count(), 2)

    def test_grade_detail_does_not_refresh_peer_summaries(self):
        grade = self._capstone_grade()
        PeerEvaluationSubmission.objects.create(
            team_grade=grade,
            evaluator=self.student,
            evaluatee=self.second_student,
            total_score=Decimal('4.00'),
            max_score=Decimal('5.00'),
            breakdown=[{'criteriaName': 'Technical Quality', 'score': 4, 'max': 5}],
        )
        PeerEvaluationSubmission.objects.create(
            team_grade=grade,
            evaluator=self.second_student,
            evaluatee=self.student,
            total_score=Decimal('5.00'),
            max_score=Decimal('5.00'),
            breakdown=[{'criteriaName': 'Technical Quality', 'score': 5, 'max': 5}],
        )

        response = self.client.get(f'/api/grading/grades/{grade.id}/')

        self.assertEqual(response.status_code, 200)
        grade.refresh_from_db()
        self.assertIsNone(grade.peer_score)
        self.assertFalse(StudentPeerGrade.objects.filter(team_grade=grade).exists())

    def test_pit_close_blocked_when_peer_grading_open_and_incomplete(self):
        self.pit_team.semester = self.semester
        self.pit_team.save(update_fields=['semester'])
        self.pit_schedule.semester = self.semester
        self.pit_schedule.save(update_fields=['semester'])
        second_pit = User.objects.create_user(
            username='2025-0002',
            password='pass12345',
            role='student',
            first_name='Ana',
            last_name='Lopez',
        )
        TeamMembership.objects.create(team=self.pit_team, student=second_pit, order=1)
        self._ensure_pit_event_config(event_name='PIT Expo', semester=self.semester)
        sync_missing_grade_rows(user=self.admin)
        self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo',
                'peer_grading_enabled': True,
            },
            format='json',
        )
        self.client.force_authenticate(user=self.pit_student)
        self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.pit_team.id,
                'evaluateeId': second_pit.id,
                'breakdown': [{'criteriaName': 'Teamwork', 'score': 4, 'max': 5}],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )
        self.client.force_authenticate(user=self.admin)
        blocked = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo',
                'is_officially_complete': True,
            },
            format='json',
        )
        self.assertEqual(blocked.status_code, 400)
        self.assertIn('incomplete_teams', blocked.data)

    def test_pit_close_blocked_when_panel_missing(self):
        self.pit_team.semester = self.semester
        self.pit_team.save(update_fields=['semester'])
        self.pit_schedule.semester = self.semester
        self.pit_schedule.save(update_fields=['semester'])
        self._ensure_pit_event_config(event_name='PIT Expo', semester=self.semester)
        sync_missing_grade_rows(user=self.admin)
        blocked = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_PIT,
                'stage_label': 'PIT Expo',
                'is_officially_complete': True,
            },
            format='json',
        )
        self.assertEqual(blocked.status_code, 400)
        self.assertIn('panel', blocked.data['incomplete_teams'][0]['missing_components'])

    def test_capstone_close_blocked_when_term_peer_enabled_no_submissions(self):
        self._enable_capstone_peer_grading()
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '100.00', 'adviser_score': '100.00'},
            format='json',
        )
        blocked = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )
        self.assertEqual(blocked.status_code, 400)
        self.assertIn('peer', blocked.data['incomplete_teams'][0]['missing_components'])

    def test_capstone_close_blocked_when_adviser_missing(self):
        self._enable_capstone_peer_grading()
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '100.00'},
            format='json',
        )
        self._submit_all_capstone_peer_evaluations()
        blocked = self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )
        self.assertEqual(blocked.status_code, 400)
        self.assertIn('adviser', blocked.data['incomplete_teams'][0]['missing_components'])

    def test_partial_peer_does_not_auto_finalize_after_stage_complete(self):
        grade = self._capstone_grade()
        self._make_capstone_grade_ready_for_close(grade)
        self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )
        grade.refresh_from_db()
        grade.status = TeamGrade.STATUS_PENDING
        grade.peer_score = None
        grade.save(update_fields=['status', 'peer_score', 'updated_at'])
        PeerEvaluationSubmission.objects.filter(team_grade=grade).delete()
        StudentPeerGrade.objects.filter(team_grade=grade).delete()
        self.client.force_authenticate(user=self.student)
        self.client.post(
            '/api/grading/grades/peer-evaluations/',
            self._peer_eval_payload(self.second_student),
            format='json',
        )
        grade.refresh_from_db()
        self.assertIsNone(grade.peer_score)
        self.assertNotEqual(grade.status, TeamGrade.STATUS_PUBLISHED)

    def test_patch_grade_blocked_when_event_officially_complete(self):
        grade = self._capstone_grade()
        self._make_capstone_grade_ready_for_close(grade)
        self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )

        response = self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '80.00'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)

    def test_peer_submit_requires_term_peer_evaluation_enabled(self):
        grade = self._capstone_grade()
        self._disable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)

        blocked = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.capstone_team.id,
                'evaluateeId': self.second_student.id,
                'breakdown': [],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )
        self.assertEqual(blocked.status_code, 400)

        self.client.force_authenticate(user=self.admin)
        self._enable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)
        allowed = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.capstone_team.id,
                'evaluateeId': self.second_student.id,
                'breakdown': [
                    {'criteriaName': 'Technical Quality', 'score': 4, 'max': 5},
                ],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )
        self.assertEqual(allowed.status_code, 200)
        self.assertEqual(
            PeerEvaluationSubmission.objects.filter(
                team_grade=grade,
                evaluator=self.student,
                evaluatee=self.second_student,
            ).count(),
            1,
        )

    def test_student_can_submit_peer_evaluation(self):
        grade = self._capstone_grade()
        self._enable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)

        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.capstone_team.id,
                'evaluateeId': self.second_student.id,
                'breakdown': [
                    {'criteriaName': 'Technical Quality', 'score': 4, 'max': 5},
                ],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            PeerEvaluationSubmission.objects.filter(
                team_grade=grade,
                evaluator=self.student,
                evaluatee=self.second_student,
            ).count(),
            1,
        )
        grade.refresh_from_db()
        self.assertIsNone(grade.peer_score)
        self.assertFalse(
            StudentPeerGrade.objects.filter(team_grade=grade).exists(),
        )

    def test_peer_submit_uses_evaluatee_id_when_names_duplicate(self):
        grade = self._capstone_grade()
        self._enable_capstone_peer_grading()
        duplicate_name_student = User.objects.create_user(
            username='2024-0003',
            password='pass12345',
            role='student',
            first_name='Maria',
            last_name='Santos',
        )
        TeamMembership.objects.create(
            team=self.capstone_team,
            student=duplicate_name_student,
            order=2,
        )
        self.client.force_authenticate(user=self.student)

        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.capstone_team.id,
                'evaluateeId': duplicate_name_student.id,
                'breakdown': [
                    {'criteriaName': 'Technical Quality', 'score': 4, 'max': 5},
                ],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['evaluateeId'], duplicate_name_student.id)
        self.assertEqual(response.data['evaluateeName'], 'Maria Santos')
        self.assertEqual(
            PeerEvaluationSubmission.objects.filter(
                team_grade=grade,
                evaluator=self.student,
                evaluatee=duplicate_name_student,
            ).count(),
            1,
        )
        self.assertFalse(
            PeerEvaluationSubmission.objects.filter(
                team_grade=grade,
                evaluator=self.student,
                evaluatee=self.second_student,
            ).exists()
        )

    def test_adviser_submit_merges_stale_grade_row(self):
        sync_missing_grade_rows(user=self.admin, repair_placeholders=False)
        canonical = TeamGrade.objects.get(team=self.capstone_team, schedule=self.capstone_schedule)
        stale = TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label='Unscheduled',
            adviser_score=Decimal('88.00'),
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
        )
        self.assertNotEqual(stale.pk, canonical.pk)

        self.client.force_authenticate(user=self.adviser)
        response = self.client.post(
            f'/api/grading/grades/adviser-grades/{stale.pk}/submit/',
            {
                'adviser_score': '95.00',
                'rubric_id': self.adviser_rubric.id,
                'criteria_scores': [
                    {
                        'criterion_name': 'Technical Quality',
                        'score': 9.5,
                        'max_score': 10,
                        'display_order': 0,
                    },
                ],
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(TeamGrade.objects.filter(team=self.capstone_team).count(), 1)
        merged = TeamGrade.objects.get(team=self.capstone_team)
        self.assertEqual(merged.pk, canonical.pk)
        self.assertEqual(merged.adviser_score, Decimal('95.00'))

    def test_adviser_list_returns_one_canonical_row_per_team(self):
        sync_missing_grade_rows(user=self.admin, repair_placeholders=False)
        TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label='Unscheduled',
            adviser_weight=30,
            panel_weight=50,
            peer_weight=20,
        )
        self.client.force_authenticate(user=self.adviser)
        response = self.client.get('/api/grading/grades/adviser-grades/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['grades']), 1)
        self.assertEqual(response.data['grades'][0]['assigned_adviser_rubric_id'], self.adviser_rubric.id)

    def test_adviser_submit_requires_configured_adviser_rubric(self):
        grade = self._capstone_grade()
        config = get_or_create_stage_grading_config(self.stage, self.semester)
        config.adviser_rubric = None
        config.save(update_fields=['adviser_rubric', 'updated_at'])
        self.client.force_authenticate(user=self.adviser)

        response = self.client.post(
            f'/api/grading/grades/adviser-grades/{grade.id}/submit/',
            {'adviser_score': '95.00'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('rubric', response.data)
        grade.refresh_from_db()
        self.assertIsNone(grade.adviser_score)

    def test_rebuild_component_breakdown_requires_rubric_criteria(self):
        grade = self._capstone_grade()
        self.adviser_rubric.criteria.all().delete()

        with self.assertRaises(DjangoValidationError):
            rebuild_component_breakdown(grade, Rubric.EVAL_ADVISER, Decimal('0.90'))

    def test_student_dashboard_includes_peer_criteria(self):
        self._capstone_grade()
        self._enable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)

        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['peerCriteria'])
        self.assertTrue(response.data['peerEvalEnabled'])

    def test_peer_submit_requires_configured_peer_rubric(self):
        grade = self._capstone_grade()
        self._enable_capstone_peer_grading()
        config = get_or_create_stage_grading_config(self.stage, self.semester)
        config.peer_rubric = None
        config.save(update_fields=['peer_rubric', 'updated_at'])
        self.client.force_authenticate(user=self.student)

        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            self._peer_eval_payload(self.second_student),
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('rubric', response.data)
        self.assertFalse(PeerEvaluationSubmission.objects.filter(team_grade=grade).exists())

    def test_peer_submit_with_stale_row_appears_on_canonical_grade(self):
        sync_missing_grade_rows(user=self.admin, repair_placeholders=False)
        canonical = TeamGrade.objects.get(team=self.capstone_team, schedule=self.capstone_schedule)
        stale = TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label='Unscheduled',
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
        )
        self.assertNotEqual(stale.pk, canonical.pk)
        self._enable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)

        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.capstone_team.id,
                'evaluateeId': self.second_student.id,
                'breakdown': [
                    {'criteriaName': 'Technical Quality', 'score': 4, 'max': 5},
                ],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)

        canonical.refresh_from_db()
        self.assertEqual(
            PeerEvaluationSubmission.objects.filter(
                team_grade=canonical,
                evaluator=self.student,
                evaluatee=self.second_student,
            ).count(),
            1,
        )
        self.assertFalse(PeerEvaluationSubmission.objects.filter(team_grade=stale).exists())
        self.assertFalse(
            StudentPeerGrade.objects.filter(team_grade=canonical).exists(),
        )
        self.assertIsNone(canonical.peer_score)

        self.client.force_authenticate(user=self.admin)
        list_response = self.client.get('/api/grading/grades/')
        grade_data = next(
            g for g in list_response.data['grades'] if g['id'] == canonical.id
        )
        self.assertFalse(grade_data['peer_eval_complete'])
        self.assertIsNone(grade_data['peer_score'])

        self.client.force_authenticate(user=self.student)
        dashboard = self.client.get('/api/dashboards/student/')
        submissions = dashboard.data['myPeerSubmissions']
        self.assertEqual(len(submissions), 1)
        self.assertEqual(submissions[0]['evaluateeName'], 'Maria Santos')
        self.assertEqual(submissions[0]['breakdown'][0]['criteriaName'], 'Technical Quality')

    def test_stale_peer_submissions_merge_and_sync_on_cleanup(self):
        sync_missing_grade_rows(user=self.admin, repair_placeholders=False)
        canonical = TeamGrade.objects.get(team=self.capstone_team, schedule=self.capstone_schedule)
        stale = TeamGrade.objects.create(
            team=self.capstone_team,
            semester=self.semester,
            scope=TeamGrade.SCOPE_CAPSTONE,
            stage_label='Unscheduled',
            panel_weight=50,
            adviser_weight=30,
            peer_weight=20,
        )
        PeerEvaluationSubmission.objects.create(
            team_grade=stale,
            evaluator=self.student,
            evaluatee=self.second_student,
            total_score=Decimal('4.00'),
            max_score=Decimal('5.00'),
            breakdown=[{'criteriaName': 'Technical Quality', 'score': 4, 'max': 5}],
        )

        sync_missing_grade_rows(user=self.admin)

        canonical.refresh_from_db()
        self.assertEqual(
            PeerEvaluationSubmission.objects.filter(team_grade=canonical).count(),
            1,
        )
        self.assertFalse(TeamGrade.objects.filter(pk=stale.pk).exists())
        self.assertFalse(
            StudentPeerGrade.objects.filter(team_grade=canonical).exists(),
        )
        self.assertIsNone(canonical.peer_score)
