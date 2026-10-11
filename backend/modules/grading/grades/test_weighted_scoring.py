from decimal import Decimal
from types import SimpleNamespace

from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from grading.rubrics.models import Rubric, RubricCriterion
from . import tests as fixtures
from .models import GradeBreakdown, PanelistCriterionScore, PeerEvaluationSubmission, StudentStageGrade
from .scoring import evaluation_percentage
from .services import panelist_percentage_from_criterion_scores, recompute_panel_score


class WeightedScoringMathTests(SimpleTestCase):
    def test_unequal_weights_and_mixed_scales(self):
        rows = [(Decimal('9'), Decimal('10'), Decimal('80')),
                (Decimal('2.5'), Decimal('5'), Decimal('20'))]
        self.assertEqual(evaluation_percentage(rows), Decimal('82.00'))

    def test_five_criteria_and_decimal_weights(self):
        rows = [(Decimal(score), Decimal(maximum), Decimal(weight)) for score, maximum, weight in
                [('9', '10', '40'), ('2.5', '5', '20'), ('10', '20', '15'), ('80', '100', '15'), ('10', '10', '10')]]
        self.assertEqual(evaluation_percentage(rows), Decimal('75.50'))
        self.assertEqual(evaluation_percentage([(Decimal(10), Decimal(10), Decimal('33.33')),
                                               (Decimal(5), Decimal(10), Decimal('33.33')),
                                               (Decimal(0), Decimal(10), Decimal('33.34'))]), Decimal('50.00'))

    def test_zero_scores_and_legacy_snapshots(self):
        self.assertEqual(evaluation_percentage([(Decimal(0), Decimal(10), Decimal(80)),
                                               (Decimal(0), Decimal(5), Decimal(20))]), Decimal('0.00'))
        legacy = [SimpleNamespace(score=Decimal(9), max_score_snapshot=Decimal(10), weight_snapshot=None),
                  SimpleNamespace(score=Decimal('2.5'), max_score_snapshot=Decimal(5), weight_snapshot=None)]
        self.assertEqual(panelist_percentage_from_criterion_scores(legacy), Decimal('76.67'))


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class WeightedScoringApiTests(APITestCase):
    # Reuse the standard ready-team fixture without inheriting its test cases.
    setUp = fixtures.GradeCenterApiTests.setUp
    _rubric = fixtures.GradeCenterApiTests._rubric
    _capstone_grade = fixtures.GradeCenterApiTests._capstone_grade
    _complete_capstone_panel_grading = fixtures.GradeCenterApiTests._complete_capstone_panel_grading
    _enable_capstone_peer_grading = fixtures.GradeCenterApiTests._enable_capstone_peer_grading

    def configure(self, rubric, target='team'):
        rubric.target_type = target
        rubric.save()
        rubric.criteria.all().delete()
        return [RubricCriterion.objects.create(
            rubric=rubric, name=f'Criterion {index}', max_score=maximum,
            weight=weight, display_order=index,
            target_type=('individual' if index == 1 else 'team') if target == 'both' else target,
        ) for index, (maximum, weight) in enumerate([(10, 80), (5, 20)])]

    def panel_submit(self, criteria, scores=(9, 2.5), submissions=None):
        self.client.force_authenticate(self.panelist)
        payload = {'team_id': self.capstone_team.pk, 'schedule_id': self.capstone_schedule.pk,
                   'criteria_scores': [{'criterion_id': criterion.pk, 'score': score,
                                        'weight': 999, 'max_score': 999}
                                       for criterion, score in zip(criteria, scores)]}
        if submissions is not None:
            payload['submissions'] = submissions
            payload.pop('criteria_scores')
        response = self.client.post('/api/defense/schedules/submit-grades/', payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        return self._capstone_grade()

    def adviser_submit(self, criteria, **overrides):
        grade = self._capstone_grade()
        self.client.force_authenticate(self.adviser)
        payload = {'rubric_id': self.adviser_rubric.pk, 'adviser_score': 100,
                   'criteria_scores': [{'criterion_id': criterion.pk, 'score': score,
                                        'max_score': 999, 'weight': 999}
                                       for criterion, score in zip(criteria, (9, 2.5))]}
        payload.update(overrides)
        return self.client.post(f'/api/grading/grades/adviser-grades/{grade.pk}/submit/', payload, format='json')

    def test_panel_backend_uses_rubric_and_freezes_weights_and_maxima(self):
        criteria = self.configure(self.panel_rubric)
        grade = self.panel_submit(criteria)
        self.assertEqual(grade.panel_score, Decimal('82.00'))
        rows = list(PanelistCriterionScore.objects.filter(submission__team_grade=grade).order_by('display_order'))
        self.assertEqual([row.weight_snapshot for row in rows], [Decimal(80), Decimal(20)])
        self.assertEqual([row.max_score_snapshot for row in rows], [Decimal(10), Decimal(5)])
        RubricCriterion.objects.filter(pk=criteria[0].pk).update(weight=20, max_score=100)
        RubricCriterion.objects.filter(pk=criteria[1].pk).update(weight=80)
        self.assertEqual(recompute_panel_score(grade), Decimal('82.00'))

    def test_panel_both_combines_shared_and_individual_weights_once_per_student(self):
        criteria = self.configure(self.panel_rubric, target='both')
        submissions = [{'student_id': None, 'criteria_scores': [{'criterion_id': criteria[0].pk, 'score': 9}]},
                       {'student_id': self.student.pk, 'criteria_scores': [{'criterion_id': criteria[1].pk, 'score': 2.5}]},
                       {'student_id': self.second_student.pk, 'criteria_scores': [{'criterion_id': criteria[1].pk, 'score': 5}]}]
        grade = self.panel_submit(criteria, submissions=submissions)
        self.assertEqual(grade.panel_score, Decimal('87.00'))
        self.assertEqual(StudentStageGrade.objects.get(team_grade=grade, student=self.student).panel_score, Decimal('82.00'))
        self.assertEqual(StudentStageGrade.objects.get(team_grade=grade, student=self.second_student).panel_score, Decimal('92.00'))
        results = self.client.get('/api/defense/schedules/panelist-results/')
        self.assertEqual(results.data['results'][0]['percentage'], 87)
        self.client.force_authenticate(self.admin)
        response = self.client.get(f'/api/grading/grades/{grade.pk}/')
        self.assertEqual(sorted(Decimal(row['percentage']) for row in response.data['grade']['panel_evaluation_scores']),
                         [Decimal(82), Decimal(92)])

    def test_adviser_ignores_client_aggregate_weights_and_maxima(self):
        criteria = self.configure(self.adviser_rubric)
        response = self.adviser_submit(criteria)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(Decimal(response.data['grade']['adviser_score']), Decimal('82.00'))
        rows = GradeBreakdown.objects.filter(team_grade_id=response.data['grade']['id'], evaluation_type='adviser').order_by('display_order')
        self.assertEqual(list(rows.values_list('weight_snapshot', flat=True)), [Decimal(80), Decimal(20)])
        self.assertEqual(list(rows.values_list('max_score', flat=True)), [Decimal(10), Decimal(5)])

    def test_adviser_rejects_missing_duplicate_and_foreign_criteria_without_replacing_scores(self):
        criteria = self.configure(self.adviser_rubric)
        response = self.adviser_submit(criteria)
        self.assertEqual(response.status_code, 200, response.data)
        grade_id = response.data['grade']['id']
        before = list(GradeBreakdown.objects.filter(team_grade_id=grade_id).values('pk', 'score', 'max_score', 'weight_snapshot'))
        for scores in ([{'criterion_id': criteria[0].pk, 'score': 9}],
                       [{'criterion_id': criteria[0].pk, 'score': 9}] * 2,
                       [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 9}]):
            with self.subTest(scores=scores):
                invalid = self.adviser_submit(criteria, criteria_scores=scores)
                self.assertEqual(invalid.status_code, 400, invalid.data)
                self.assertEqual(list(GradeBreakdown.objects.filter(team_grade_id=grade_id).values('pk', 'score', 'max_score', 'weight_snapshot')), before)

    def test_adviser_both_uses_shared_weight_for_each_student(self):
        criteria = self.configure(self.adviser_rubric, target='both')
        response = self.adviser_submit(criteria, criteria_scores=[],
            team_criteria_scores=[{'criterion_id': criteria[0].pk, 'score': 9}],
            student_submissions=[{'student_id': student.pk,
                                  'criteria_scores': [{'criterion_id': criteria[1].pk, 'score': score}]}
                                 for student, score in [(self.student, 2.5), (self.second_student, 5)]])
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(Decimal(response.data['grade']['adviser_score']), Decimal('87.00'))
        self.assertEqual(sorted(Decimal(row['adviser_score']) for row in response.data['grade']['peer_per_student']),
                         [Decimal(82), Decimal(92)])

    def test_peer_backend_computes_weighted_score_from_criteria_instead_of_client_total(self):
        self._complete_capstone_panel_grading()
        self._enable_capstone_peer_grading()
        criteria = self.configure(self.peer_rubric, target='individual')
        for evaluator, evaluatee, scores in [(self.student, self.second_student, (9, 2.5)),
                                            (self.second_student, self.student, (10, 5))]:
            self.client.force_authenticate(evaluator)
            response = self.client.post('/api/grading/grades/peer-evaluations/', {
                'teamId': self.capstone_team.pk, 'evaluateeId': evaluatee.pk, 'total': 999, 'max': 1,
                'breakdown': [{'criterion_id': criterion.pk, 'score': score, 'weight': 999, 'max': 999}
                              for criterion, score in zip(criteria, scores)],
            }, format='json')
            self.assertEqual(response.status_code, 200, response.data)
        grade = self._capstone_grade()
        self.assertEqual(grade.peer_score, Decimal('91.00'))
        submission = PeerEvaluationSubmission.objects.get(team_grade=grade, evaluator=self.student)
        self.assertEqual(submission.weighted_score, Decimal('82.00'))
        self.assertEqual(submission.total_score, Decimal('11.50'))
        self.assertEqual(submission.max_score, Decimal('15.00'))
        self.assertEqual([Decimal(row['weight_snapshot']) for row in submission.breakdown], [Decimal(80), Decimal(20)])

    def test_peer_rejects_incomplete_criteria(self):
        self._complete_capstone_panel_grading()
        self._enable_capstone_peer_grading()
        criteria = self.configure(self.peer_rubric, target='individual')
        self.client.force_authenticate(self.student)
        response = self.client.post('/api/grading/grades/peer-evaluations/', {
            'teamId': self.capstone_team.pk, 'evaluateeId': self.second_student.pk,
            'breakdown': [{'criterion_id': criteria[0].pk, 'score': 9}],
        }, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(PeerEvaluationSubmission.objects.filter(evaluator=self.student).exists())
