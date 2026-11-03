from copy import deepcopy
from types import SimpleNamespace

from django.test import SimpleTestCase

from .student_visibility import student_assessment_payload


class StudentAssessmentVisibilityTests(SimpleTestCase):
    def test_nested_current_and_historical_scores_are_omitted_without_mutating_evidence(self):
        evidence = {
            'verdict': 'approved', 'approved_title': 'Recorded module',
            'panel_score': 82.5, 'final_grade': 85,
            'outcome_metadata': {'concepts': [{'key': 'c1', 'score': 82.5, 'qualifies': True}]},
            'history': [{'concepts': [{'title': 'Earlier module', 'panel_score': 80,
                                      'decision': 'not_selected'}], 'student_scores': {'1': 80}}],
            'peer_per_student': [{'average_score': 90}],
            'peerScore': 90,
        }
        before = deepcopy(evidence)
        public = student_assessment_payload(evidence, SimpleNamespace(role='student'))
        self.assertNotIn('panel_score', public)
        self.assertNotIn('final_grade', public)
        self.assertNotIn('peer_per_student', public)
        self.assertNotIn('peerScore', public)
        self.assertEqual(public['outcome_metadata']['concepts'], [{'key': 'c1'}])
        self.assertEqual(public['history'], [{'concepts': [
            {'title': 'Earlier module', 'decision': 'not_selected'}]}])
        self.assertEqual(public['verdict'], 'approved')
        self.assertEqual(evidence, before)

    def test_authorized_staff_assessment_keeps_scores(self):
        evidence = {'panel_score': 82.5, 'history': [{'final_grade': 85}]}
        for role in ('faculty', 'admin'):
            self.assertEqual(student_assessment_payload(evidence, SimpleNamespace(role=role)), evidence)
