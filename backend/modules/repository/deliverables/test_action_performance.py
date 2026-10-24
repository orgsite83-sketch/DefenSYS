"""Review responses should cost one team, regardless of cohort size."""
from time import perf_counter
from unittest.mock import patch

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from defense.scheduler.models import PitEventDeliverable, PitEventGradingConfig
from student_teams.models import StudentTeam
from user_management.models import SectionInstructorAssignment
from .models import DeliverableSubmission
from .services import counts_payload, team_payload, team_queryset_for_user
from . import test_submission_timing as timing_tests


class DeliverableActionPerformanceTests(APITestCase):
    setUp = timing_tests.faculty_review_setup
    upload = timing_tests.SubmissionTimingTests.upload

    def configure_pit(self):
        self.team.level = StudentTeam.LEVEL_1_PIT
        self.team.year_level = '1st Year'
        self.team.section = 'BSIT-1A'
        self.team.adviser = None
        self.team.save()
        self.adviser.is_adviser = False
        self.adviser.save()
        SectionInstructorAssignment.objects.create(
            faculty=self.adviser, semester=self.semester, year_level='1st Year', section=self.team.section,
        )
        event = PitEventGradingConfig.objects.create(
            semester=self.semester, year_level='1st Year', event_name=self.stage.label,
        )
        PitEventDeliverable.objects.create(
            pit_event_config=event, deliverable_id='PAPER', label='Concept paper', required=True,
        )

    def action(self, name='review', *, partial=True, **params):
        self.client.force_authenticate(self.adviser)
        query = {'stage_label': self.stage.label, 'scope': 'pit' if self.team.is_pit else 'capstone', **params}
        if partial:
            query['response_mode'] = 'team'
        body = {'team_id': self.team.pk, 'stage_label': self.stage.label}
        if name == 'review':
            body.update(deliverable_id='PAPER', status='accepted')
        with CaptureQueriesContext(connection) as queries:
            started = perf_counter()
            response = self.client.post(
                f'/api/repository/deliverables/{name}/', body, format='json', query_params=query,
            )
            elapsed = perf_counter() - started
        self.assertEqual(response.status_code, 200, response.data)
        return response.data, len(queries), elapsed

    def assert_cohort_independent_actions(self):
        self.upload('PAPER', 'paper.docx')
        first, single_queries, _ = self.action()
        paper = next(item for item in first['team']['selected_stage']['pre'] if item['id'] == 'PAPER')
        self.assertEqual(paper['submission']['status'], 'accepted')
        self.assertEqual(first['team']['counts']['ready'], 1)
        for i in range(7):
            StudentTeam.objects.create(
                name=f'Performance team {i}', project_title=f'Project {i}',
                level=self.team.level, year_level=self.team.year_level, section=self.team.section,
                semester=self.semester, leader=self.student, adviser=self.team.adviser,
                status=StudentTeam.STATUS_APPROVED,
            )
        if self.team.is_pit:
            # The first review pins the event roster. Expand the test fixture's
            # explicit rosters too, rather than benchmarking seven invisible teams.
            from student_teams.models import PITSectionRoster, PITEventRoster
            cohort = StudentTeam.objects.filter(semester=self.semester, year_level=self.team.year_level,
                                                 section=self.team.section)
            current, _ = PITSectionRoster.objects.get_or_create(semester=self.semester,
                year_level=self.team.year_level, section=self.team.section)
            current.teams.set(cohort)
            event = PitEventGradingConfig.objects.get(semester=self.semester,
                year_level=self.team.year_level, event_name=self.stage.label)
            roster, _ = PITEventRoster.objects.get_or_create(event=event, section=self.team.section)
            roster.teams.set(cohort)
        partial, many_queries, partial_seconds = self.action()
        self.assertNotIn('teams', partial)
        self.assertLessEqual(many_queries, single_queries + 2)
        full, full_queries, full_seconds = self.action(partial=False)
        self.assertEqual(len(full['teams']), 8)
        self.assertLess(many_queries, full_queries / 2)
        scope = 'pit' if self.team.is_pit else 'capstone'
        queryset = team_queryset_for_user(self.adviser)
        self.assertEqual(full['counts'], counts_payload(queryset, selected_stage=self.stage.label))
        print(f'Action benchmark ({scope}, 8 teams): full={full_queries} queries/{full_seconds:.3f}s; '
              f'team={many_queries} queries/{partial_seconds:.3f}s')

        endorsed, _, _ = self.action('endorse')
        self.assertTrue(endorsed['team']['selected_stage']['endorsed'])
        self.assertEqual(endorsed['team']['ready_for_stage'], self.stage.label)
        cancelled, _, _ = self.action('unendorse')
        self.assertFalse(cancelled['team']['selected_stage']['endorsed'])

    def test_capstone_action_query_cost_does_not_grow_with_cohort(self):
        self.assert_cohort_independent_actions()

    def test_pit_instructor_action_query_cost_does_not_grow_with_cohort(self):
        self.configure_pit()
        self.assert_cohort_independent_actions()

    def test_review_skips_file_processing_and_preserves_upload_time(self):
        paper = self.upload('PAPER', 'paper.docx')
        uploaded_at = paper.uploaded_at
        DeliverableSubmission.objects.filter(pk=paper.pk).update(extracted_text='')
        with patch('repository.deliverables.pdf_processor.extract_pdf_from_file_object') as extraction:
            self.action()
        extraction.assert_not_called()
        paper.refresh_from_db()
        self.assertEqual(paper.uploaded_at, uploaded_at)
        self.assertEqual(paper.status, 'accepted')
        self.assertEqual(paper.reviewed_by, self.adviser)

    def test_partial_response_removes_team_from_pending_filter_after_acceptance(self):
        self.upload('PAPER', 'paper.docx')
        result, _, _ = self.action(status='pending_review')
        self.assertFalse(result['matches_filters'])

    def test_partial_response_preserves_requested_stage(self):
        from defense.stages.models import DefenseStage, StageDeliverable
        second = DefenseStage.objects.create(label='Performance stage', display_order=99, is_active=True)
        StageDeliverable.objects.create(defense_stage=second, deliverable_id='OTHER', label='Other paper')
        self.upload('PAPER', 'paper.docx')
        result, _, _ = self.action(stage_label=second.label)
        self.assertEqual(result['team']['selected_stage']['stage_label'], second.label)

    def test_selected_stage_is_serialized_once_and_prefetched_files_are_reused(self):
        self.upload('PAPER', 'paper.docx')
        team = team_queryset_for_user(self.adviser).get(pk=self.team.pk)
        from . import services
        from defensys_backend.read_projection import read_projection
        with read_projection():
            with patch.object(services, 'stage_payload', wraps=services.stage_payload) as serialize:
                result = team_payload(team, selected_stage=self.stage.label, evaluator=self.adviser)
            self.assertEqual(sum(call.args[1] == self.stage.label for call in serialize.call_args_list), 1)
            self.assertEqual(result['submitted_count'], 1)
            from .services import submissions_for, submission_payload
            with self.assertNumQueries(0):
                submission_payload(submissions_for(team, self.stage.label)['PAPER'])

    def test_partial_response_does_not_bypass_team_permissions(self):
        self.upload('PAPER', 'paper.docx')
        self.client.force_authenticate(self.student)
        response = self.client.post('/api/repository/deliverables/review/?response_mode=team', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'deliverable_id': 'PAPER', 'status': 'accepted',
        }, format='json')
        self.assertEqual(response.status_code, 403)
        self.team.adviser = None
        self.team.save()
        self.client.force_authenticate(self.adviser)
        response = self.client.post('/api/repository/deliverables/review/?response_mode=team', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'deliverable_id': 'PAPER', 'status': 'accepted',
        }, format='json')
        self.assertEqual(response.status_code, 404)
