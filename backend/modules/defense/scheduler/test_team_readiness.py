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

    def test_all_panel_scores_await_verdict_instead_of_becoming_ready(self):
        self.submit_panel()
        self.assert_readiness('awaiting_verdict')

    def test_approved_attempt_waits_for_grading_then_becomes_completed(self):
        self.submit_panel()
        self.verdict('approved')
        self.team.refresh_from_db()
        # Historical endorsement remains stored, but cannot re-enter scheduling.
        self.assertEqual(self.team.ready_for_stage, self.stage.label)
        self.assert_readiness('grading_incomplete', verdict='approved')
        grade = TeamGrade.objects.get(schedule=self.schedule)
        grade.adviser_score = 80
        grade.peer_score = 80
        grade.save()
        self.assert_readiness('awaiting_completion', verdict='approved')
        response = self.client.patch('/api/grading/grades/group-settings/', {
            'scope': 'capstone', 'defense_stage_id': self.stage.pk,
            'is_officially_complete': True,
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assert_readiness('completed', verdict='approved')

    def test_revisions_do_not_reenter_the_ready_queue(self):
        self.submit_panel()
        self.verdict('approved_with_revisions')
        self.assert_readiness('revisions_pending', verdict='approved_with_revisions')

    def test_redefense_eligibility_respects_verification_and_new_attempt(self):
        self.submit_panel()
        self.verdict('for_redefense', redefense_verification_required=True)
        self.assert_readiness('redefense_required', verdict='for_redefense')
        grade = TeamGrade.objects.get(schedule=self.schedule)
        grade.redefense_verified_at = timezone.now()
        grade.save()
        self.assert_readiness('redefense_required', eligible=True, verdict='for_redefense')
        second = fixtures.DefenseSchedulerApiTests.create_scheduled_defense(self)
        GradeContextService.get_or_create_for_schedule(second)
        self.assert_readiness('awaiting_evaluation')

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
