"""PIT access defaults persist; each team's defense gates actual peer grading."""
from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig, SchedulePanelist
from defense.scheduler.pit_config import upsert_pit_event_config
from grading.rubrics.models import Rubric, RubricCriterion
from student_teams.models import StudentTeam, TeamMembership
from user_management.models import GuestPanelistCode
from .availability import peer_grading_unavailable_reason
from .models import PanelistCriterionScore, PanelistGradeSubmission, PeerEvaluationSubmission
from .services import GradeContextService, submit_panelist_grade


class PitPeerAvailabilityTests(APITestCase):
    def setUp(self):
        user = get_user_model()
        self.lead = user.objects.create_user(username='pit-access-lead', role='faculty',
                                             is_pit_lead=True, pit_lead_year='2nd Year')
        self.student = user.objects.create_user(username='pit-access-student', role='student')
        self.teammate = user.objects.create_user(username='pit-access-teammate', role='student')
        self.panelists = [user.objects.create_user(username=f'pit-access-panel-{i}', role='faculty',
                                                   is_panelist=True) for i in range(2)]
        self.semester = Semester.objects.create(
            school_year=SchoolYear.objects.create(label='2097-2098'), label=Semester.FIRST, is_active=True)
        self.team = StudentTeam.objects.create(name='Peer access team', semester=self.semester,
            leader=self.student, level=StudentTeam.LEVEL_2_PIT, year_level='2nd Year')
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        TeamMembership.objects.create(team=self.team, student=self.teammate)
        self.panel = self.rubric('Panel', 'panel')
        self.peer = self.rubric('Peer', 'peer')
        self.event = upsert_pit_event_config(semester=self.semester, event_name='Peer access event',
            year_level='2nd Year', panel_rubric=self.panel, peer_rubric=self.peer, user=self.lead)
        self.team.current_defense_stage = self.event.event_name
        self.team.save(update_fields=['current_defense_stage'])
        self.schedule = DefenseSchedule.objects.create(scope='pit', team=self.team, semester=self.semester,
            event_name=self.event.event_name, rubric=self.panel, scheduled_date=timezone.localdate(),
            start_time='08:00', room='Peer Access Lab')
        for panelist in self.panelists:
            SchedulePanelist.objects.create(schedule=self.schedule, panelist=panelist)
        self.grade = GradeContextService.get_or_create_for_schedule(self.schedule)[0]

    def rubric(self, name, kind):
        rubric = Rubric.objects.create(name=name, scope='pit', semester=self.semester,
            evaluation_type=kind, status='published', created_by=self.lead)
        RubricCriterion.objects.create(rubric=rubric, name='Contribution', max_score=10, weight=100)
        return rubric

    def panel_grade(self, index):
        submit_panelist_grade(self.schedule, self.grade,
            [{'criterion_id': self.panel.criteria.get().pk, 'score': 8}], panelist=self.panelists[index])
        self.grade.refresh_from_db()

    def finish_panel(self):
        for i in range(len(self.panelists)):
            self.panel_grade(i)

    def submit_peer(self):
        self.client.force_authenticate(self.student)
        return self.client.post('/api/grading/grades/peer-evaluations/', {
            'teamId': self.team.pk, 'evaluateeId': self.teammate.pk, 'stage': self.event.event_name,
            'breakdown': [{'criterion_id': self.peer.criteria.get().pk,
                           'criteriaName': 'Contribution', 'score': 8, 'max': 10}],
        }, format='json')

    def assert_closed(self):
        self.assertTrue(peer_grading_unavailable_reason(self.grade))
        response = self.submit_peer()
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(PeerEvaluationSubmission.objects.filter(team_grade=self.grade).exists())

    def test_default_stays_enabled_without_rubric_and_after_attaching_it(self):
        self.client.force_authenticate(self.lead)
        response = self.client.post('/api/defense/schedules/pit-event-config/', {
            'event_name': 'Attach later', 'semester_id': self.semester.pk,
            'panel_weight': 80, 'peer_weight': 20,
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['config']['peer_grading_enabled'])
        event_id = response.data['config']['id']
        created = self.client.post('/api/grading/rubrics/', {
            'name': 'Attached peer rubric', 'scope': 'pit', 'semester_id': self.semester.pk,
            'evaluation_type': 'peer', 'status': 'published', 'pit_event_id': event_id,
            'criteria': [{'name': 'Contribution', 'max_score': 10, 'weight': 100}],
        }, format='json')
        self.assertEqual(created.status_code, 201, created.data)
        event = PitEventGradingConfig.objects.get(pk=event_id)
        self.assertEqual(event.peer_rubric_id, created.data['rubric']['id'])
        self.assertTrue(event.peer_grading_enabled)
        reloaded = self.client.get('/api/defense/schedules/pit-event-config/', {'event_name': 'Attach later'})
        self.assertTrue(reloaded.data['config']['peer_grading_enabled'])

    def test_explicit_closure_is_preserved_when_peer_rubric_is_attached(self):
        event = upsert_pit_event_config(semester=self.semester, event_name='Explicitly closed',
            year_level='2nd Year', peer_grading_enabled=False, user=self.lead)
        peer = self.rubric('Closed event peer', 'peer')
        updated = upsert_pit_event_config(semester=self.semester, event_name=event.event_name,
            year_level='2nd Year', peer_rubric=peer, user=self.lead)
        self.assertFalse(updated.peer_grading_enabled)

    def test_model_default_matches_new_event_access_policy(self):
        event = PitEventGradingConfig.objects.create(semester=self.semester,
            event_name='Model default', year_level='2nd Year')
        self.assertTrue(event.peer_grading_enabled)

    def test_scheduling_and_partial_panel_score_do_not_open_grading(self):
        self.assertTrue(self.event.peer_grading_enabled)
        self.assert_closed()
        self.panel_grade(0)
        self.assertIsNotNone(self.grade.panel_score)
        self.assert_closed()
        self.panel_grade(1)
        self.assertEqual(peer_grading_unavailable_reason(self.grade), '')
        self.assertEqual(self.submit_peer().status_code, 200)

    def test_dashboard_and_stage_payload_follow_finished_defense(self):
        from repository.deliverables.services import stage_payload
        self.client.force_authenticate(self.student)
        before = self.client.get('/api/dashboards/student/')
        self.assertFalse(before.data['peerEvalEnabled'])
        self.assertEqual(before.data['peerCriteria'], [])
        self.assertFalse(stage_payload(self.team, self.event.event_name, evaluator=self.student)['peer_eval_allowed'])
        self.finish_panel()
        after = self.client.get('/api/dashboards/student/')
        self.assertTrue(after.data['peerEvalEnabled'])
        self.assertTrue(after.data['peerCriteria'])
        self.assertTrue(stage_payload(self.team, self.event.event_name, evaluator=self.student)['peer_eval_allowed'])

    def test_missing_schedule_stays_closed(self):
        self.schedule.delete()
        self.grade.refresh_from_db()
        self.assert_closed()

    def test_future_defense_stays_closed_even_with_recorded_panel_scores(self):
        self.finish_panel()
        self.schedule.scheduled_date = timezone.localdate() + timedelta(days=1)
        self.schedule.save(update_fields=['scheduled_date'])
        self.grade.refresh_from_db()
        self.assert_closed()

    def test_closed_cancelled_archived_and_paused_contexts_remain_closed(self):
        self.finish_panel()
        for status, operation in [('cancelled', 'normal'), ('archived', 'normal'), ('scheduled', 'paused')]:
            with self.subTest(status=status, operation=operation):
                self.schedule.status, self.schedule.operation_state = status, operation
                self.schedule.save(update_fields=['status', 'operation_state'])
                self.grade.refresh_from_db()
                self.assert_closed()
        self.schedule.status, self.schedule.operation_state = 'scheduled', 'normal'
        self.schedule.save(update_fields=['status', 'operation_state'])
        self.event.peer_grading_enabled = False
        self.event.save(update_fields=['peer_grading_enabled'])
        self.grade.refresh_from_db()
        self.assert_closed()

    def test_historical_term_and_previous_project_remain_read_only(self):
        self.finish_panel()
        self.semester.is_active = False
        self.semester.save(update_fields=['is_active'])
        self.grade.refresh_from_db()
        self.assert_closed()
        self.semester.is_active = True
        self.semester.save(update_fields=['is_active'])
        self.team.project_version += 1
        self.team.save(update_fields=['project_version'])
        self.grade.refresh_from_db()
        self.assert_closed()

    def test_done_status_does_not_bypass_missing_panel_assessments(self):
        self.schedule.status = DefenseSchedule.STATUS_DONE
        self.schedule.save(update_fields=['status'])
        self.grade.refresh_from_db()
        self.assert_closed()

    def test_external_panelist_must_finish_too(self):
        guest = GuestPanelistCode.objects.create(guest_name='Peer access guest', defense_schedule=self.schedule)
        guest.schedules.add(self.schedule)
        self.finish_panel()
        self.assert_closed()
        submission = PanelistGradeSubmission.objects.create(team_grade=self.grade, schedule=self.schedule,
            guest_code_id=str(guest.pk), guest_name=guest.guest_name)
        criterion = self.panel.criteria.get()
        PanelistCriterionScore.objects.create(submission=submission, criterion=criterion,
            criterion_name_snapshot=criterion.name, score=8, max_score_snapshot=10, weight_snapshot=100)
        self.assertEqual(peer_grading_unavailable_reason(self.grade), '')
        self.assertEqual(self.submit_peer().status_code, 200)

    def test_new_attempt_cannot_use_previous_panels_to_open_peer_grading(self):
        self.finish_panel()
        replacement = DefenseSchedule.objects.create(scope='pit', team=self.team, semester=self.semester,
            event_name=self.event.event_name, rubric=self.panel, scheduled_date=timezone.localdate(),
            start_time='11:00', room='Peer Access Lab')
        SchedulePanelist.objects.create(schedule=replacement, panelist=self.panelists[0])
        self.grade = GradeContextService.get_or_create_for_schedule(replacement)[0]
        self.assert_closed()

    def test_last_panel_refreshes_only_the_team_after_commit(self):
        with patch('realtime.broadcast.notify_team_peer_open') as notify:
            with self.captureOnCommitCallbacks(execute=True):
                self.panel_grade(0)
            notify.assert_not_called()
            with self.captureOnCommitCallbacks(execute=True):
                self.panel_grade(1)
            notify.assert_called_once()
            self.assertEqual(notify.call_args.kwargs['scope'], 'pit')
            self.assertEqual(set(notify.call_args.kwargs['student_ids']), {self.student.pk, self.teammate.pk})
