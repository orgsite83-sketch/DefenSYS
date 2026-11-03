"""The queue, dashboard, and scheduler agree after a panel assessment."""
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import Semester
from grading.grades.models import TeamGrade
from grading.grades.services import GradeContextService
from student_teams.models import TeamStageProgress
from . import tests as fixtures
from .models import DefenseSchedule, SchedulePanelist
from .serializers import ScheduleTeamSerializer
from .capstone_planning import team_stage_readiness


class TeamReadinessLifecycleTests(APITestCase):
    _complete_prior_stages = fixtures.DefenseSchedulerApiTests._complete_prior_stages

    def setUp(self):
        fixtures.DefenseSchedulerApiTests.setUp(self)
        self.schedule = fixtures.DefenseSchedulerApiTests.create_scheduled_defense(self)
        SchedulePanelist.objects.filter(schedule=self.schedule, panelist=self.panelist).update(is_chair=True)

    def submit_panel(self):
        for panelist in (self.panelist, self.second_panelist):
            self.client.force_authenticate(user=panelist)
            response = self.client.post('/api/defense/schedules/submit-grades/', {
                'team_id': self.team.pk,
                'schedule_id': self.schedule.pk,
                'criteria_scores': fixtures.DefenseSchedulerApiTests.criteria_scores(self, 8),
            }, format='json')
            self.assertEqual(response.status_code, 201, response.data)

    def verdict(self, value, **extra):
        self.client.force_authenticate(user=self.panelist)
        response = self.client.patch(f'/api/defense/schedules/{self.schedule.pk}/verdict/', {
            'verdict': value, 'verdict_remarks': 'Recorded assessment outcome.', **extra,
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)

    def assert_readiness(self, status, eligible=False, verdict=''):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/api/defense/schedules/')
        self.assertEqual(response.status_code, 200, response.data)
        team = next(team for team in response.data['teams'] if team['id'] == self.team.pk)
        self.assertEqual(team['stage_progress'][self.stage.label], status)
        self.assertEqual(team['stage_verdicts'].get(self.stage.label, ''), verdict)
        self.assertEqual(self.stage.label in team['eligible_stages'], eligible)
        self.assertEqual(team['ready_for_stage'], self.stage.label if eligible else None)
        dashboard = self.client.get('/api/dashboards/admin/')
        self.assertEqual(dashboard.status_code, 200, dashboard.data)
        self.assertEqual(dashboard.data['team_pipeline']['ready_for_defense'], int(eligible))
        items = [item for item in dashboard.data['action_items'] if item['id'] == 'unscheduled_ready_teams']
        self.assertEqual(bool(items), eligible)

    def assert_scheduler_readiness(self, status, *, visible=True, eligible=False):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext
        with CaptureQueriesContext(connection) as queries:
            state = team_stage_readiness(self.team, self.stage)
        self.assertFalse(any(q['sql'].lstrip().split()[0].upper() in {'INSERT', 'UPDATE', 'DELETE'} for q in queries))
        self.assertEqual(state['status'], status)
        self.assertEqual(state['include_in_scheduler'], visible)
        self.assertEqual(state['can_schedule'], eligible)
        serialized = ScheduleTeamSerializer(self.team).data['stage_readiness'][str(self.stage.pk)]
        self.assertEqual(serialized, state)
        return state

    def test_all_panel_scores_await_verdict_instead_of_becoming_ready(self):
        self.submit_panel()
        self.assert_readiness('awaiting_verdict')

    def test_booked_first_hearing_is_omitted_from_scheduler_readiness(self):
        self.assert_scheduler_readiness('scheduled', visible=False)

    def test_approved_attempt_waits_for_grading_then_becomes_completed(self):
        self.submit_panel()
        self.verdict('approved')
        self.team.refresh_from_db()
        # Historical endorsement remains stored, but cannot re-enter scheduling.
        self.assertEqual(self.team.ready_for_stage, self.stage.label)
        self.assert_readiness('grading_incomplete', verdict='approved')
        self.assert_scheduler_readiness('approved', visible=False)
        grade = TeamGrade.objects.get(schedule=self.schedule)
        grade.adviser_score = 80
        grade.peer_score = 80
        grade.peer_score_is_override = True
        grade.save()
        self.assert_readiness('awaiting_completion', verdict='approved')
        self.assert_scheduler_readiness('approved', visible=False)
        response = self.client.patch('/api/grading/grades/group-settings/', {
            'scope': 'capstone', 'defense_stage_id': self.stage.pk,
            'is_officially_complete': True,
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_readiness('completed', verdict='approved')
        self.assert_scheduler_readiness('approved', visible=False)

    def test_revisions_do_not_reenter_the_ready_queue(self):
        self.submit_panel()
        self.verdict('approved_with_revisions')
        self.assert_readiness('revisions_pending', verdict='approved_with_revisions')
        self.assert_scheduler_readiness('approved', visible=False)

    def test_redefense_eligibility_respects_verification_and_new_attempt(self):
        self.submit_panel()
        self.verdict('for_redefense', redefense_verification_required=True)
        self.assert_readiness('redefense_required', verdict='for_redefense')
        self.assert_scheduler_readiness('preparing_redefense')
        grade = TeamGrade.objects.get(schedule=self.schedule)
        grade.redefense_verified_at = timezone.now()
        grade.save()
        self.assert_readiness('redefense_required', eligible=True, verdict='for_redefense')
        self.assert_scheduler_readiness('ready_for_redefense', eligible=True)
        second = fixtures.DefenseSchedulerApiTests.create_scheduled_defense(self)
        GradeContextService.get_or_create_for_schedule(second)
        self.assert_readiness('awaiting_evaluation')
        self.assert_scheduler_readiness('scheduled', visible=False)

    def test_approved_team_awaiting_post_defense_is_hidden_only_for_its_passed_stage(self):
        from defense.stages.models import StageDeliverable
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='SCHEDULER_FINAL',
            label='Final paper', deliverable_type='post', required=True)
        capture_participation(self.team, requirements=configured_requirements())
        self.submit_panel()
        self.verdict('approved')
        self.assert_readiness('pending_post_defense', verdict='approved')
        self.assert_scheduler_readiness('approved', visible=False)
        response = self.client.get('/api/defense/schedules/capstone-workspace/')
        self.assertEqual(response.status_code, 200, response.data)
        row = next(row for row in response.data['teams'] if row['id'] == self.team.pk)
        self.assertFalse(row['stage_readiness'][str(self.stage.pk)]['include_in_scheduler'])
        self.assertNotIn(self.stage.pk, row['ready_stage_ids'])
        next_stage = self.stage.__class__.objects.filter(display_order__gt=self.stage.display_order).first()
        next_state = team_stage_readiness(self.team, next_stage)
        self.assertTrue(next_state['include_in_scheduler'])
        self.assertFalse(next_state['can_schedule'])

    def test_assessed_scheduled_flag_does_not_mask_redefense_preparation_or_write_on_get(self):
        self.submit_panel()
        self.verdict('for_redefense', redefense_verification_required=True)
        DefenseSchedule.objects.filter(pk=self.schedule.pk).update(status='scheduled')
        state = self.assert_scheduler_readiness('preparing_redefense')
        self.assertEqual(state['label'], 'Preparing re-defense')
        self.schedule.refresh_from_db()
        self.assertEqual(self.schedule.status, 'scheduled')

    def test_progress_and_schedules_from_old_project_and_term_are_ignored(self):
        TeamStageProgress.objects.filter(team=self.team).update(status=TeamStageProgress.STATUS_PASSED)
        self.team.project_version += 1
        self.team.ready_for_stage = None
        self.team.save(update_fields=['project_version', 'ready_for_stage'])
        data = ScheduleTeamSerializer(self.team).data
        self.assertEqual(data['completed_stages'], [])
        self.assertEqual(data['scheduled_stages'], [])
        self.assertEqual(data['stage_progress'], {})
        self.assertEqual(data['stage_verdicts'], {})
        self.assert_scheduler_readiness('awaiting_endorsement')
        TeamStageProgress.all_objects.filter(team=self.team).update(project_version=self.team.project_version)
        # Prefetching stage progress must still respect the team's current term.
        self.team.semester = Semester.objects.create(school_year=self.school_year, label=Semester.FIRST)
        data = ScheduleTeamSerializer(self.team).data
        self.assertEqual(data['completed_stages'], [])
        self.assertEqual(data['scheduled_stages'], [])
        self.assertEqual(data['stage_progress'], {})
        self.assertEqual(data['stage_verdicts'], {})

    def test_failed_verdict_is_visible_and_stays_out_of_scheduling(self):
        self.submit_panel()
        self.verdict('failed')
        self.assert_readiness('failed', verdict='failed')

    def test_rejected_verdict_is_visible_and_stays_out_of_scheduling(self):
        self.submit_panel()
        self.verdict('project_rejected')
        self.assert_readiness('project_rejected', verdict='project_rejected')
