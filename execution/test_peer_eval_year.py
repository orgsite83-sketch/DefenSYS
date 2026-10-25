"""Peer cohort discovery regressions run only in Django's isolated test database.

From the repository root:
  backend/venv/Scripts/python.exe backend/manage.py test execution.test_peer_eval_year --pythonpath . --keepdb --noinput
"""
from contextlib import redirect_stdout
from io import StringIO
import sys
from unittest.mock import Mock, patch

from django.contrib.auth import get_user_model
from django.test import TestCase

from academic_period_management.models import SchoolYear, Semester
from student_teams.models import StudentTeam, TeamMembership

from execution import auto_peer_eval


class PeerYearDiscoveryTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        school_year = SchoolYear.objects.create(label='2098-2099')
        semester = Semester.objects.create(school_year=school_year, label=Semester.FIRST)
        User = get_user_model()
        cls.second = User.objects.create(username='a-second', role='student')
        cls.first = User.objects.create(username='b-first', role='student')
        cls.shared = User.objects.create(username='c-shared', role='student')
        User.objects.create(username='d-unassigned', role='student')
        cls.first_team = StudentTeam.objects.create(name='Peer Year One', level=StudentTeam.LEVEL_1_PIT,
            year_level='1st Year', semester=semester, leader=cls.first)
        cls.second_team = StudentTeam.objects.create(name='Peer Year Two', level=StudentTeam.LEVEL_2_PIT,
            year_level='2nd Year', semester=semester, leader=cls.second)
        extra = StudentTeam.objects.create(name='Peer Year One Extra', level=StudentTeam.LEVEL_1_PIT,
            year_level='1st Year', semester=semester, leader=cls.first)
        TeamMembership.objects.bulk_create([
            TeamMembership(team=cls.first_team, student=cls.first),
            TeamMembership(team=cls.first_team, student=cls.shared),
            TeamMembership(team=cls.second_team, student=cls.second),
            TeamMembership(team=cls.second_team, student=cls.shared),
            TeamMembership(team=extra, student=cls.first),
        ])

    def usernames(self, **filters):
        return [username for username, _ in auto_peer_eval.fetch_student_records(**filters)]

    def test_year_excludes_other_cohorts_and_deduplicates_multiple_memberships(self):
        self.assertEqual(self.usernames(year='1st Year'), ['b-first', 'c-shared'])
        self.assertEqual(self.usernames(year='2nd Year'), ['a-second', 'c-shared'])
        self.assertEqual(self.usernames(), ['a-second', 'b-first', 'c-shared', 'd-unassigned'])

    def test_year_intersects_student_and_team_filters_on_the_same_membership(self):
        self.assertEqual(self.usernames(year='1st Year', specific_usernames=['a-second', 'b-first']), ['b-first'])
        self.assertEqual(self.usernames(year='1st Year', team_id=self.first_team.pk), ['b-first', 'c-shared'])
        self.assertEqual(self.usernames(year='1st Year', team_id=self.second_team.pk), [])
        self.assertEqual(self.usernames(year='1st Year', team_id=self.first_team.pk,
            specific_usernames=['a-second', 'c-shared']), ['c-shared'])

    def test_year_filters_discovery_before_limit_and_authentication(self):
        client = Mock()
        client.authenticate.return_value = False
        args = ['auto_peer_eval.py', '--all-students', '--year', '1', '--limit', '1', '--dry-run']
        with patch.object(sys, 'argv', args), \
                patch.object(auto_peer_eval, 'StudentClient', return_value=client) as clients, \
                redirect_stdout(StringIO()):
            auto_peer_eval.run()
        clients.assert_called_once_with('http://127.0.0.1:8000', 'b-first', 'b-first')
        client.submit_evaluation.assert_not_called()

    def test_automation_includes_required_self_rating_and_skips_existing_pairs(self):
        for submitted_ids, expected_ids in [
            ([], [self.first.pk, self.shared.pk]),
            ([self.shared.pk], [self.first.pk]),
            ([self.first.pk, self.shared.pk], []),
        ]:
            with self.subTest(submitted_ids=submitted_ids):
                client = Mock()
                client.authenticate.return_value = True
                client.get_dashboard.return_value = {
                    'student': {'id': self.first.pk},
                    'team': {'id': self.first_team.pk, 'yearLevel': '1st Year', 'members': [
                        {'id': self.first.pk, 'name': 'First Student'},
                        {'id': self.shared.pk, 'name': 'Shared Student'},
                    ]},
                    'peerEvalEnabled': True,
                    'current_stage': 'Peer test event',
                    'peerCriteria': [{'name': 'Contribution', 'maxScore': 10}],
                    'myPeerSubmissions': [{'evaluateeId': pk} for pk in submitted_ids],
                }
                args = ['auto_peer_eval.py', '--all-students', '--year', '1', '--limit', '1', '--dry-run']
                with patch.object(sys, 'argv', args), \
                        patch.object(auto_peer_eval, 'StudentClient', return_value=client), \
                        patch.object(auto_peer_eval.time, 'sleep'), redirect_stdout(StringIO()):
                    auto_peer_eval.run()
                self.assertEqual([call.args[0]['evaluateeId'] for call in client.submit_evaluation.call_args_list],
                                 expected_ids)
                for call in client.submit_evaluation.call_args_list:
                    self.assertTrue(call.kwargs['dry_run'])
