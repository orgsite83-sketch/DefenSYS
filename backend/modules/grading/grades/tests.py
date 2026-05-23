from decimal import Decimal

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig, SchedulePanelist
from defense.stages.grading_config import get_or_create_stage_grading_config
from defense.stages.models import DefenseStage
from grading.rubrics.models import Rubric, RubricCriterion
from student_teams.models import StudentTeam, TeamMembership
from .models import GradeBreakdown, PeerEvaluationSubmission, StudentPeerGrade, TeamGrade
from .services import sync_missing_grade_rows, _sync_unscheduled_team


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
        self.client.get('/api/grading/grades/')
        return TeamGrade.objects.get(team=self.capstone_team)

    def _enable_capstone_peer_grading(self):
        self.semester.capstone_peer_evaluation_enabled = True
        self.semester.save(update_fields=['capstone_peer_evaluation_enabled'])

    def _disable_capstone_peer_grading(self):
        self.semester.capstone_peer_evaluation_enabled = False
        self.semester.save(update_fields=['capstone_peer_evaluation_enabled'])

    def test_list_syncs_schedules_into_grade_rows(self):
        response = self.client.get('/api/grading/grades/', {'scope': 'capstone'})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['counts']['filtered'], 1)
        self.assertEqual(response.data['grades'][0]['team_name'], 'Team VaultSync')
        self.assertEqual(response.data['grades'][0]['weights']['panel'], 50)
        self.assertEqual(TeamGrade.objects.count(), 2)

    def test_admin_default_scope_is_capstone_when_param_omitted(self):
        self.client.get('/api/grading/grades/')

        response = self.client.get('/api/grading/grades/')

        self.assertEqual(response.status_code, 200)
        scopes = {grade['scope'] for grade in response.data['grades']}
        self.assertEqual(scopes, {TeamGrade.SCOPE_CAPSTONE})

    def test_admin_scope_pit_returns_only_pit(self):
        response = self.client.get('/api/grading/grades/', {'scope': 'pit'})

        self.assertEqual(response.status_code, 200)
        self.assertGreaterEqual(response.data['counts']['filtered'], 1)
        self.assertTrue(
            all(grade['scope'] == TeamGrade.SCOPE_PIT for grade in response.data['grades']),
        )

    def test_admin_scope_all_returns_capstone_and_pit(self):
        self.client.get('/api/grading/grades/')

        response = self.client.get('/api/grading/grades/', {'scope': 'all'})

        self.assertEqual(response.status_code, 200)
        scopes = {grade['scope'] for grade in response.data['grades']}
        self.assertIn(TeamGrade.SCOPE_CAPSTONE, scopes)
        self.assertIn(TeamGrade.SCOPE_PIT, scopes)

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
        self.assertIsNone(grade.schedule_id)

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

    def test_pit_lead_scope_only_returns_assigned_pit_year(self):
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
        self.client.get('/api/grading/grades/')
        response = self.client.get('/api/grading/grades/')

        self.assertEqual(response.status_code, 200)
        self.assertIn('group_settings', response.data)
        capstone_key = f'capstone|{self.stage.label}'
        self.assertIn(capstone_key, response.data['group_settings'])

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
        self.assertEqual(grade.status, TeamGrade.STATUS_READY_FOR_ARCHIVE)
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
        self._enable_capstone_peer_grading()
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '100.00', 'adviser_score': '100.00', 'peer_score': '85.80'},
            format='json',
        )
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
        self.assertEqual(grade.status, TeamGrade.STATUS_READY_FOR_ARCHIVE)
        self.assertEqual(self.capstone_team.status, StudentTeam.STATUS_APPROVED)

    def test_capstone_official_complete_skips_below_threshold(self):
        grade = self._capstone_grade()
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

    def test_capstone_list_repairs_pending_passed_when_stage_complete(self):
        self._enable_capstone_peer_grading()
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '100.00', 'adviser_score': '100.00', 'peer_score': '85.80'},
            format='json',
        )
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
        self.assertEqual(grade.status, TeamGrade.STATUS_READY_FOR_ARCHIVE)

    def test_capstone_peer_sync_auto_finalizes_when_stage_complete(self):
        self._enable_capstone_peer_grading()
        grade = self._capstone_grade()
        self.client.patch(
            f'/api/grading/grades/{grade.id}/',
            {'panel_score': '100.00', 'adviser_score': '100.00'},
            format='json',
        )
        self.client.patch(
            '/api/grading/grades/group-settings/',
            {
                'scope': TeamGrade.SCOPE_CAPSTONE,
                'stage_label': self.stage.label,
                'is_officially_complete': True,
            },
            format='json',
        )
        self.client.force_authenticate(user=self.student)
        response = self.client.post(
            '/api/grading/grades/peer-evaluations/',
            {
                'teamId': self.capstone_team.id,
                'evaluateeName': 'Maria Santos',
                'breakdown': [
                    {'criteriaName': 'Technical Quality', 'score': 4, 'max': 5},
                ],
                'total': '4.00',
                'max': '5.00',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        grade.refresh_from_db()
        self.assertGreaterEqual(grade.final_grade, Decimal('75.00'))
        self.assertEqual(grade.status, TeamGrade.STATUS_READY_FOR_ARCHIVE)

    def test_patch_grade_blocked_when_event_officially_complete(self):
        self._enable_capstone_peer_grading()
        grade = self._capstone_grade()
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
                'evaluateeName': 'Maria Santos',
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
                'evaluateeName': 'Maria Santos',
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
                'evaluateeName': 'Maria Santos',
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
        self.assertTrue(
            StudentPeerGrade.objects.filter(
                team_grade=grade,
                student=self.second_student,
            ).exists()
        )

    def test_adviser_submit_merges_stale_grade_row(self):
        self.client.get('/api/grading/grades/')
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
        self.client.get('/api/grading/grades/')
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

    def test_student_dashboard_includes_peer_criteria(self):
        self._capstone_grade()
        self._enable_capstone_peer_grading()
        self.client.force_authenticate(user=self.student)

        response = self.client.get('/api/dashboards/student/')

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data['peerCriteria'])
        self.assertTrue(response.data['peerEvalEnabled'])

    def test_peer_submit_with_stale_row_appears_on_canonical_grade(self):
        self.client.get('/api/grading/grades/')
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
                'evaluateeName': 'Maria Santos',
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
        self.assertTrue(
            StudentPeerGrade.objects.filter(
                team_grade=canonical,
                student=self.second_student,
            ).exists()
        )

        self.client.force_authenticate(user=self.admin)
        list_response = self.client.get('/api/grading/grades/')
        grade_data = next(
            g for g in list_response.data['grades'] if g['id'] == canonical.id
        )
        self.assertTrue(grade_data['peer_per_student'])
        self.assertIsNotNone(grade_data['peer_score'])

        self.client.force_authenticate(user=self.student)
        dashboard = self.client.get('/api/dashboards/student/')
        submissions = dashboard.data['myPeerSubmissions']
        self.assertEqual(len(submissions), 1)
        self.assertEqual(submissions[0]['evaluateeName'], 'Maria Santos')
        self.assertEqual(submissions[0]['breakdown'][0]['criteriaName'], 'Technical Quality')

    def test_stale_peer_submissions_merge_and_sync_on_cleanup(self):
        self.client.get('/api/grading/grades/')
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
        self.assertTrue(
            StudentPeerGrade.objects.filter(
                team_grade=canonical,
                student=self.second_student,
            ).exists()
        )
        self.assertIsNotNone(canonical.peer_score)
