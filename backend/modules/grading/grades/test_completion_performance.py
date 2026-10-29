"""Completion reuses its cohort while preserving fresh commit validation."""
from decimal import Decimal
from time import perf_counter
from unittest.mock import patch

from django.db import connection
from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from . import services
from . import test_workflow_completion as fixtures
from . import tests as grade_fixtures
from .corrections import evaluator_completion
from .models import TeamGrade


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class CompletionPerformanceTests(APITestCase):
    setUp = fixtures.WorkflowCompletionTests.setUp
    _rubric = fixtures.WorkflowCompletionTests._rubric
    new_hearing = fixtures.WorkflowCompletionTests.new_hearing
    submit = fixtures.WorkflowCompletionTests.submit
    approve = fixtures.WorkflowCompletionTests.approve
    accepted_files = fixtures.WorkflowCompletionTests.accepted_files

    def test_evaluator_graph_is_loaded_for_the_cohort(self):
        self.approve()
        grades = services._completion_grade_rows(TeamGrade.objects.filter(pk=self.grade.pk))
        with self.assertNumQueries(0):
            self.assertEqual(evaluator_completion(grades[0]), {'submitted': 1, 'required': 1})

    def test_commit_classifies_once_and_response_reflects_published_grades(self):
        self.approve()
        self.accepted_files()
        params = {'scope': 'capstone', 'stage_label': self.stage.label}
        with CaptureQueriesContext(connection) as preview_queries:
            started = perf_counter()
            preview = self.client.get('/api/grading/grades/group-settings/', params)
            preview_seconds = perf_counter() - started
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['can_complete'])
        self.assertFalse(any(query['sql'].lstrip().upper().startswith(
            ('INSERT', 'UPDATE', 'DELETE')) for query in preview_queries))
        with patch.object(services, 'cohort_grading_teams_for_group',
                          wraps=services.cohort_grading_teams_for_group) as classify:
            with CaptureQueriesContext(connection) as commit_queries:
                started = perf_counter()
                response = self.client.patch('/api/grading/grades/group-settings/', {
                    **params, 'is_officially_complete': True,
                    'completion_token': preview.data['completion_token'],
                }, format='json')
                commit_seconds = perf_counter() - started
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(classify.call_count, 1)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.status, TeamGrade.STATUS_PUBLISHED)
        settings = next(iter(response.data['group_settings'].values()))
        self.assertTrue(settings['is_officially_complete'])
        self.assertEqual(settings['grading_ready_team_count'], 1)
        print(f'Completion benchmark: preview={len(preview_queries)} queries/{preview_seconds:.3f}s; '
              f'commit={len(commit_queries)} queries/{commit_seconds:.3f}s')


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PitCompletionPayloadTests(APITestCase):
    setUp = grade_fixtures.GradeCenterApiTests.setUp
    _rubric = grade_fixtures.GradeCenterApiTests._rubric
    _ensure_pit_event_config = grade_fixtures.GradeCenterApiTests._ensure_pit_event_config
    _record_panel_evaluations = grade_fixtures.GradeCenterApiTests._record_panel_evaluations

    def test_pit_lead_can_complete_with_the_untokened_preview_payload(self):
        self.pit_team.semester = self.semester
        self.pit_team.save(update_fields=['semester'])
        self.pit_schedule.semester = self.semester
        self.pit_schedule.save(update_fields=['semester'])
        event = self._ensure_pit_event_config()
        grade, _, _ = services.GradeContextService.get_or_create_for_schedule(self.pit_schedule)
        grade.panel_score = Decimal('90')
        grade.peer_score = Decimal('80')
        grade.peer_score_is_override = True
        grade.save()
        self._record_panel_evaluations(grade)
        self.client.force_authenticate(self.pit_lead)
        endpoint = '/api/grading/grades/group-settings/?workspace=operations'
        params = {'scope': 'pit', 'stage_label': event.event_name}
        preview = self.client.get(endpoint, params)
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['can_complete'], preview.data)
        self.assertIsNone(preview.data['completion_token'])
        # This is the exact confirmation shape sent by the existing Flutter UI.
        response = self.client.patch(endpoint, {
            **params, 'is_officially_complete': True,
            'completion_token': preview.data['completion_token'], 'failure_grade_ids': [],
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        event.refresh_from_db()
        grade.refresh_from_db()
        self.assertTrue(event.is_officially_complete)
        self.assertEqual(grade.status, TeamGrade.STATUS_PUBLISHED)
