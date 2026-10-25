"""Self-ratings are required and carry the same weight as teammate ratings."""
from decimal import Decimal

from rest_framework.test import APITestCase

from student_teams.models import TeamMembership
from . import tests as fixtures
from .models import PeerEvaluationSubmission, StudentStageGrade, TeamGrade
from .peer_eval import (
    is_evaluator_peer_complete,
    is_team_peer_eval_complete,
    peer_completion_summary,
    required_peer_submission_count,
    sync_peer_summaries,
)
from .services import GradeContextService


class RequiredSelfEvaluationTests(APITestCase):
    _rubric = fixtures.GradeCenterApiTests._rubric
    _peer_eval_payload = fixtures.GradeCenterApiTests._peer_eval_payload
    _complete_capstone_panel_grading = fixtures.GradeCenterApiTests._complete_capstone_panel_grading

    def setUp(self):
        fixtures.GradeCenterApiTests.setUp(self)
        self._complete_capstone_panel_grading()
        self.grade = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)[0]

    def submit(self, evaluator, evaluatee, score=4):
        self.client.force_authenticate(evaluator)
        payload = self._peer_eval_payload(evaluatee)
        payload['breakdown'][0]['score'] = score
        response = self.client.post('/api/grading/grades/peer-evaluations/', payload, format='json')
        self.grade.refresh_from_db()
        return response

    def assert_submit(self, evaluator, evaluatee, score=4):
        response = self.submit(evaluator, evaluatee, score)
        self.assertEqual(response.status_code, 200, response.data)

    def test_self_ratings_are_required_and_average_equally_into_individual_grades(self):
        self.grade.adviser_score = Decimal('80')
        self.grade.save()
        self.assert_submit(self.student, self.second_student, 4)
        self.assert_submit(self.second_student, self.student, 2)
        self.assertIsNone(self.grade.peer_score)
        self.assertFalse(is_team_peer_eval_complete(self.grade))
        self.assertFalse(is_evaluator_peer_complete(self.grade, self.student))
        summary = peer_completion_summary(self.grade)
        self.assertEqual((summary['submitted'], summary['required'], summary['evaluators_done']), (2, 4, 0))

        self.assert_submit(self.student, self.student, 5)
        self.assertTrue(is_evaluator_peer_complete(self.grade, self.student))
        self.assertFalse(is_team_peer_eval_complete(self.grade))
        self.assertIsNone(self.grade.peer_score)
        dashboard = self.client.get('/api/dashboards/student/').data
        self.assertTrue(dashboard['myPeerEvalComplete'])
        self.assertFalse(dashboard['peerEvalComplete'])
        self.assertEqual({row['evaluateeId'] for row in dashboard['myPeerSubmissions']},
                         {self.student.pk, self.second_student.pk})

        self.assert_submit(self.second_student, self.second_student, 1)
        self.assertTrue(is_team_peer_eval_complete(self.grade))
        self.assertEqual(self.grade.peer_score, Decimal('60.00'))
        first = StudentStageGrade.objects.get(team_grade=self.grade, student=self.student)
        second = StudentStageGrade.objects.get(team_grade=self.grade, student=self.second_student)
        self.assertEqual((first.peer_score, first.final_grade), (Decimal('70.00'), Decimal('78.00')))
        self.assertEqual((second.peer_score, second.final_grade), (Decimal('50.00'), Decimal('74.00')))
        summary = peer_completion_summary(self.grade)
        self.assertEqual((summary['submitted'], summary['required'], summary['evaluators_done']), (4, 4, 2))

    def test_self_submission_is_read_only_and_uses_server_rubric(self):
        self.assert_submit(self.student, self.student, 3)
        row = PeerEvaluationSubmission.objects.get(team_grade=self.grade,
            evaluator=self.student, evaluatee=self.student)
        self.assertEqual(row.weighted_score, Decimal('60.00'))
        self.assertEqual(row.max_score, Decimal('5.00'))
        self.assertEqual(self.submit(self.student, self.student, 5).status_code, 400)
        row.refresh_from_db()
        self.assertEqual(row.total_score, Decimal('3.00'))

    def test_single_member_must_submit_one_self_evaluation(self):
        TeamMembership.objects.filter(team=self.capstone_team, student=self.second_student).delete()
        self.assertEqual(required_peer_submission_count(self.capstone_team), 1)
        self.assertFalse(is_team_peer_eval_complete(self.grade))
        self.assertFalse(is_evaluator_peer_complete(self.grade, self.student))
        self.assert_submit(self.student, self.student, 4)
        self.assertEqual(self.grade.peer_score, Decimal('80.00'))
        self.assertTrue(is_team_peer_eval_complete(self.grade))

    def test_unfinished_legacy_total_cannot_skip_required_self_evaluations(self):
        self.assert_submit(self.student, self.second_student)
        self.assert_submit(self.second_student, self.student)
        self.grade.peer_score = Decimal('80')
        self.grade.save()
        self.assertFalse(is_team_peer_eval_complete(self.grade))
        self.assertFalse(peer_completion_summary(self.grade)['complete'])
        self.assert_submit(self.student, self.student)
        self.assertIsNone(self.grade.peer_score)
        self.assert_submit(self.second_student, self.second_student)
        self.assertEqual(self.grade.peer_score, Decimal('80.00'))

    def test_voided_self_rating_no_longer_completes_team(self):
        for evaluator in [self.student, self.second_student]:
            for evaluatee in [self.student, self.second_student]:
                self.assert_submit(evaluator, evaluatee)
        PeerEvaluationSubmission.objects.filter(team_grade=self.grade,
            evaluator=self.student, evaluatee=self.student).update(is_void=True)
        self.assertFalse(is_team_peer_eval_complete(self.grade))
        sync_peer_summaries(self.grade)
        self.grade.refresh_from_db()
        self.assertIsNone(self.grade.peer_score)
        self.assert_submit(self.student, self.student)
        self.assertTrue(is_team_peer_eval_complete(self.grade))

    def test_published_history_and_explicit_overrides_remain_complete(self):
        self.grade.peer_score = Decimal('80')
        self.assertFalse(is_team_peer_eval_complete(self.grade))
        self.grade.peer_score_is_override = True
        self.assertTrue(is_team_peer_eval_complete(self.grade))
        self.grade.peer_score_is_override = False
        self.grade.status = TeamGrade.STATUS_PUBLISHED
        self.assertTrue(is_team_peer_eval_complete(self.grade))
        sync_peer_summaries(self.grade)
        self.assertEqual(self.grade.peer_score, Decimal('80'))

    def test_self_submission_preserves_an_explicit_administrative_override(self):
        self.grade.peer_score = Decimal('85')
        self.grade.peer_score_is_override = True
        self.grade.save()
        self.assert_submit(self.student, self.student, 1)
        self.assertEqual(self.grade.peer_score, Decimal('85'))
        self.assertTrue(self.grade.peer_score_is_override)

    def test_self_evaluation_does_not_grant_access_to_another_team(self):
        self.assertEqual(self.submit(self.pit_student, self.pit_student).status_code, 400)
        self.assertFalse(PeerEvaluationSubmission.objects.filter(team_grade=self.grade).exists())
