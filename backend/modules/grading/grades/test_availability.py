"""Capstone forms and APIs share endorsement, schedule, and evaluator gates."""
from datetime import timedelta
from decimal import Decimal
from unittest.mock import patch

from django.utils import timezone
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from student_teams.models import TeamStageProgress
from user_management.models import GuestPanelistCode
from . import tests as fixtures
from .availability import adviser_grading_unavailable_reason, peer_grading_unavailable_reason
from .models import PanelistGradeSubmission, PeerEvaluationSubmission, TeamGrade
from .services import GradeContextService, submit_panelist_grade, team_grading_readiness


class EvaluationAvailabilityTests(APITestCase):
    _rubric = fixtures.GradeCenterApiTests._rubric
    _peer_eval_payload = fixtures.GradeCenterApiTests._peer_eval_payload

    def setUp(self):
        fixtures.GradeCenterApiTests.setUp(self)
        self.grade = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)[0]

    def panel(self, panelist=None):
        submit_panelist_grade(self.capstone_schedule, self.grade,
            [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 8}],
            panelist=panelist or self.panelist)
        self.grade.refresh_from_db()

    def peer(self):
        self.client.force_authenticate(user=self.student)
        return self.client.post('/api/grading/grades/peer-evaluations/',
            self._peer_eval_payload(self.second_student), format='json')

    def submit_adviser(self):
        self.client.force_authenticate(user=self.adviser)
        return self.client.post(f'/api/grading/grades/adviser-grades/{self.grade.pk}/submit/', {
            'rubric_id': self.adviser_rubric.pk,
            'team_criteria_scores': [{'criterion_name': 'Technical Quality', 'score': 8, 'max_score': 10}],
        }, format='json')

    def test_unscheduled_peer_cannot_create_grade_or_expose_criteria(self):
        self.capstone_schedule.delete()
        self.grade.delete()
        self.capstone_team.ready_for_stage = None
        self.capstone_team.current_defense_stage = self.stage.label
        self.capstone_team.save(update_fields=['ready_for_stage', 'current_defense_stage'])
        self.assertEqual(self.peer().status_code, 400)
        self.assertFalse(TeamGrade.objects.filter(team=self.capstone_team).exists())
        dashboard = self.client.get('/api/dashboards/student/')
        self.assertFalse(dashboard.data['peerEvalEnabled'])
        self.assertEqual(dashboard.data['peerCriteria'], [])
        self.assertIn('scheduled', dashboard.data['peerEvalUnavailableReason'])

    def test_unscheduled_existing_grade_blocks_both_roles(self):
        self.capstone_schedule.delete()
        self.grade.refresh_from_db()
        self.assertEqual(self.peer().status_code, 400)
        self.assertEqual(self.submit_adviser().status_code, 400)
        self.grade.refresh_from_db()
        self.assertIsNone(self.grade.adviser_score)
        self.assertFalse(PeerEvaluationSubmission.objects.filter(team_grade=self.grade).exists())
        listing = self.client.get('/api/grading/grades/adviser-grades/')
        row = next(g for g in listing.data['grades'] if g['id'] == self.grade.pk)
        self.assertFalse(row['adviser_grading_available'])
        self.assertIn('scheduled', row['adviser_grading_unavailable_reason'])

    def test_unendorsed_schedule_blocks_both_roles(self):
        self.capstone_team.ready_for_stage = None
        self.capstone_team.save(update_fields=['ready_for_stage'])
        TeamStageProgress.objects.filter(team=self.capstone_team, defense_stage=self.stage).delete()
        self.assertEqual(self.peer().status_code, 400)
        self.assertEqual(self.submit_adviser().status_code, 400)

    def test_future_schedule_opens_adviser_but_keeps_peer_locked(self):
        self.capstone_schedule.scheduled_date = timezone.localdate() + timedelta(days=7)
        self.capstone_schedule.save(update_fields=['scheduled_date'])
        self.assertEqual(self.peer().status_code, 400)
        self.assertEqual(self.submit_adviser().status_code, 200)

    def test_partial_panel_score_does_not_open_peer(self):
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=self.adviser)
        self.panel()
        self.assertIsNotNone(self.grade.panel_score)
        self.assertEqual(self.peer().status_code, 400)
        self.panel(self.adviser)
        self.assertEqual(self.peer().status_code, 200)

    def test_missing_external_panelist_keeps_peer_locked(self):
        invitation = GuestPanelistCode.objects.create(guest_name='External Reviewer', defense_schedule=self.capstone_schedule)
        invitation.schedules.add(self.capstone_schedule)
        self.panel()
        self.assertIn('external panelist', peer_grading_unavailable_reason(self.grade))
        self.assertEqual(self.peer().status_code, 400)
        # Completion validates submitted criterion snapshots, including external identities.
        from .models import PanelistCriterionScore
        submission = PanelistGradeSubmission.objects.create(team_grade=self.grade,
            schedule=self.capstone_schedule, guest_code_id=str(invitation.pk), guest_name=invitation.guest_name)
        criterion = self.panel_rubric.criteria.first()
        PanelistCriterionScore.objects.create(submission=submission, criterion=criterion,
            criterion_name_snapshot=criterion.name, score=8, max_score_snapshot=10)
        self.assertEqual(self.peer().status_code, 200)

    def test_panel_completion_opens_dashboard_and_stage_payload(self):
        self.client.force_authenticate(user=self.student)
        before = self.client.get('/api/dashboards/student/')
        self.assertFalse(before.data['peerEvalEnabled'])
        self.panel()
        after = self.client.get('/api/dashboards/student/')
        self.assertTrue(after.data['peerEvalEnabled'])
        self.assertTrue(after.data['peerCriteria'])
        from repository.deliverables.services import stage_payload
        payload = stage_payload(self.capstone_team, self.stage.label, evaluator=self.student)
        self.assertTrue(payload['peer_eval_allowed'])
        self.assertEqual(payload['peer_eval_unavailable_reason'], '')

    def test_peer_open_refresh_is_sent_only_after_commit_and_last_panel(self):
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=self.adviser)
        with patch('realtime.broadcast.notify_team_peer_open') as notify:
            with self.captureOnCommitCallbacks(execute=True):
                self.panel()
            notify.assert_not_called()
            with self.captureOnCommitCallbacks(execute=True):
                self.panel(self.adviser)
            notify.assert_called_once()
            self.assertEqual(set(notify.call_args.kwargs['student_ids']), {self.student.pk, self.second_student.pk})

    def test_done_schedule_still_accepts_remaining_grades(self):
        self.panel()
        self.capstone_schedule.status = DefenseSchedule.STATUS_DONE
        self.capstone_schedule.save(update_fields=['status'])
        self.assertEqual(self.peer().status_code, 200)
        self.assertEqual(self.submit_adviser().status_code, 200)

    def test_repeat_peer_submission_cannot_overwrite_score(self):
        self.panel()
        self.assertEqual(self.peer().status_code, 200)
        submission = PeerEvaluationSubmission.objects.get(team_grade=self.grade)
        original = submission.total_score
        self.assertEqual(self.peer().status_code, 400)
        submission.refresh_from_db()
        self.assertEqual(submission.total_score, original)

    def test_cancelled_archived_and_interrupted_schedules_block_both_roles(self):
        self.panel()
        for state, status in [('normal', 'cancelled'), ('normal', 'archived'), ('paused', 'scheduled'), ('no_show', 'scheduled')]:
            with self.subTest(state=state, status=status):
                self.capstone_schedule.status = status
                self.capstone_schedule.operation_state = state
                self.capstone_schedule.save(update_fields=['status', 'operation_state'])
                self.assertEqual(self.peer().status_code, 400)
                self.assertEqual(self.submit_adviser().status_code, 400)

    def test_closed_form_does_not_remove_required_peer_component(self):
        readiness = team_grading_readiness(self.grade, self.semester, 'capstone')
        self.assertTrue(readiness['peer_required'])
        self.assertFalse(readiness['peer_complete'])
        self.assertIn('peer', readiness['missing_components'])

    def test_cleared_ready_flag_uses_stage_endorsement_history(self):
        TeamStageProgress.objects.update_or_create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, defaults={'status': TeamStageProgress.STATUS_GRADING})
        self.capstone_team.ready_for_stage = None
        self.capstone_team.save(update_fields=['ready_for_stage'])
        self.grade.refresh_from_db()
        self.assertEqual(adviser_grading_unavailable_reason(self.grade), '')
        self.panel()
        self.assertEqual(self.peer().status_code, 200)

    def test_previous_term_and_project_are_read_only(self):
        self.semester.is_active = False
        self.semester.save(update_fields=['is_active'])
        self.assertEqual(self.peer().status_code, 400)
        self.assertEqual(self.submit_adviser().status_code, 400)
        self.semester.is_active = True
        self.semester.save(update_fields=['is_active'])
        self.capstone_team.project_version += 1
        self.capstone_team.save(update_fields=['project_version'])
        self.grade.refresh_from_db()
        self.assertIn('previous project', peer_grading_unavailable_reason(self.grade))

    def test_redefense_does_not_open_peer_using_old_panel_scores(self):
        self.panel()
        self.grade.peer_score = Decimal('80')
        self.grade.verdict = TeamGrade.VERDICT_FOR_REDEFENSE
        self.grade.save()
        next_slot = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date=timezone.localdate(), start_time='10:00', room='Room 302')
        SchedulePanelist.objects.create(schedule=next_slot, panelist=self.panelist)
        grade = GradeContextService.get_or_create_for_schedule(next_slot)[0]
        self.assertIsNotNone(grade.peer_score)
        self.assertIn('every assigned', peer_grading_unavailable_reason(grade))
