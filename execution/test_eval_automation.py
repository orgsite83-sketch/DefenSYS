"""Automation respects backend eligibility, even when rubric criteria exist."""
from contextlib import redirect_stdout
from io import StringIO
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from execution import auto_adviser_eval, auto_peer_eval


class EvaluationAutomationTests(unittest.TestCase):
    def peer_args(self, **overrides):
        values = dict(students=None, all_students=True, team_id=None, limit=None,
            min_score=6, max_score=9, base_url='http://example.test', http_login=False,
            dry_run=False, password=None, stage=None, delay=0, session_id=None, semester_id=None)
        return SimpleNamespace(**{**values, **overrides})

    def peer_dashboard(self, **overrides):
        return {'student': {'id': 1}, 'team': {'id': 2, 'name': 'Team Test', 'members': [{'id': 1}, {'id': 3}]},
            'current_stage': 'Project Proposal', 'peerCriteria': [{'name': 'Contribution', 'maxScore': 10}],
            'peerEvalEnabled': True, 'myPeerSubmissions': [],
            'peerEvalContext': {'session_id': 'session-a', 'semester_id': 1}, **overrides}

    def run_peer(self, args, dashboard):
        client = Mock()
        client.authenticate.return_value = True
        client.get_dashboard.return_value = dashboard
        with patch.object(auto_peer_eval, 'parse_args', return_value=args), \
                patch.object(auto_peer_eval, 'fetch_student_records', return_value=[('student', 'unused')]), \
                patch.object(auto_peer_eval, 'StudentClient', return_value=client), redirect_stdout(StringIO()):
            auto_peer_eval.run()
        return client

    def test_closed_peer_form_is_skipped_even_with_criteria(self):
        client = self.run_peer(self.peer_args(), self.peer_dashboard(peerEvalEnabled=False))
        client.submit_evaluation.assert_not_called()

    def test_peer_session_filter_never_submits_to_another_session(self):
        client = self.run_peer(self.peer_args(session_id='session-b'), self.peer_dashboard())
        client.submit_evaluation.assert_not_called()

    def test_open_peer_submits_in_matching_context(self):
        client = self.run_peer(self.peer_args(session_id='session-a', semester_id=1), self.peer_dashboard())
        client.submit_evaluation.assert_called_once()

    def test_closed_adviser_form_is_skipped_even_with_a_grade_and_rubric(self):
        args = SimpleNamespace(advisers=None, all_advisers=True, team_id=None, min_score=6,
            max_score=9, base_url='http://example.test', dry_run=False, delay=0,
            stage=None, session_id=None, semester_id=None)
        session = Mock()
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {'grades': [{'id': 2, 'adviser_score': None,
            'adviser_grading_available': False, 'assigned_adviser_rubric_id': 1,
            'assigned_adviser_criteria': [{'name': 'Contribution', 'max_score': 10}]}]}
        with patch.object(auto_adviser_eval, 'parse_args', return_value=args), \
                patch.object(auto_adviser_eval, 'fetch_adviser_users', return_value=['adviser']), \
                patch.object(auto_adviser_eval, 'get_jwt_token_for_user', return_value='test-token'), \
                patch.object(auto_adviser_eval.requests, 'Session', return_value=session), redirect_stdout(StringIO()):
            auto_adviser_eval.run()
        session.post.assert_not_called()


if __name__ == '__main__':
    unittest.main()
