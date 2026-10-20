"""Authorization, stale writes and numeric results for PIT concept selection."""
from decimal import Decimal
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from defense.scheduler.models import SchedulePanelist
from grading.grades.models import TeamGrade
from grading.grades.services import (GradeContextService, submit_panelist_grade, group_completion_readiness,
                                     StageCompletionService, IncompleteGradingTeamsError)
from . import concepts, pit_decisions
from .models import ConceptRound
from .services import upsert_submission, review_submission
from .test_pit_concepts import PitConceptTests


class PitConceptDecisionTests(APITestCase):
    setUp = PitConceptTests.setUp
    rubric = PitConceptTests.rubric
    data = PitConceptTests.data
    slot = PitConceptTests.slot
    configure = PitConceptTests.configure
    prepare = PitConceptTests.prepare
    titles = PitConceptTests.titles
    schedule = PitConceptTests.schedule

    def ready(self, *, evaluated=True):
        self.prepare()
        schedule = self.schedule()
        grade = TeamGrade.objects.get(schedule=schedule)
        if evaluated:
            submit_panelist_grade(schedule, grade,
                [{'criterion_id': self.panel.criteria.first().pk, 'score': 8}], panelist=self.panelist)
        return schedule, grade

    def request(self, *, actor=None, token=None, decisions=None, action='pit_decision', reason='Recorded concept feedback.'):
        current = concepts.latest_round(self.team, self.event)
        self.client.force_authenticate(actor or self.first)
        return self.client.post('/api/repository/deliverables/concepts/?response_mode=team', {
            'team_id': self.team.pk, 'stage_label': self.event.label, 'action': action,
            'review_token': token if token is not None else pit_decisions.review_token(current),
            'reason': reason,
            'concepts': decisions if decisions is not None else [
                {'key': f'c{i}', 'decision': 'approved' if i == 2 else 'not_selected', 'remarks': ''}
                for i in range(1, 4)],
        }, format='json')

    def test_lead_selects_title_without_changing_scores_or_recording_grade_verdict(self):
        schedule, grade = self.ready()
        grade.refresh_from_db()
        grade.peer_score, grade.peer_score_is_override = Decimal('20'), True
        grade.save()
        before = grade.final_grade
        response = self.request()
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        grade.refresh_from_db()
        current = ConceptRound.objects.get(schedule=schedule)
        self.assertEqual((self.team.project_title, grade.project_title_snapshot), ('PIT proposal 2', 'PIT proposal 2'))
        self.assertEqual((grade.verdict, grade.final_grade, grade.result), ('', before, 'failed'))
        self.assertEqual(current.decided_by, self.first)
        self.assertIsNotNone(current.decided_at)
        workflow = response.data['team']['stages'][0]['concept_workflow']
        self.assertEqual(workflow['selected_title'], 'PIT proposal 2')
        self.assertFalse(workflow['can_record_decision'])
        GradeContextService.publish(grade, user=self.first)
        grade.refresh_from_db()
        self.assertEqual(grade.result, 'failed')

    def test_students_non_chair_panelists_and_other_year_leads_cannot_choose_while_chair_can(self):
        self.ready()
        for actor in (self.team.leader, self.second, self.unassigned):
            with self.subTest(actor=actor.username):
                self.assertIn(self.request(actor=actor).status_code, (403, 404))
        self.assertEqual(concepts.latest_round(self.team, self.event).verdict, '')
        self.assertEqual(self.request(actor=self.panelist).status_code, 200)

    def test_selection_requires_every_panel_evaluation(self):
        schedule, _ = self.ready(evaluated=False)
        self.assertEqual(self.request().status_code, 400)
        grade = TeamGrade.objects.get(schedule=schedule)
        submit_panelist_grade(schedule, grade,
            [{'criterion_id': self.panel.criteria.first().pk, 'score': 8}], panelist=self.panelist)
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.second)
        response = self.request()
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('Every required', str(response.data))

    def test_official_event_completion_requires_selection_and_then_keeps_numeric_grades(self):
        _, grade = self.ready()
        grade.refresh_from_db()
        grade.peer_score, grade.peer_score_is_override = Decimal('86'), True
        grade.save()
        readiness = group_completion_readiness(semester=self.semester, scope='pit', stage_label=self.event.label, user=self.first)
        self.assertFalse(readiness['can_complete'])
        self.assertIn('concept_selection', readiness['incomplete_teams'][0]['missing_components'])
        with self.assertRaises(IncompleteGradingTeamsError):
            StageCompletionService.complete_group(semester=self.semester, scope='pit', stage_label=self.event.label,
                                                  config=self.event, user=self.first)
        self.assertEqual(self.request().status_code, 200)
        post = upsert_submission(self.team, self.event.label, 'APPROVED_CONCEPT', 'approved.pdf', '10 B', self.team.leader,
            file=SimpleUploadedFile('approved.pdf', b'%PDF-1.4 approved concept'))
        review_submission(self.team, self.event.label, 'APPROVED_CONCEPT', 'accepted', '', self.first,
            file_id=post.files.get(is_current=True).pk)
        readiness = group_completion_readiness(semester=self.semester, scope='pit', stage_label=self.event.label, user=self.first)
        self.assertTrue(readiness['can_complete'], readiness)
        StageCompletionService.complete_group(semester=self.semester, scope='pit', stage_label=self.event.label,
                                              config=self.event, user=self.first)
        grade.refresh_from_db()
        self.assertEqual(grade.status, TeamGrade.STATUS_PUBLISHED)
        self.assertEqual(grade.verdict, '')

    def test_multiple_approved_duplicate_unknown_and_malformed_keys_are_atomic(self):
        self.ready()
        original = self.team.project_title
        for rows in (
            [{'key': f'c{i}', 'decision': 'approved'} for i in range(1, 4)],
            [{'key': 'c1', 'decision': 'approved'}] * 3,
            [{'key': ['c1'], 'decision': 'approved'}] * 3,
            [{'key': 'wrong', 'decision': 'not_selected'}] * 3,
        ):
            self.assertEqual(self.request(decisions=rows).status_code, 400)
            self.team.refresh_from_db()
            self.assertEqual(self.team.project_title, original)
            self.assertEqual(concepts.latest_round(self.team, self.event).verdict, '')

    def test_stale_and_repeated_decisions_cannot_overwrite_the_selected_title(self):
        self.ready()
        self.assertEqual(self.request(token='stale').status_code, 400)
        token = pit_decisions.review_token(concepts.latest_round(self.team, self.event))
        self.assertEqual(self.request(token=token).status_code, 200)
        self.assertEqual(self.request(token=token).status_code, 400)
        self.assertEqual(self.request().status_code, 400)

    def test_historical_completed_and_paused_events_reject_changes(self):
        schedule, _ = self.ready()
        schedule.operation_state = 'paused'
        schedule.save()
        self.assertEqual(self.request().status_code, 400)
        schedule.operation_state = 'normal'
        schedule.save()
        self.event.is_officially_complete = True
        self.event.save()
        self.assertEqual(self.request().status_code, 400)
        self.event.is_officially_complete = False
        self.event.save()
        self.semester.is_active = False
        self.semester.save()
        self.assertIn(self.request().status_code, (400, 403, 404))

    def test_pit_verdict_endpoints_stay_disabled_even_when_concepts_are_enabled(self):
        schedule, grade = self.ready()
        for actor in (self.panelist, self.first, self.admin):
            self.client.force_authenticate(actor)
            for url in (f'/api/defense/schedules/{schedule.pk}/verdict/', f'/api/grading/grades/{grade.pk}/verdict/'):
                self.assertIn(self.client.patch(url, {'verdict': 'approved'}, format='json').status_code, (400, 403))
        grade.refresh_from_db()
        self.assertEqual(grade.verdict, '')

    def test_audit_failure_rolls_back_the_title_and_decision(self):
        self.ready()
        current = concepts.latest_round(self.team, self.event)
        original = self.team.project_title
        with patch('repository.deliverables.pit_decisions.audit', side_effect=RuntimeError('Audit unavailable')):
            with self.assertRaises(RuntimeError):
                pit_decisions.record_decision(self.team, self.event, self.first,
                    [{'key': f'c{i}', 'decision': 'approved' if i == 2 else 'not_selected'} for i in range(1, 4)],
                    token=pit_decisions.review_token(current))
        self.team.refresh_from_db()
        self.assertEqual(self.team.project_title, original)
        self.assertEqual(concepts.latest_round(self.team, self.event).verdict, '')

    def test_revisions_block_completion_until_required_documents_are_accepted(self):
        self.configure(deliverables=[
            {'deliverable_id': 'CONCEPTS', 'label': 'Concept papers', 'required': True,
             'deliverable_type': 'pre', 'is_defense_material': True, 'file_policy': {'mode': 'concepts'}},
            {'deliverable_id': 'APPROVED_PAPER', 'label': 'Approved concept paper', 'required': True,
             'deliverable_type': 'post'},
        ])
        _, grade = self.ready()
        response = self.request(decisions=[
            {'key': f'c{i}', 'decision': 'approved_with_revisions' if i == 2 else 'not_selected',
             'remarks': 'Clarify the proposed module.' if i == 2 else ''} for i in range(1, 4)])
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(pit_decisions.completion_blocker(grade))
        self.assertEqual(self.request(action='clear_pit_revisions').status_code, 400)
        current = concepts.latest_round(self.team, self.event)
        submission = self.team.deliverable_submissions.get(deliverable_id='CONCEPTS')
        file = submission.files.get(slot_key='c2:paper', is_current=True)
        self.assertEqual(file.status, 'accepted')
        self.assertEqual(submission.files.get(slot_key='c1:paper', is_current=True).status, 'accepted')
        post_sub = upsert_submission(self.team, self.event.label, 'APPROVED_PAPER', 'approved_c2.pdf', '10 B',
            self.team.leader, file=SimpleUploadedFile('approved_c2.pdf', b'approved paper content'))
        post_file = post_sub.files.first()
        review_submission(self.team, self.event.label, 'APPROVED_PAPER', 'accepted', 'Revisions accepted', self.first, file_id=post_file.pk)
        current.refresh_from_db()
        self.assertEqual(current.revisions_cleared_by, self.first)
        self.assertFalse(pit_decisions.completion_blocker(grade))
