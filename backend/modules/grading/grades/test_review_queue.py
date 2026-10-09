from decimal import Decimal

from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam, TeamStageProgress
from student_teams.services import get_ready_teams
from . import tests as fixtures
from .correction_models import GradeCorrection
from .models import (
    GradeAttemptHistory, GradeBreakdown, PanelistCriterionScore,
    PanelistGradeSubmission, PeerEvaluationSubmission, TeamGrade,
)
from .services import GradeContextService, grade_review_queryset, group_settings_key


class GradeReviewQueueTests(APITestCase):
    setUp = fixtures.GradeCenterApiTests.setUp
    _rubric = fixtures.GradeCenterApiTests._rubric

    def grade(self):
        return GradeContextService.get_or_create_for_schedule(self.capstone_schedule)[0]

    def assert_empty_review_queue(self):
        response = self.client.get('/api/grading/grades/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['grades'], [])
        self.assertEqual(response.data['counts']['filtered'], 0)
        self.assertEqual(response.data['counts']['total_capstone'], 0)
        settings = response.data['group_settings'][group_settings_key('capstone', self.stage.label)]
        self.assertEqual(settings['grading_total_team_count'], 0)
        readiness = self.client.get('/api/grading/grades/group-settings/', {
            'scope': 'capstone', 'stage_label': self.stage.label,
        })
        self.assertEqual(readiness.status_code, 200, readiness.data)
        self.assertEqual(readiness.data['grading_total_team_count'], 0)
        self.assertEqual(readiness.data['incomplete_teams'], [])
        self.assertEqual(readiness.data['cohort_teams'], [])
        self.assertFalse(readiness.data['can_complete'])
        dashboard = self.client.get('/api/dashboards/admin/')
        self.assertEqual(dashboard.status_code, 200, dashboard.data)
        self.assertNotIn('pending_grades', {item['id'] for item in dashboard.data['action_items']})

    def test_deleting_empty_schedule_returns_team_to_ready_and_clears_grade_review(self):
        grade = self.grade()
        self.assertEqual(grade.student_grades.count(), 2)
        self.assertIn(grade.pk, {row['id'] for row in self.client.get('/api/grading/grades/').data['grades']})

        response = self.client.delete(f'/api/defense/schedules/{self.capstone_schedule.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        grade.refresh_from_db()
        self.assertIsNone(grade.schedule_id)
        progress = TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage)
        self.assertEqual(progress.status, TeamStageProgress.STATUS_READY)
        self.capstone_team.refresh_from_db()
        self.assertEqual(self.capstone_team.ready_for_stage, self.stage.label)
        self.assertIn(self.capstone_team, get_ready_teams(self.semester, self.stage))
        self.assert_empty_review_queue()

        dashboard = self.client.get('/api/dashboards/admin/').data
        ready_item = next(item for item in dashboard['action_items'] if item['id'] == 'unscheduled_ready_teams')
        self.assertIn('1 Capstone Team Ready for Defense', ready_item['title'])
        # Explicit sync may retain/recreate placeholders; they must stay out of review.
        sync = self.client.post('/api/grading/grades/sync/', {}, format='json')
        self.assertEqual(sync.status_code, 200, sync.data)
        self.assertEqual(sync.data['grades'], [])
        self.assertTrue(TeamGrade.objects.filter(pk=grade.pk).exists())
        self.assert_empty_review_queue()

        complete = self.client.patch('/api/grading/grades/group-settings/', {
            'scope': 'capstone', 'stage_label': self.stage.label, 'is_officially_complete': True,
        }, format='json')
        self.assertEqual(complete.status_code, 400, complete.data)
        self.assertIn('ready for scheduling', str(complete.data))

        schedule = DefenseSchedule.objects.create(
            scope='capstone', semester=self.semester, team=self.capstone_team,
            defense_stage=self.stage, rubric=self.panel_rubric,
            scheduled_date='2099-05-15', start_time='08:00', room='Room 301',
            created_by=self.admin,
        )
        rebound, created, _ = GradeContextService.get_or_create_for_schedule(schedule)
        self.assertFalse(created)
        self.assertEqual(rebound.pk, grade.pk)
        self.assertEqual(rebound.schedule_id, schedule.pk)
        progress.refresh_from_db()
        self.assertEqual(progress.status, TeamStageProgress.STATUS_SCHEDULED)
        grades = self.client.get('/api/grading/grades/').data
        self.assertEqual([row['id'] for row in grades['grades']], [grade.pk])
        settings = grades['group_settings'][group_settings_key('capstone', self.stage.label)]
        self.assertEqual(settings['grading_total_team_count'], 1)
        dashboard = self.client.get('/api/dashboards/admin/').data
        self.assertIn('pending_grades', {item['id'] for item in dashboard['action_items']})

    def test_deletion_preserves_published_grades_from_previous_stage(self):
        previous = TeamGrade.objects.create(
            team=self.capstone_team, semester=self.semester, scope='capstone',
            defense_stage=DefenseStage.objects.get(label='Concept Proposal'),
            panel_score=90, adviser_score=90, peer_score=90,
            verdict=TeamGrade.VERDICT_APPROVED, status=TeamGrade.STATUS_PUBLISHED,
        )
        grade = self.grade()
        response = self.client.delete(f'/api/defense/schedules/{self.capstone_schedule.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        grades = self.client.get('/api/grading/grades/').data
        self.assertEqual([row['id'] for row in grades['grades']], [previous.pk])
        previous.refresh_from_db()
        self.assertEqual(previous.status, TeamGrade.STATUS_PUBLISHED)
        self.assertEqual(previous.final_grade, Decimal('90.00'))
        self.assertTrue(TeamGrade.objects.filter(pk=grade.pk, schedule__isnull=True).exists())

    def test_ready_unscheduled_team_prevents_closing_an_otherwise_graded_stage(self):
        grade = self.grade()
        submission = PanelistGradeSubmission.objects.create(
            team_grade=grade, schedule=self.capstone_schedule, panelist=self.panelist,
        )
        criterion = self.panel_rubric.criteria.get()
        PanelistCriterionScore.objects.create(
            submission=submission, criterion=criterion, score=9,
            criterion_name_snapshot=criterion.name, max_score_snapshot=criterion.max_score,
        )
        grade.panel_score = grade.adviser_score = grade.peer_score = Decimal('90')
        grade.verdict = TeamGrade.VERDICT_APPROVED
        grade.save()
        ready_team = StudentTeam.objects.create(
            name='Team Awaiting Scheduling', project_title='Next Proposal',
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year',
            semester=self.semester, leader=self.second_student, adviser=self.adviser,
            ready_for_stage=self.stage.label,
        )
        GradeContextService.get_or_create_unscheduled_team(ready_team)
        response = self.client.get('/api/grading/grades/group-settings/', {
            'scope': 'capstone', 'stage_label': self.stage.label,
        })
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['grading_total_team_count'], 1)
        self.assertEqual(response.data['grading_ready_team_count'], 1)
        self.assertFalse(response.data['can_complete'])
        complete = self.client.patch('/api/grading/grades/group-settings/', {
            'scope': 'capstone', 'stage_label': self.stage.label, 'is_officially_complete': True,
        }, format='json')
        self.assertEqual(complete.status_code, 400, complete.data)
        self.assertIn('ready for scheduling', str(complete.data))

    def test_unscheduled_recorded_scores_and_verdicts_stay_visible(self):
        grade = self.grade()
        TeamGrade.objects.filter(pk=grade.pk).update(schedule=None)
        for field, value, empty in (
            ('panel_score', Decimal('0'), None),
            ('adviser_score', Decimal('0'), None),
            ('peer_score', Decimal('0'), None),
            ('final_grade', Decimal('0'), None),
            ('verdict', TeamGrade.VERDICT_FOR_REDEFENSE, ''),
            ('verdict_remarks', 'Recorded chair remarks', ''),
            ('status', TeamGrade.STATUS_PUBLISHED, TeamGrade.STATUS_PENDING),
        ):
            with self.subTest(field=field):
                # Keep legacy evidence intact without recalculating it for this query test.
                TeamGrade.objects.filter(pk=grade.pk).update(**{field: value})
                self.assertTrue(grade_review_queryset(TeamGrade.objects.filter(pk=grade.pk)).exists())
                TeamGrade.objects.filter(pk=grade.pk).update(**{field: empty})
        self.assertFalse(grade_review_queryset(TeamGrade.objects.filter(pk=grade.pk)).exists())
        student_grade = grade.student_grades.first()
        student_grade.adviser_score = Decimal('0')
        student_grade.save()
        response = self.client.get('/api/grading/grades/')
        self.assertEqual([row['id'] for row in response.data['grades']], [grade.pk])
        settings = response.data['group_settings'][group_settings_key('capstone', self.stage.label)]
        self.assertEqual(settings['grading_total_team_count'], 1)

    def test_unscheduled_evaluation_and_history_records_stay_visible_without_duplicate_counts(self):
        grade = self.grade()
        TeamGrade.objects.filter(pk=grade.pk).update(schedule=None)
        records = [
            lambda: GradeBreakdown.objects.create(team_grade=grade, evaluation_type='adviser',
                criterion_name='Recorded criterion', score=0, max_score=10),
            lambda: PeerEvaluationSubmission.objects.create(team_grade=grade,
                evaluator=self.student, evaluatee=self.second_student, total_score=0, max_score=5),
            lambda: GradeAttemptHistory.objects.create(team_grade=grade, attempt_number=1,
                panel_weight=50, adviser_weight=30, peer_weight=20),
            lambda: GradeCorrection.objects.create(grade=grade, requested_by=self.admin,
                reason='Recorded correction review', changes={}, before={}),
        ]
        for create_record in records:
            record = create_record()
            with self.subTest(model=type(record).__name__):
                self.assertTrue(grade_review_queryset(TeamGrade.objects.filter(pk=grade.pk)).exists())
                record.delete()
                self.assertFalse(grade_review_queryset(TeamGrade.objects.filter(pk=grade.pk)).exists())
        for index in range(2):
            GradeBreakdown.objects.create(team_grade=grade, evaluation_type='adviser',
                criterion_name=f'Criterion {index}', score=0, max_score=10)
        response = self.client.get('/api/grading/grades/')
        self.assertEqual([row['id'] for row in response.data['grades']], [grade.pk])
        self.assertEqual(response.data['counts']['filtered'], 1)
        dashboard = self.client.get('/api/dashboards/admin/').data
        pending = next(item for item in dashboard['action_items'] if item['id'] == 'pending_grades')
        self.assertIn('1 Unpublished Capstone Defense Grade', pending['title'])

    def test_empty_pit_placeholder_is_excluded_from_grade_review_and_readiness(self):
        self.semester.is_active = False
        self.semester.save(update_fields=['is_active'])
        self.first_semester.is_active = True
        self.first_semester.save(update_fields=['is_active'])
        PitEventGradingConfig.objects.create(semester=self.first_semester, event_name='PIT Expo')
        grade = GradeContextService.get_or_create_for_schedule(self.pit_schedule)[0]
        response = self.client.delete(f'/api/defense/schedules/{self.pit_schedule.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.client.force_authenticate(user=self.pit_lead)
        response = self.client.get('/api/grading/grades/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['grades'], [])
        dashboard = self.client.get('/api/dashboards/faculty/')
        self.assertEqual(dashboard.status_code, 200, dashboard.data)
        self.assertEqual(dashboard.data['pit_lead_overview']['stats']['pending_grades'], 0)
        readiness = self.client.get('/api/grading/grades/group-settings/', {
            'scope': 'pit', 'stage_label': 'PIT Expo',
        })
        self.assertEqual(readiness.status_code, 200, readiness.data)
        self.assertEqual(readiness.data['grading_total_team_count'], 0)
        self.assertFalse(readiness.data['can_complete'])
        self.assertTrue(TeamGrade.objects.filter(pk=grade.pk, schedule__isnull=True).exists())
