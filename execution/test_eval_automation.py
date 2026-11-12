"""Automation respects backend eligibility, even when rubric criteria exist."""
from contextlib import redirect_stdout
from io import StringIO
import os
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from execution import auto_adviser_eval, auto_panelist_eval, auto_peer_eval


class EvaluationAutomationTests(unittest.TestCase):
    def setUp(self):
        for name, value in [('fetch_target_schedule_ids', [101]), ('fetch_external_panelists', [])]:
            mock = patch.object(auto_panelist_eval, name, return_value=value)
            mock.start()
            self.addCleanup(mock.stop)

    def peer_args(self, **overrides):
        values = dict(students=None, all_students=True, team_id=None, limit=None,
            min_score=6, max_score=9, base_url='http://example.test', http_login=False,
            dry_run=False, password=None, stage=None, delay=0, session_id=None, semester_id=None, year=None)
        return SimpleNamespace(**{**values, **overrides})

    def peer_dashboard(self, **overrides):
        return {'student': {'id': 1}, 'team': {'id': 2, 'name': 'Team Test', 'yearLevel': '1st Year',
            'members': [{'id': 1}, {'id': 3}]},
            'current_stage': 'Project Proposal', 'peerCriteria': [{'name': 'Contribution', 'maxScore': 10}],
            'peerEvalEnabled': True, 'myPeerSubmissions': [],
            'peerEvalContext': {'session_id': 'session-a', 'semester_id': 1}, **overrides}

    def run_peer(self, args, dashboard, *, submissions=None, authenticate=True):
        client = Mock()
        client.authenticate.return_value = authenticate
        client.get_dashboard.return_value = dashboard
        if submissions is not None:
            client.submit_evaluation.side_effect = submissions
        with patch.object(auto_peer_eval, 'parse_args', return_value=args), \
                patch.object(auto_peer_eval, 'fetch_student_records', return_value=[('student', 'unused')]), \
                patch.object(auto_peer_eval, 'StudentClient', return_value=client), redirect_stdout(StringIO()) as output:
            self.peer_result = auto_peer_eval.run()
        self.peer_output = output.getvalue()
        return client

    def test_closed_peer_form_is_skipped_even_with_criteria(self):
        client = self.run_peer(self.peer_args(), self.peer_dashboard(peerEvalEnabled=False))
        client.submit_evaluation.assert_not_called()

    def test_peer_session_filter_never_submits_to_another_session(self):
        client = self.run_peer(self.peer_args(session_id='session-b'), self.peer_dashboard())
        client.submit_evaluation.assert_not_called()

    def test_peer_timeout_cli_rejects_unbounded_or_nonpositive_waits(self):
        self.assertEqual(auto_peer_eval.parse_args(['--all-students', '--request-timeout', '90']).request_timeout, 90)
        for value in ['0', '-1', '301', 'nan', 'inf']:
            with self.subTest(value=value), patch('sys.stderr', new=StringIO()), self.assertRaises(SystemExit):
                auto_peer_eval.parse_args(['--all-students', '--request-timeout', value])

    def test_peer_slow_dashboard_and_submissions_use_configured_timeout_without_retrying_writes(self):
        session = Mock()
        session.post.return_value.status_code = 200
        session.post.return_value.json.return_value = {'access': 'test-token'}
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = self.peer_dashboard()
        with patch.object(auto_peer_eval.requests, 'Session', return_value=session):
            client = auto_peer_eval.StudentClient('http://example.test', 'student', request_timeout=90)
        self.assertTrue(client.authenticate(use_http_login=True))
        self.assertEqual(client.get_dashboard(), self.peer_dashboard())
        self.assertTrue(client.submit_evaluation({'teamId': 2}))
        self.assertEqual(session.get.call_args.kwargs['timeout'], 90)
        self.assertTrue(all(call.kwargs['timeout'] == 90 for call in session.post.call_args_list))
        session.post.reset_mock()
        session.post.side_effect = auto_peer_eval.requests.Timeout('Slow response')
        with redirect_stdout(StringIO()):
            self.assertFalse(client.submit_evaluation({'teamId': 2}))
        session.post.assert_called_once()

    def test_open_peer_submits_in_matching_context(self):
        client = self.run_peer(self.peer_args(session_id='session-a', semester_id=1), self.peer_dashboard())
        self.assertEqual([call.args[0]['evaluateeId'] for call in client.submit_evaluation.call_args_list], [1, 3])

    def test_peer_aggregate_total_does_not_send_float_precision_artifacts(self):
        criteria = [{'id': index, 'name': f'Quality {index}', 'maxScore': 10} for index in range(3)]
        with patch.object(auto_peer_eval.random, 'uniform', return_value=8.1):
            client = self.run_peer(self.peer_args(), self.peer_dashboard(peerCriteria=criteria))
        for call in client.submit_evaluation.call_args_list:
            self.assertEqual(str(call.args[0]['total']), '24.3')
        self.assertEqual(self.peer_result, 0)

    def test_peer_partial_failure_is_counted_and_never_reported_as_full_success(self):
        client = self.run_peer(self.peer_args(), self.peer_dashboard(), submissions=[True, False])
        self.assertEqual(client.submit_evaluation.call_count, 2)
        self.assertEqual(self.peer_result, 1)
        self.assertIn('Evaluations Created : 1', self.peer_output)
        self.assertIn('Evaluations Failed  : 1', self.peer_output)
        self.assertNotIn('All peer evaluations successfully submitted', self.peer_output)

    def test_peer_account_failures_are_included_in_exit_status(self):
        for dashboard, authenticated in [(self.peer_dashboard(), False), (None, True)]:
            with self.subTest(authenticated=authenticated):
                client = self.run_peer(self.peer_args(), dashboard, authenticate=authenticated)
                client.submit_evaluation.assert_not_called()
                self.assertEqual(self.peer_result, 1)
                self.assertIn('Account Failures    : 1', self.peer_output)
                self.assertNotIn('All peer evaluations successfully submitted', self.peer_output)

    def test_peer_rerun_skips_and_counts_each_saved_pair(self):
        client = self.run_peer(self.peer_args(), self.peer_dashboard(myPeerSubmissions=[{'evaluateeId': 1}]))
        self.assertEqual([call.args[0]['evaluateeId'] for call in client.submit_evaluation.call_args_list], [3])
        self.assertIn('Already Completed   : 1', self.peer_output)

    def test_peer_scores_scale_to_each_maximum_and_identify_section_criteria(self):
        criteria = [{'id': index + 1, 'name': 'Quality', 'section': f'Section {index}',
                     'maxScore': maximum, 'weight': 20}
                    for index, maximum in enumerate([0.5, 5, 10, 20, 100])]
        client = self.run_peer(self.peer_args(min_score=8, max_score=8),
                               self.peer_dashboard(peerCriteria=criteria))
        self.assertEqual(client.submit_evaluation.call_count, 2)
        for call in client.submit_evaluation.call_args_list:
            payload = call.args[0]
            self.assertEqual([row['score'] for row in payload['breakdown']], [0.4, 4, 8, 16, 80])
            self.assertEqual([row['criterion_id'] for row in payload['breakdown']], [1, 2, 3, 4, 5])
            self.assertEqual([row['section'] for row in payload['breakdown']],
                             [f'Section {index}' for index in range(5)])
            self.assertAlmostEqual(payload['total'], 108.4)
            self.assertEqual(payload['max'], 135.5)

    def test_peer_zero_and_decimal_ranges_are_preserved(self):
        for rating, expected in [(0, [0, 0]), (8.25, [4.12, 16.5])]:
            with self.subTest(rating=rating):
                client = self.run_peer(self.peer_args(min_score=rating, max_score=rating),
                    self.peer_dashboard(peerCriteria=[{'id': 1, 'name': 'First', 'maxScore': 5},
                                                       {'id': 2, 'name': 'Second', 'maxScore': 20}]))
                self.assertEqual([row['score'] for row in client.submit_evaluation.call_args.args[0]['breakdown']],
                                 expected)

    def test_peer_invalid_score_ranges_are_rejected(self):
        for flags in [['--min-score', '-1'], ['--max-score', '11'], ['--min-score', 'nan'],
                      ['--max-score', 'inf'], ['--min-score', '9', '--max-score', '7']]:
            with self.subTest(flags=flags), patch('sys.stderr', new=StringIO()), self.assertRaises(SystemExit):
                auto_peer_eval.parse_args(['--all-students', *flags])

    def test_peer_year_cli_accepts_numbers_and_labels_and_rejects_unknown_years(self):
        for value, expected in [('1', '1st Year'), ('2nd Year', '2nd Year'), ('3', '3rd Year'), ('4', '4th Year')]:
            with self.subTest(value=value), patch.object(sys, 'argv', ['auto_peer_eval.py', '--all-students', '--year', value]):
                self.assertEqual(auto_peer_eval.parse_args().year, expected)
        for value in ['0', '5', 'first']:
            with self.subTest(value=value), patch.object(sys, 'argv', ['auto_peer_eval.py', '--all-students', '--year', value]), \
                    patch('sys.stderr', new=StringIO()), self.assertRaises(SystemExit) as error:
                auto_peer_eval.parse_args()
            self.assertEqual(error.exception.code, 2)

    def test_peer_year_uses_the_live_team_instead_of_the_students_academic_year(self):
        dashboard = self.peer_dashboard(academic_record={'year_level': '2nd Year'})
        client = self.run_peer(self.peer_args(year='1st Year', session_id='session-a', semester_id=1), dashboard)
        self.assertEqual(client.submit_evaluation.call_count, 2)
        self.assertEqual(client.submit_evaluation.call_args.args[0]['teamId'], 2)

    def test_peer_year_rechecks_dashboard_and_skips_other_or_unknown_cohorts(self):
        for year in ['2nd Year', None, '']:
            for dry_run in [False, True]:
                with self.subTest(year=year, dry_run=dry_run):
                    dashboard = self.peer_dashboard()
                    dashboard['team']['yearLevel'] = year
                    client = self.run_peer(self.peer_args(year='1st Year', dry_run=dry_run), dashboard)
                    client.submit_evaluation.assert_not_called()

    def test_peer_year_filter_preserves_availability_and_completed_evaluations(self):
        for overrides in [{'peerEvalEnabled': False}, {'myPeerSubmissions': [{'evaluateeId': 1}, {'evaluateeId': 3}]}]:
            with self.subTest(overrides=overrides):
                client = self.run_peer(self.peer_args(year='1st Year'), self.peer_dashboard(**overrides))
                client.submit_evaluation.assert_not_called()

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

    def adviser_args(self, **overrides):
        return SimpleNamespace(**{
            'advisers': None, 'all_advisers': True, 'team_id': None, 'min_score': 8,
            'max_score': 8, 'base_url': 'http://example.test', 'dry_run': False,
            'delay': 0, 'stage': None, 'session_id': None, 'semester_id': None,
            'request_timeout': 90, **overrides,
        })

    def adviser_row(self, **overrides):
        return {
            'id': 2, 'team_id': 20, 'team_name': 'Team Test', 'adviser_score': None,
            'adviser_grading_available': True, 'assigned_adviser_rubric_id': 1,
            'assigned_adviser_rubric_target_type': 'team', 'stage_label': 'Project Proposal',
            'semester_id': 3, 'session_id': 'session-a', 'members': [{'student_id': 11}, {'student_id': 12}],
            'assigned_adviser_criteria': [
                {'id': 1, 'name': 'Quality', 'section': 'Research', 'max_score': 20, 'target_type': 'team'},
                {'id': 2, 'name': 'Quality', 'section': 'Teamwork', 'max_score': 5, 'target_type': 'team'},
            ], **overrides,
        }

    def run_adviser(self, rows, *, args=None, statuses=(200,), token='test-token', get_status=200):
        session = Mock()
        session.get.return_value.status_code = get_status
        session.get.return_value.json.return_value = {'grades': rows}
        session.post.side_effect = [status if isinstance(status, Exception) else Mock(status_code=status, text='Failure',
            json=Mock(return_value={'grade': {'adviser_score': '80.00'}})) for status in statuses]
        with patch.object(auto_adviser_eval, 'parse_args', return_value=args or self.adviser_args()), \
                patch.object(auto_adviser_eval, 'fetch_adviser_users', return_value=['adviser']), \
                patch.object(auto_adviser_eval, 'get_jwt_token_for_user', return_value=token), \
                patch.object(auto_adviser_eval.requests, 'Session', return_value=session), redirect_stdout(StringIO()) as output:
            self.adviser_result = auto_adviser_eval.run()
        self.adviser_output = output.getvalue()
        return session

    def test_adviser_scales_scores_and_preserves_section_ids_for_all_targets(self):
        for target in ['team', 'individual', 'both']:
            with self.subTest(target=target):
                row = self.adviser_row(assigned_adviser_rubric_target_type=target)
                if target == 'both':
                    row['assigned_adviser_criteria'][1]['target_type'] = 'individual'
                session = self.run_adviser([row])
                payload = session.post.call_args.kwargs['json']
                groups = ([payload['team_criteria_scores']] if target != 'individual' else [])
                groups += [item['criteria_scores'] for item in payload['student_submissions']]
                for scores in groups:
                    for score in scores:
                        expected = {1: (16, 'Research'), 2: (4, 'Teamwork')}
                        self.assertEqual((score['score'], score['section']), expected[score['criterion_id']])
                self.assertEqual([item['student_id'] for item in payload['student_submissions']],
                                 [] if target == 'team' else [11, 12])
                self.assertEqual(self.adviser_result, 0)
                self.assertIn('Score: 80.00%', self.adviser_output)

    def test_adviser_preserves_zero_and_decimal_ranges(self):
        for rating, expected in [(0, [0, 0]), (8.25, [16.5, 4.12])]:
            with self.subTest(rating=rating):
                session = self.run_adviser([self.adviser_row()],
                    args=self.adviser_args(min_score=rating, max_score=rating))
                self.assertEqual([row['score'] for row in session.post.call_args.kwargs['json']['team_criteria_scores']], expected)

    def test_adviser_partial_failure_has_nonzero_exit_and_does_not_retry(self):
        session = self.run_adviser([self.adviser_row(), self.adviser_row(id=3)], statuses=(200, 400))
        self.assertEqual(session.post.call_count, 2)
        self.assertEqual(self.adviser_result, 1)
        self.assertIn('Evaluations Failed  : 1', self.adviser_output)
        self.assertNotIn('[OK] Adviser evaluations submitted!', self.adviser_output)

    def test_adviser_preview_skips_recorded_grades_and_never_posts(self):
        session = self.run_adviser([self.adviser_row(adviser_score=0), self.adviser_row(id=3)],
                                   args=self.adviser_args(dry_run=True))
        session.post.assert_not_called()
        self.assertEqual(self.adviser_result, 0)
        self.assertIn('Evaluations Planned : 1', self.adviser_output)
        self.assertIn('Already Graded      : 1', self.adviser_output)
        self.assertNotIn('[OK] Adviser evaluations submitted!', self.adviser_output)

    def test_adviser_timeout_applies_to_reads_and_writes(self):
        session = self.run_adviser([self.adviser_row()])
        self.assertEqual(session.get.call_args.kwargs['timeout'], 90)
        self.assertEqual(session.post.call_args.kwargs['timeout'], 90)

    def test_adviser_timed_out_write_is_not_retried_and_is_reported_as_failure(self):
        session = self.run_adviser([self.adviser_row()], statuses=(auto_adviser_eval.requests.Timeout('Timed out'),))
        session.post.assert_called_once()
        self.assertEqual(self.adviser_result, 1)
        self.assertIn('Evaluations Failed  : 1', self.adviser_output)

    def test_adviser_invalid_rubric_or_missing_members_never_posts(self):
        for fields in [
            {'assigned_adviser_rubric_target_type': 'invalid'},
            {'assigned_adviser_rubric_target_type': 'individual', 'members': []},
            {'assigned_adviser_rubric_id': None},
            {'assigned_adviser_rubric_target_type': 'both'},
        ]:
            with self.subTest(fields=fields):
                session = self.run_adviser([self.adviser_row(**fields)])
                session.post.assert_not_called()
                self.assertEqual(self.adviser_result, 1)

    def test_adviser_authentication_and_list_failures_are_counted(self):
        for token, get_status in [(None, 200), ('token', 500)]:
            with self.subTest(token=token):
                session = self.run_adviser([], token=token, get_status=get_status)
                session.post.assert_not_called()
                self.assertEqual(self.adviser_result, 1)
                self.assertIn('Account Failures    : 1', self.adviser_output)

    def test_adviser_rejects_invalid_ranges_and_timeout(self):
        for flags in [['--min-score', '-1'], ['--max-score', '11'], ['--min-score', 'nan'],
                      ['--min-score', '9', '--max-score', '7'], ['--request-timeout', '0'],
                      ['--request-timeout', '301'], ['--request-timeout', 'inf']]:
            with self.subTest(flags=flags), patch('sys.stderr', new=StringIO()), self.assertRaises(SystemExit):
                auto_adviser_eval.parse_args(['--all-advisers', *flags])

    def panelist_args(self, **overrides):
        values = dict(
            panelists=None, all_panelists=True, team_id=None, min_score=7,
            max_score=9, base_url='http://example.test', dry_run=False, delay=0,
            stage=None, session_id=None, semester_id=None, scope=None,
            verdict='auto', verdict_remarks=None, revision_deadline=None,
            redefense_verification=False, no_verdict=False, verdict_only=False,
            external_only=False, exclude_external=False, year=None, include_drafts=False,
        )
        return SimpleNamespace(**{**values, **overrides})

    def panelist_schedule_payload(self, **overrides):
        payload = {
            'id': 10,
            'schedule_id': 101,
            'name': 'Team Alpha',
            'scope': 'capstone',
            'is_capstone': True,
            'defense_stage': 'Project Proposal',
            'session_id': 'session-uuid-1',
            'semester_id': 1,
            'is_posted': False,
            'grading_available': True,
            'grading_unavailable_reason': '',
            'is_chair': True,
            'can_issue_verdict': True,
            'year_level': '1st Year',
            'evaluation_context': 'ctx-signature',
            'panel_rubric': {
                'target_type': 'team',
                'criteria': [{'id': 1, 'name': 'Methodology', 'max_score': 10.0}],
            },
            'members': [{'id': 11, 'name': 'Student A'}],
            'verdict': None,
        }
        payload.update(overrides)
        return payload

    def test_closed_panelist_defense_is_skipped_even_with_criteria(self):
        args = self.panelist_args()
        session = Mock()
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {
            'teams': [self.panelist_schedule_payload(grading_available=False, grading_unavailable_reason='Grading locked until defense date')]
        }
        with patch.object(auto_panelist_eval, 'parse_args', return_value=args), \
                patch.object(auto_panelist_eval, 'fetch_panelist_users', return_value=['panelist1']), \
                patch.object(auto_panelist_eval, 'get_jwt_token_for_user', return_value='token1'), \
                patch.object(auto_panelist_eval.requests, 'Session', return_value=session), \
                patch.object(auto_panelist_eval.requests, 'patch') as mock_patch, \
                redirect_stdout(StringIO()):
            auto_panelist_eval.run()

        session.post.assert_not_called()
        mock_patch.assert_not_called()

    def test_panelist_session_and_stage_filters_skip_mismatched_defense(self):
        args = self.panelist_args(stage='Final Defense', session_id='session-uuid-2')
        session = Mock()
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {
            'teams': [self.panelist_schedule_payload(defense_stage='Project Proposal', session_id='session-uuid-1')]
        }
        with patch.object(auto_panelist_eval, 'parse_args', return_value=args), \
                patch.object(auto_panelist_eval, 'fetch_panelist_users', return_value=['panelist1']), \
                patch.object(auto_panelist_eval, 'get_jwt_token_for_user', return_value='token1'), \
                patch.object(auto_panelist_eval.requests, 'Session', return_value=session), \
                patch.object(auto_panelist_eval.requests, 'patch') as mock_patch, \
                redirect_stdout(StringIO()):
            auto_panelist_eval.run()

        session.post.assert_not_called()
        mock_patch.assert_not_called()

    def test_open_panelist_defense_submits_grades_and_issues_capstone_verdict(self):
        args = self.panelist_args(session_id='session-uuid-1', request_timeout=90)
        session = Mock()
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {
            'teams': [self.panelist_schedule_payload()]
        }
        session.post.return_value.status_code = 200
        session.post.return_value.json.return_value = {'panel_score': 88.0}

        patch_response = Mock()
        patch_response.status_code = 200
        patch_response.json.return_value = {'success': True}

        with patch.object(auto_panelist_eval, 'parse_args', return_value=args), \
                patch.object(auto_panelist_eval, 'fetch_panelist_users', return_value=['panelist1']), \
                patch.object(auto_panelist_eval, 'get_jwt_token_for_user', return_value='token1'), \
                patch.object(auto_panelist_eval, 'get_schedule_chair_username', return_value='chair1'), \
                patch.object(auto_panelist_eval.requests, 'Session', return_value=session), \
                patch.object(auto_panelist_eval.requests, 'patch', return_value=patch_response) as mock_patch, \
                redirect_stdout(StringIO()):
            auto_panelist_eval.run()

        session.post.assert_called_once()
        mock_patch.assert_called_once()
        # Ensure verdict endpoint called with 'approved'
        call_url = mock_patch.call_args[0][0]
        call_payload = mock_patch.call_args[1]['json']
        self.assertIn('/api/defense/schedules/101/verdict/', call_url)
        self.assertEqual(call_payload['verdict'], 'approved')
        self.assertTrue(all(call.kwargs['timeout'] == 90 for call in session.get.call_args_list))
        self.assertEqual(session.post.call_args.kwargs['timeout'], 90)
        self.assertEqual(mock_patch.call_args.kwargs['timeout'], 90)

    def test_panelist_timeout_cli_rejects_unbounded_or_nonpositive_waits(self):
        self.assertEqual(auto_panelist_eval.parse_args(['--all-panelists', '--request-timeout', '90']).request_timeout, 90)
        for value in ['0', '-1', '301', 'nan', 'inf']:
            with self.subTest(value=value), patch('sys.stderr', new=StringIO()), self.assertRaises(SystemExit):
                auto_panelist_eval.parse_args(['--all-panelists', '--request-timeout', value])

    def test_pit_defense_submits_grades_but_skips_verdict(self):
        args = self.panelist_args(scope='pit')
        session = Mock()
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {
            'teams': [self.panelist_schedule_payload(scope='pit', is_capstone=False)]
        }
        session.post.return_value.status_code = 200
        session.post.return_value.json.return_value = {'panel_score': 91.0}

        with patch.object(auto_panelist_eval, 'parse_args', return_value=args), \
                patch.object(auto_panelist_eval, 'fetch_panelist_users', return_value=['panelist1']), \
                patch.object(auto_panelist_eval, 'get_jwt_token_for_user', return_value='token1'), \
                patch.object(auto_panelist_eval.requests, 'Session', return_value=session), \
                patch.object(auto_panelist_eval.requests, 'patch') as mock_patch, \
                redirect_stdout(StringIO()):
            auto_panelist_eval.run()

        session.post.assert_called_once()
        mock_patch.assert_not_called()

    def run_panel(self, **overrides):
        args = self.panelist_args(**overrides.pop('args', {}))
        session = Mock()
        session.get.return_value.status_code = 200
        session.get.return_value.json.return_value = {'teams': overrides.pop('teams', [self.panelist_schedule_payload()])}
        if 'get_payloads' in overrides:
            session.get.side_effect = [Mock(status_code=200, json=Mock(return_value=data)) for data in overrides.pop('get_payloads')]
        session.post.return_value.status_code = overrides.pop('status_code', 200)
        session.post.return_value.json.return_value = {'panel_score': '90.00'}
        guests = overrides.pop('guests', [{'id': 3, 'name': 'External Expert', 'unavailable_reason': ''}])
        with patch.object(auto_panelist_eval, 'parse_args', return_value=args), \
                patch.object(auto_panelist_eval, 'fetch_panelist_users', return_value=overrides.pop('faculty', [])), \
                patch.object(auto_panelist_eval, 'fetch_external_panelists', return_value=guests), \
                patch.object(auto_panelist_eval, 'get_guest_jwt_token', return_value='guest-token') as guest_token, \
                patch.object(auto_panelist_eval, 'get_jwt_token_for_user', return_value='faculty-token'), \
                patch.object(auto_panelist_eval, 'get_schedule_chair_username', return_value=overrides.pop('chair', 'chair')), \
                patch.object(auto_panelist_eval, 'submit_schedule_verdict', return_value=overrides.pop('verdict_result', {'status': 'ok'})) as verdict, \
                patch.object(auto_panelist_eval.requests, 'Session', return_value=session), redirect_stdout(StringIO()) as output:
            result = auto_panelist_eval.run()
        return session, guest_token, verdict, result, output.getvalue()

    def test_external_uses_guest_api_and_preserves_evaluation_context(self):
        session, token, verdict, result, output = self.run_panel()
        token.assert_called_once_with(3)
        self.assertTrue(session.get.call_args_list[0].args[0].endswith('/guest-assignments/'))
        self.assertTrue(session.get.call_args_list[-1].args[0].endswith('/panelist-assignments/'))
        self.assertTrue(session.post.call_args.args[0].endswith('/guest-submit-grades/'))
        payload = session.post.call_args.kwargs['json']
        self.assertEqual(payload['evaluation_context'], 'ctx-signature')
        self.assertEqual(payload['schedule_id'], 101)
        verdict.assert_called_once()
        self.assertEqual(result, 0)
        self.assertNotIn('FAIL', output)

    def test_expired_external_is_reported_without_authenticating_or_submitting(self):
        session, token, verdict, _, output = self.run_panel(guests=[{
            'id': 3, 'name': 'External Expert', 'unavailable_reason': 'Invitation expired; renew access.'}])
        token.assert_not_called()
        session.post.assert_not_called()
        verdict.assert_not_called()
        self.assertIn('Invitation expired', output)

    def test_external_only_dry_run_never_writes_grades_or_verdicts(self):
        session, _, verdict, _, output = self.run_panel(args={'external_only': True, 'dry_run': True})
        session.post.assert_not_called()
        verdict.assert_not_called()
        self.assertIn('Evaluations Planned : 1', output)

    def test_same_panelist_old_term_assignment_is_outside_schedule_allowlist(self):
        session, _, verdict, _, _ = self.run_panel(teams=[self.panelist_schedule_payload(schedule_id=999)])
        session.post.assert_not_called()
        verdict.assert_not_called()

    def test_guest_http_failure_is_counted_and_returns_failure(self):
        session, _, verdict, result, output = self.run_panel(status_code=403)
        session.post.assert_called_once()
        verdict.assert_not_called()
        self.assertEqual(result, 1)
        self.assertIn('Failed              : 1', output)

    def test_explicit_exclusion_runs_only_faculty(self):
        session, token, _, _, _ = self.run_panel(args={'exclude_external': True}, faculty=['panelist'])
        token.assert_not_called()
        self.assertTrue(session.post.call_args.args[0].endswith('/submit-grades/'))

    def test_zero_and_scaled_scores_respect_fractional_and_large_maxima(self):
        criteria = [{'id': i, 'max_score': maximum} for i, maximum in enumerate([0.5, 5, 10, 100])]
        self.assertEqual([s['score'] for s in auto_panelist_eval.generate_scores(criteria, 0, 0)], [0, 0, 0, 0])
        self.assertEqual([s['score'] for s in auto_panelist_eval.generate_scores(criteria, 8, 8)], [0.4, 4, 8, 80])

    def test_external_both_target_submits_team_and_every_member_with_scaled_scores(self):
        rubric = {'target_type': 'both', 'criteria': [
            {'id': 1, 'target_type': 'team', 'max_score': 5},
            {'id': 2, 'target_type': 'individual', 'max_score': 100},
        ]}
        team = self.panelist_schedule_payload(scope='pit', is_capstone=False, panel_rubric=rubric,
            members=[{'id': 11, 'name': 'Student A'}, {'id': 12, 'name': 'Student B'}])
        session, _, verdict, _, _ = self.run_panel(teams=[team], args={'min_score': 8, 'max_score': 8})
        items = session.post.call_args.kwargs['json']['submissions']
        self.assertEqual([i['student_id'] for i in items], [None, 11, 12])
        self.assertEqual([i['criteria_scores'][0]['score'] for i in items], [4, 80, 80])
        verdict.assert_not_called()

    def test_configured_concept_assessments_keep_separate_scores_and_chair_selection(self):
        rubric = {'target_type': 'both', 'criteria': [
            {'id': 1, 'target_type': 'team', 'max_score': 10},
            {'id': 2, 'target_type': 'individual', 'max_score': 5},
        ]}
        team = self.panelist_schedule_payload(panel_rubric=rubric,
            assessment_concepts=[{'key': 'c1', 'title': 'One'}, {'key': 'c2', 'title': 'Two'}],
            members=[{'id': 11, 'name': 'A'}, {'id': 12, 'name': 'B'}])
        session, _, verdict, result, output = self.run_panel(teams=[team], args={'min_score': 8, 'max_score': 8})
        rows = session.post.call_args.kwargs['json']['submissions']
        self.assertEqual([(r['concept_key'], r['student_id']) for r in rows],
            [('c1', None), ('c1', 11), ('c1', 12), ('c2', None), ('c2', 11), ('c2', 12)])
        self.assertEqual([r['criteria_scores'][0]['score'] for r in rows], [8, 4, 4, 8, 4, 4])
        verdict.assert_not_called()
        self.assertEqual(result, 0)
        self.assertIn('chair must review the concepts', output)

    def test_invalid_cli_ranges_and_conflicting_modes_are_rejected_before_discovery(self):
        for flags in [
            ['--min-score', '-1'], ['--max-score', '11'], ['--min-score', 'nan'],
            ['--min-score', '9', '--max-score', '7'], ['--delay', '-1'],
            ['--external-only', '--panelists', 'panel'], ['--verdict-only', '--no-verdict'],
        ]:
            with self.subTest(flags=flags), patch.object(sys, 'argv', ['auto_panelist_eval.py', *flags]), \
                    redirect_stdout(StringIO()), patch('sys.stderr', new=StringIO()), self.assertRaises(SystemExit) as error:
                auto_panelist_eval.parse_args()
            self.assertEqual(error.exception.code, 2)

    def test_year_selects_the_requested_cohort_and_cli_defaults_to_api_outcome(self):
        args = auto_panelist_eval.parse_args(['--all-panelists', '--scope', 'pit', '--year', '1'])
        self.assertEqual(args.year, '1st Year')
        self.assertEqual(args.verdict, 'auto')
        session, _, verdict, _, _ = self.run_panel(args={'year': '2nd Year'})
        session.post.assert_not_called()
        verdict.assert_not_called()

    def test_drafts_are_skipped_unless_explicitly_preserved_and_completed(self):
        team = self.panelist_schedule_payload(draft={'submissions': [
            {'student_id': None, 'criteria_scores': [{'criterion_id': 1, 'score': 0}], 'remarks': 'My saved feedback.'}]})
        session, _, _, result, output = self.run_panel(teams=[team])
        session.post.assert_not_called()
        self.assertEqual(result, 2)
        self.assertIn('--include-drafts', output)
        session, _, _, _, _ = self.run_panel(teams=[team], args={'include_drafts': True})
        row = session.post.call_args.kwargs['json']['submissions'][0]
        self.assertEqual(row['criteria_scores'], [{'criterion_id': 1, 'score': 0}])
        self.assertEqual(row['remarks'], 'My saved feedback.')

    def test_individual_draft_keeps_existing_scores_and_fills_missing_members(self):
        team = self.panelist_schedule_payload(panel_rubric={'target_type': 'individual', 'criteria': [
            {'id': 1, 'max_score': 5}, {'id': 2, 'max_score': 100}]},
            members=[{'id': 11}, {'id': 12}], draft={'submissions': [
                {'student_id': 11, 'criteria_scores': [{'criterion_id': 1, 'score': 0}], 'remarks': 'Saved'}]})
        rows = auto_panelist_eval.build_submissions(team, 8, 8, 'Generated', include_drafts=True)
        self.assertEqual(rows[0], {'student_id': 11, 'criteria_scores': [
            {'criterion_id': 1, 'score': 0}, {'criterion_id': 2, 'score': 80}], 'remarks': 'Saved'})
        self.assertEqual(rows[1]['student_id'], 12)
        self.assertEqual(rows[1]['criteria_scores'][0]['score'], 4)

    def test_invalid_or_obsolete_draft_scores_are_never_submitted(self):
        for scores in [[{'criterion_id': 999, 'score': 8}], [{'criterion_id': 1, 'score': float('nan')}],
                       [{'criterion_id': 1, 'score': 11}], [{'criterion_id': 1, 'score': 8}] * 2]:
            with self.subTest(scores=scores):
                team = self.panelist_schedule_payload(draft={'submissions': [
                    {'student_id': None, 'criteria_scores': scores}]})
                session, _, verdict, result, _ = self.run_panel(teams=[team], args={'include_drafts': True})
                session.post.assert_not_called()
                verdict.assert_not_called()
                self.assertEqual(result, 2)

    def test_missing_members_or_concept_keys_cannot_create_incomplete_grades(self):
        for team in [self.panelist_schedule_payload(members=[], panel_rubric={
                    'target_type': 'individual', 'criteria': [{'id': 1, 'max_score': 10}]}),
                    self.panelist_schedule_payload(assessment_policy={'version': 1, 'per_concept': True})]:
            with self.subTest(team=team):
                session, _, _, result, _ = self.run_panel(teams=[team])
                session.post.assert_not_called()
                self.assertEqual(result, 2)

    def test_legacy_concept_hearing_is_also_left_for_the_chair(self):
        team = self.panelist_schedule_payload(assessment_concepts=[], assessment_policy={'version': 0},
            grade_record={'workflow': {'concept_workflow': {'concepts': [{'key': 'c1'}]}}})
        session, _, verdict, result, _ = self.run_panel(teams=[team])
        session.post.assert_called_once()
        self.assertNotIn('concept_key', session.post.call_args.kwargs['json']['submissions'][0])
        verdict.assert_not_called()
        self.assertEqual(result, 0)

    def test_current_context_and_completed_state_are_refreshed_before_submission(self):
        original = self.panelist_schedule_payload()
        fresh = self.panelist_schedule_payload(evaluation_context='new-context')
        session, _, _, _, _ = self.run_panel(args={'no_verdict': True}, get_payloads=[
            {'teams': [original]}, {'teams': [fresh]}])
        self.assertEqual(session.post.call_args.kwargs['json']['evaluation_context'], 'new-context')
        session, _, _, result, _ = self.run_panel(args={'no_verdict': True}, get_payloads=[
            {'teams': [original]}, {'teams': [self.panelist_schedule_payload(is_posted=True)]}])
        session.post.assert_not_called()
        self.assertEqual(result, 0)

    def test_disappearing_assignment_does_not_post_a_stale_grade(self):
        session, _, verdict, result, _ = self.run_panel(get_payloads=[
            {'teams': [self.panelist_schedule_payload()]}, {'teams': []}])
        session.post.assert_not_called()
        verdict.assert_not_called()
        self.assertEqual(result, 1)

    def test_verdict_uses_current_api_allowed_outcome(self):
        for allowed, chosen in [(['approved', 'approved_with_revisions'], 'approved'), (['for_redefense'], 'for_redefense')]:
            with self.subTest(allowed=allowed):
                team = self.panelist_schedule_payload(assessment_policy={'version': 1}, grade_record={'workflow': {
                    'outcome_rule': {'panel_complete': True, 'allowed_verdicts': allowed}}})
                _, _, verdict, result, _ = self.run_panel(teams=[team])
                self.assertEqual(verdict.call_args.kwargs['verdict'], chosen)
                self.assertEqual(result, 0)

    def test_automatic_hearings_never_plan_a_manual_verdict_write(self):
        for complete, outcome in [(False, 'pending'), (True, 'approved'), (True, 'for_redefense')]:
            with self.subTest(complete=complete, outcome=outcome):
                row = self.panelist_schedule_payload(assessment_policy={'version': 1, 'automatic_outcomes': True},
                    grade_record={'workflow': {'outcome_rule': {
                        'automatic': True, 'panel_complete': complete, 'outcome': outcome}}})
                state, explanation, verdict = auto_panelist_eval.plan_verdict(row, 'approved')
                self.assertIn(state, ('existing', 'manual'))
                self.assertIsNone(verdict)

    def test_incomplete_cutoff_or_disallowed_verdict_stays_pending(self):
        for row, requested in [
            (self.panelist_schedule_payload(can_issue_verdict=False), 'auto'),
            (self.panelist_schedule_payload(assessment_policy={'version': 1}), 'auto'),
            (self.panelist_schedule_payload(grade_record={'workflow': {'outcome_rule': {
                'panel_complete': False, 'allowed_verdicts': []}}}), 'auto'),
            (self.panelist_schedule_payload(grade_record={'workflow': {'outcome_rule': {
                'panel_complete': True, 'allowed_verdicts': ['for_redefense']}}}), 'approved'),
        ]:
            with self.subTest(row=row, requested=requested):
                _, _, verdict, result, _ = self.run_panel(teams=[row], args={'verdict': requested})
                verdict.assert_not_called()
                self.assertEqual(result, 2)

    def test_no_chair_does_not_use_an_admin_fallback(self):
        _, _, verdict, result, output = self.run_panel(chair=None)
        verdict.assert_not_called()
        self.assertEqual(result, 2)
        self.assertIn('Assign one active panel chair', output)

    def test_rate_limit_or_auth_failure_stops_remaining_evaluators_and_verdicts(self):
        for status in (401, 429):
            with self.subTest(status=status):
                session, _, verdict, result, output = self.run_panel(status_code=status,
                    faculty=['panelist-a', 'panelist-b'])
                session.post.assert_called_once()
                verdict.assert_not_called()
                self.assertEqual(result, 1)
                self.assertIn('[STOPPED]', output)

    def test_rate_limit_during_verdict_stops_remaining_verdicts(self):
        auto_panelist_eval.fetch_target_schedule_ids.return_value = [101, 102]
        _, _, verdict, result, output = self.run_panel(args={'verdict_only': True}, teams=[
            self.panelist_schedule_payload(schedule_id=101), self.panelist_schedule_payload(schedule_id=102)],
            verdict_result={'status': 'error', 'code': 429, 'detail': 'Rate limited.'})
        verdict.assert_called_once()
        self.assertEqual(result, 1)
        self.assertIn('[STOPPED]', output)


if __name__ == '__main__':
    unittest.main()
