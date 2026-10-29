"""Stage setup reads retain history filters without building every team dossier."""
from unittest.mock import patch

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from academic_period_management import tests_capstone_transition as fixtures
from student_teams.capstone_history import history_payload
from student_teams.models import TeamTermParticipation


class StageSetupReadPerformanceTests(APITestCase):
    setUp = fixtures.CapstoneTransitionTests.setUp
    make_team = fixtures.CapstoneTransitionTests.make_team
    enroll = fixtures.CapstoneTransitionTests.enroll
    assess = fixtures.CapstoneTransitionTests.assess
    preview = fixtures.CapstoneTransitionTests.preview
    activate = fixtures.CapstoneTransitionTests.activate

    def continue_team(self):
        self.assess(self.team, self.first)
        self.assess(self.team, self.second)
        self.assertEqual(self.activate(self.normal).status_code, 200)
        self.team.refresh_from_db()

    def test_setup_never_builds_team_dossiers(self):
        self.continue_team()
        before = list(TeamTermParticipation.objects.values())
        with patch('student_teams.capstone_history.stage_context', side_effect=AssertionError('stage clearance')):
            with patch('student_teams.capstone_history.team_snapshot', side_effect=AssertionError('live dossier')):
                with patch('student_teams.capstone_history.historical_payload', side_effect=AssertionError('historical dossier')):
                    response = self.client.get('/api/defense/stages/', {'scope': 'history'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual([g['phase'] for g in response.data['phase_groups']], ['capstone_1', 'capstone_2'])
        self.assertTrue(all(g['read_only'] for g in response.data['phase_groups']))
        self.assertEqual(list(TeamTermParticipation.objects.values()), before)

    def test_setup_payload_matches_full_history_with_fewer_queries(self):
        self.continue_team()

        def full_history(visible, params, **kwargs):
            return history_payload(visible, params, user=kwargs.get('user'))

        filters = (
            {},
            {'scope': 'history', 'intake_id': str(self.intake.pk)},
            {'phase': 'capstone_1'},
            {'stage_key': f'{self.intake.pk}:{self.first.pk}'},
            {'semester_id': str(self.normal.pk)},
            {'search': 'Cedar', 'year_level': '3rd Year'},
            {'search': 'missing project'},
            {'status': 'Completed'},
            {'section': 'unrelated section'},
        )
        for params in filters:
            with self.subTest(params=params):
                with patch('student_teams.capstone_history.history_payload', side_effect=full_history):
                    with CaptureQueriesContext(connection) as legacy_queries:
                        expected = self.client.get('/api/defense/stages/', params)
                with CaptureQueriesContext(connection) as queries:
                    actual = self.client.get('/api/defense/stages/', params)
                self.assertEqual(actual.status_code, 200)
                self.assertEqual(actual.data, expected.data)
                if not params:
                    self.assertLess(len(queries), len(legacy_queries))

    def test_setup_history_stays_scoped_to_the_viewer_and_refreshes(self):
        self.continue_team()
        self.client.force_authenticate(self.team.leader)
        response = self.client.get('/api/defense/stages/', {'scope': 'history'})
        self.assertEqual(len(response.data['capstone_history']['intakes']), 1)
        outsider = self.make_team('Other intake', self.extension)
        self.client.force_authenticate(outsider.leader)
        response = self.client.get('/api/defense/stages/', {'scope': 'history'})
        self.assertNotIn(self.intake.pk, [row['id'] for row in response.data['capstone_history']['intakes']])
        self.client.force_authenticate(self.admin)
        self.first.label = 'Updated discovery workshop'
        self.first.save(update_fields=['label'])
        response = self.client.get('/api/defense/stages/')
        self.assertEqual(next(s for s in response.data['stages'] if s['id'] == self.first.pk)['label'], self.first.label)

    def test_participation_read_reuse_is_invalidated_by_grade_writes(self):
        from defensys_backend.read_projection import read_projection
        from grading.grades.models import TeamGrade
        from student_teams.participation import closed_failure

        grade = self.assess(self.team, self.first, verdict='failed', status='pending')
        with read_projection():
            self.assertFalse(closed_failure(self.team))
            with self.assertNumQueries(0):
                self.assertFalse(closed_failure(self.team))
            TeamGrade.all_objects.filter(pk=grade.pk).update(status='published')
            self.assertTrue(closed_failure(self.team))
        TeamGrade.all_objects.filter(pk=grade.pk).update(status='pending')
        with read_projection():
            self.assertFalse(closed_failure(self.team))
