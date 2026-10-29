"""Automatic outcomes reuse real concept, evaluation, and repeat services."""
from django.core.exceptions import ValidationError
from rest_framework.test import APITestCase, APITransactionTestCase

from defense.scheduler.models import SchedulePanelist
from repository.deliverables.models import ConceptRound
from . import test_outcome_rules as fixtures
from .automatic_outcomes import resolve_outcome, save_recommendations
from .defense_workflow import record_verdict
from .outcome_rules import outcome_payload
from .services import group_completion_readiness, update_group_settings


class AutomaticConceptOutcomeTests(APITestCase):
    _rubric = fixtures.PerConceptOutcomeTests._rubric
    prepare = fixtures.PerConceptOutcomeTests.prepare
    scores = fixtures.PerConceptOutcomeTests.scores
    submit = fixtures.PerConceptOutcomeTests.submit
    post = fixtures.PerConceptOutcomeTests.post

    def setUp(self):
        fixtures.PerConceptOutcomeTests.setUp(self)
        self.capstone_schedule.assessment_policy['automatic_outcomes'] = True
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        self.grade.refresh_from_db()

    def test_only_qualifying_concept_is_selected_without_chair_verdict(self):
        self.submit([6, 7.5, 7])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panel_score, 75)
        self.assertIsNone(self.grade.verdict_by)
        self.assertEqual(self.grade.outcome_metadata['source'], 'automatic')
        self.assertEqual(ConceptRound.objects.get(schedule=self.capstone_schedule).concepts[1]['decision'], 'approved')

    def test_multiple_qualifying_concepts_require_current_chair_selection(self):
        self.submit([8, 9, 6])
        self.assertEqual(self.grade.verdict, '')
        self.assertIsNone(self.grade.panel_score)
        rule = outcome_payload(self.grade)
        with self.assertRaises(PermissionError):
            resolve_outcome(self.grade, actor=self.admin, selected_key='c1', review_token=rule['review_token'])
        with self.assertRaises(ValidationError):
            resolve_outcome(self.grade, actor=self.panelist, selected_key='c1', review_token='stale')
        result = resolve_outcome(self.grade, actor=self.panelist, selected_key='c1', review_token=rule['review_token'])
        self.assertEqual(result.panel_score, 80)
        self.assertIsNone(result.verdict_by)
        self.assertEqual(result.outcome_metadata['selected_by'], self.panelist.pk)

    def test_no_qualifying_concept_prepares_same_set_without_feedback_gate(self):
        self.submit([5, 6, 7])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'for_redefense')
        self.assertEqual(self.grade.verdict_remarks, '')
        following = ConceptRound.objects.get(team=self.capstone_team, number=2)
        self.assertEqual([c['key'] for c in following.concepts], ['c1', 'c2', 'c3'])
        self.assertTrue(all(c['title'] for c in following.concepts))
        self.assertTrue(all(c['requested_action'] == 'revise' for c in following.concepts))
        original_snapshot = ConceptRound.objects.get(schedule=self.capstone_schedule).documents_snapshot
        resolve_outcome(self.grade)
        save_recommendations(self.grade, actor=self.panelist, notes='Improve the evidence.')
        save_recommendations(self.grade, actor=self.panelist, notes='')
        self.assertEqual(ConceptRound.objects.filter(team=self.capstone_team).count(), 2)
        self.assertEqual(ConceptRound.objects.get(schedule=self.capstone_schedule).documents_snapshot, original_snapshot)

    def test_incomplete_panel_stays_pending(self):
        other = self.panelist.__class__.objects.create_user(username='auto-extra-panel', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=other)
        self.submit([8, 6, 7])
        self.assertEqual(self.grade.verdict, '')
        self.assertFalse(outcome_payload(self.grade)['panel_complete'])

    def test_selection_review_token_changes_with_hearing_revision(self):
        self.submit([8, 9, 6])
        token = outcome_payload(self.grade)['review_token']
        self.capstone_schedule.revision += 1
        self.capstone_schedule.save(update_fields=['revision'])
        with self.assertRaises(ValidationError):
            resolve_outcome(self.grade, actor=self.panelist, selected_key='c1', review_token=token)

    def adoption_report(self, **options):
        from io import StringIO
        import json
        from django.core.management import call_command
        output = StringIO()
        call_command('automatic_outcome_adoption_report', schedule_id=[self.capstone_schedule.pk], stdout=output, **options)
        return json.loads(output.getvalue())

    def captured_manual_hearing(self):
        # The general grading fixture seeds adviser/peer values. Adoption must
        # be exercised on an actual untouched hearing instead.
        self.grade.adviser_score = self.grade.peer_score = self.grade.final_grade = None
        self.grade.adviser_score_is_override = self.grade.peer_score_is_override = False
        self.grade.save()
        self.capstone_schedule.assessment_policy.pop('automatic_outcomes')
        self.capstone_schedule.save(update_fields=['assessment_policy'])

    def test_reviewed_adoption_only_changes_unstarted_captured_policy(self):
        from authentication_access_control.models import SystemAuditLog
        from copy import deepcopy
        self.captured_manual_hearing()
        before = deepcopy(self.capstone_schedule.assessment_policy)
        report = self.adoption_report()
        self.assertTrue(report['read_only'])
        self.assertTrue(report['hearings'][0]['eligible'], report)
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.capstone_schedule.assessment_policy, before)
        result = self.adoption_report(apply=True, review_token=report['review_token'], reason='Reviewed unstarted rollout.')
        self.assertEqual(result['adopted_count'], 1)
        self.capstone_schedule.refresh_from_db()
        policy = self.capstone_schedule.assessment_policy.copy()
        self.assertTrue(policy.pop('automatic_outcomes'))
        policy.pop('automatic_outcome_adoption')
        self.assertEqual(policy, before)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertTrue(SystemAuditLog.objects.filter(action='defense.automatic_policy_adopted').exists())

    def test_adoption_rejects_started_assessment_and_stale_review(self):
        from django.core.management.base import CommandError
        self.captured_manual_hearing()
        report = self.adoption_report()
        with self.assertRaises(CommandError):
            self.adoption_report(apply=True, review_token='stale', reason='Reviewed rollout.')
        self.submit([8, 9, 6])
        current = self.adoption_report()
        self.assertFalse(current['hearings'][0]['eligible'])
        with self.assertRaises(CommandError):
            self.adoption_report(apply=True, review_token=report['review_token'], reason='Reviewed rollout.')
        self.capstone_schedule.refresh_from_db()
        self.assertNotIn('automatic_outcomes', self.capstone_schedule.assessment_policy)

    def test_manual_service_and_both_api_routes_cannot_override_automatic_hearing(self):
        self.submit([8, 9, 6])
        with self.assertRaises(ValidationError):
            record_verdict(self.grade, actor=self.admin, verdict='failed', remarks='Override')
        self.client.force_authenticate(self.admin)
        for path in [f'/api/grading/grades/{self.grade.pk}/verdict/',
                     f'/api/defense/schedules/{self.capstone_schedule.pk}/verdict/']:
            response = self.client.patch(path, {'verdict': 'failed', 'verdict_remarks': 'Override'}, format='json')
            self.assertEqual(response.status_code, 400, response.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')

    def test_api_resolution_and_selection_use_same_service(self):
        result = self.post([8, 9, 6])
        self.assertEqual(result.status_code, 201, result.data)
        self.grade.refresh_from_db()
        rule = outcome_payload(self.grade)
        response = self.client.post(f'/api/grading/grades/{self.grade.pk}/assessment/', {
            'action': 'select_concept', 'concept_key': 'c2', 'review_token': rule['review_token'],
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, 90)

    def closure_preview(self):
        return group_completion_readiness(semester=self.semester, scope='capstone',
            stage_label=self.stage.label, user=self.admin)

    def test_admin_closure_preserves_hearing_and_no_official_numeric_grade(self):
        self.submit([5, 6, 7])
        preview = self.closure_preview()
        self.assertTrue(preview['can_complete'], preview)
        self.assertEqual([r['grade_id'] for r in preview['failure_candidates']], [self.grade.pk])
        params = dict(semester=self.semester, scope='capstone', stage_label=self.stage.label,
            user=self.admin, is_officially_complete=True)
        with self.assertRaises(ValidationError):
            update_group_settings(**params)
        update_group_settings(**params, failure_grade_ids=[self.grade.pk], closure_reason='Assessment window closed.',
            completion_token=preview['completion_token'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.result, 'failed')
        self.assertEqual(self.grade.verdict, 'for_redefense')
        self.assertEqual(self.grade.status, 'published')
        self.assertIsNone(self.grade.panel_score)
        self.assertIsNone(self.grade.final_grade)
        self.assertEqual(self.grade.outcome_metadata['closure']['actor_id'], self.admin.pk)
        from .views import counts_payload
        self.assertEqual(counts_payload(self.grade.__class__.objects.filter(pk=self.grade.pk))['failed'], 1)
        from defense.scheduler.progress import schedule_progress
        self.capstone_schedule.refresh_from_db()
        progress = schedule_progress(self.capstone_schedule, reconcile_status=False)
        self.assertEqual(progress['verdict'], 'failed')
        self.assertEqual(progress['hearing_outcome'], 'for_redefense')
        from reports.concept_reports import decision_row
        hearing = ConceptRound.objects.get(schedule=self.capstone_schedule)
        self.assertEqual(decision_row(self.capstone_team, hearing, hearing.concepts[0], self.grade,
                                     latest=False)['status'], 'Failed (stage closure)')
        from defense.scheduler.serializers import ScheduleTeamSerializer
        summary = ScheduleTeamSerializer(self.capstone_team).data
        self.assertEqual(summary['stage_verdicts'][self.stage.label], 'failed')
        self.assertNotIn(self.stage.label, summary['redefense_stages'])
        from student_teams.models import TeamStageProgress
        self.assertEqual(TeamStageProgress.objects.get(team=self.capstone_team, defense_stage=self.stage).status, 'failed')

    def test_failure_closure_does_not_waive_required_signed_minutes(self):
        from .test_workflow_completion import WorkflowCompletionTests
        WorkflowCompletionTests.require_minutes(self)
        self.submit([5, 6, 7])
        preview = self.closure_preview()
        self.assertFalse(preview['can_complete'])
        self.assertEqual(preview['incomplete_teams'][0]['missing_components'], ['minutes'])
        from .services import IncompleteGradingTeamsError
        params = dict(semester=self.semester, scope='capstone', stage_label=self.stage.label,
            user=self.admin, is_officially_complete=True, failure_grade_ids=[self.grade.pk],
            closure_reason='Assessment window closed.')
        with self.assertRaises(IncompleteGradingTeamsError):
            update_group_settings(**params, completion_token=preview['completion_token'])
        minutes = WorkflowCompletionTests.make_minutes(self, finalized=True)
        preview = self.closure_preview()
        self.assertTrue(preview['can_complete'], preview)
        # A new signing snapshot invalidates consent even if it stays finalized.
        minutes.save()
        with self.assertRaises(ValidationError):
            update_group_settings(**params, completion_token=preview['completion_token'])
        preview = self.closure_preview()
        update_group_settings(**params, completion_token=preview['completion_token'])
        self.grade.refresh_from_db()
        self.assertTrue(self.grade.closed_as_failed)

    def test_closure_rejects_changed_assessment_and_missing_reason(self):
        self.submit([5, 6, 7])
        preview = self.closure_preview()
        params = dict(semester=self.semester, scope='capstone', stage_label=self.stage.label,
            user=self.admin, is_officially_complete=True, failure_grade_ids=[self.grade.pk])
        with self.assertRaises(ValidationError):
            update_group_settings(**params, completion_token=preview['completion_token'])
        save_recommendations(self.grade, actor=self.panelist, notes='Record the remaining corrections.')
        with self.assertRaises(ValidationError):
            update_group_settings(**params, completion_token=preview['completion_token'], closure_reason='Close stage.')
        self.grade.refresh_from_db()
        self.assertFalse(self.grade.closed_as_failed)

    def test_closed_failure_cannot_be_reopened_by_retired_admin_action(self):
        self.submit([5, 6, 7])
        preview = self.closure_preview()
        update_group_settings(semester=self.semester, scope='capstone', stage_label=self.stage.label,
            user=self.admin, is_officially_complete=True, failure_grade_ids=[self.grade.pk],
            closure_reason='Stage window closed.', completion_token=preview['completion_token'])
        self.grade.refresh_from_db()
        from student_teams.services import is_stage_ready, mark_stage_ready
        from repository.deliverables.redefense import preparing
        self.assertFalse(is_stage_ready(self.capstone_team, self.stage))
        self.assertFalse(preparing(self.capstone_team, self.stage))
        with self.assertRaises(ValidationError):
            mark_stage_ready(self.capstone_team, self.stage, self.adviser)
        from .defense_workflow import apply_workflow_action
        with self.assertRaises(ValidationError):
            apply_workflow_action(self.grade, actor=self.admin, action='authorize_retake', reason='Retired action must be rejected.')
        from repository.deliverables.concepts import title_context_is_open
        self.assertFalse(title_context_is_open(self.capstone_team, self.stage))
        self.assertFalse(preparing(self.capstone_team, self.stage))

    def test_active_redefense_blocks_closure_and_preserves_nonfinal_result(self):
        self.submit([5, 6, 7])
        from defense.scheduler.models import DefenseSchedule
        DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date=self.capstone_schedule.scheduled_date,
            start_time='14:00', room='Retake room')
        preview = self.closure_preview()
        self.assertFalse(preview['can_complete'], preview)
        self.assertEqual(preview['failure_candidates'], [])
        self.grade.refresh_from_db()
        self.assertFalse(self.grade.closed_as_failed)

    def test_feedback_before_final_submission_survives_automatic_result(self):
        save_recommendations(self.grade, actor=self.panelist, notes='Strengthen the research evidence.')
        self.submit([5, 6, 7])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict_remarks, 'Strengthen the research evidence.')
        following = ConceptRound.objects.get(team=self.capstone_team, number=2)
        self.assertTrue(all(c['panel_feedback'] == 'Strengthen the research evidence.' for c in following.concepts))

    def test_missing_initial_assessment_is_a_blocker_not_a_final_failure(self):
        from student_teams.models import StudentTeam
        self.submit([5, 6, 7])
        StudentTeam.objects.create(name='Unassessed current-stage team', semester=self.semester,
            leader=self.second_student, adviser=self.adviser, level=self.capstone_team.level,
            year_level=self.capstone_team.year_level, current_defense_stage=self.stage.label)
        preview = self.closure_preview()
        self.assertFalse(preview['can_complete'], preview)
        missing = next(row for row in preview['incomplete_teams'] if row['team_name'] == 'Unassessed current-stage team')
        self.assertEqual(missing['missing_components'], ['initial_assessment'])

    def test_external_panel_final_submission_triggers_resolution(self):
        from authentication_access_control.guest_authentication import GuestPanelistPrincipal
        from user_management.models import GuestPanelistCode
        invitation = GuestPanelistCode.objects.create(guest_name='Automatic external evaluator', defense_schedule=self.capstone_schedule)
        invitation.schedules.add(self.capstone_schedule)
        guest = GuestPanelistPrincipal({'guest_code_id': str(invitation.pk), 'guest_code': invitation.code,
            'defense_schedule_id': self.capstone_schedule.pk, 'team_id': self.capstone_team.pk,
            'guest_name': invitation.guest_name}, invitation=invitation)
        self.submit([8, 7, 6])
        self.assertEqual(self.grade.verdict, '')
        self.client.force_authenticate(guest)
        result = self.client.post('/api/defense/schedules/guest-submit-grades/', {
            'team_id': self.capstone_team.pk, 'schedule_id': self.capstone_schedule.pk,
            'submissions': self.scores([8, 7, 6])}, format='json')
        self.assertEqual(result.status_code, 201, result.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panel_score, 80)

    def shared_round(self):
        from student_teams.models import SectionAssignment
        from repository.section_concepts.models import SectionConceptProject, SectionConceptRound, SectionSystemConcept, SectionProjectTeam
        from django.utils import timezone
        team = self.capstone_team
        team.section = 'BSIT-3A'
        team.save(update_fields=['section'])
        section, _ = SectionAssignment.objects.get_or_create(section=team.section, semester=self.semester,
            year_level=team.year_level)
        project = SectionConceptProject.objects.create(section=section, defense_stage=self.stage,
            project_manager=self.student, reviewer=self.adviser)
        SectionProjectTeam.objects.create(project=project, team=team, project_version=team.project_version)
        section_round = SectionConceptRound.objects.create(project=project, chair=self.panelist,
            presentation_started_at=timezone.now())
        SectionSystemConcept.objects.bulk_create([SectionSystemConcept(round=section_round, key=f'c{i}', title=f'Shared system {i}') for i in range(1, 4)])
        section_round.schedules.add(self.capstone_schedule)
        hearing = ConceptRound.objects.get(schedule=self.capstone_schedule)
        hearing.section_round = section_round
        hearing.save(update_fields=['section_round'])
        return section_round

    def select_shared(self, section_round, key='c2'):
        from unittest.mock import patch
        from repository.section_concepts.services import decide
        # Paper clearance has independent integration coverage. This fixture
        # isolates score/selection coordination on the actual shared write path.
        with patch('repository.section_concepts.services.shared_clearance', return_value=True):
            decide(section_round.project, self.panelist,
                [{'key': f'c{i}', 'decision': 'approved' if f'c{i}' == key else 'not_selected', 'remarks': ''} for i in range(1, 4)],
                'approved', '')

    def test_shared_selection_triggers_only_linked_module_qualification(self):
        section_round = self.shared_round()
        self.submit([9, 6, 9])
        self.assertEqual(self.grade.verdict, '')
        self.select_shared(section_round)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'for_redefense')
        following = ConceptRound.objects.get(team=self.capstone_team, number=2)
        self.assertEqual([c['key'] for c in following.concepts], ['c2'])
        section_round.refresh_from_db()
        self.assertEqual(section_round.selected_key, 'c2')

    def test_shared_selection_automatically_approves_a_qualifying_linked_module(self):
        section_round = self.shared_round()
        self.submit([9, 8, 9])
        self.select_shared(section_round)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panel_score, 80)

    def test_automatic_repeat_uses_existing_title_first_review(self):
        hearing = ConceptRound.objects.get(schedule=self.capstone_schedule)
        hearing.title_workflow_version = 2
        hearing.save(update_fields=['title_workflow_version'])
        self.submit([5, 6, 7])
        following = ConceptRound.objects.get(team=self.capstone_team, number=2)
        self.assertEqual(following.title_workflow_version, 2)
        self.assertTrue(all(c['title_review']['state'] == 'draft' for c in following.concepts))
        from repository.title_workflow import team_action
        team_action(self.capstone_team, self.stage, self.capstone_team.leader, 'submit_title', 'c1', title='Revised concept scope')
        team_action(self.capstone_team, self.stage, self.adviser, 'accept_title', 'c1')
        following.refresh_from_db()
        self.assertEqual(following.concepts[0]['title_review']['state'], 'accepted')
        self.assertEqual(following.concepts[0]['title'], 'Revised concept scope')


class AutomaticStageOutcomeTests(APITestCase):
    _rubric = fixtures.ConfiguredOutcomeTests._rubric
    new_hearing = fixtures.ConfiguredOutcomeTests.new_hearing
    submit = fixtures.ConfiguredOutcomeTests.submit

    def setUp(self):
        fixtures.ConfiguredOutcomeTests.setUp(self)
        self.capstone_schedule.assessment_policy['automatic_outcomes'] = True
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        self.grade.refresh_from_db()

    def test_scalar_stage_qualifies_at_cutoff_without_a_verdict_request(self):
        self.submit(7.5)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panel_score, 75)
        self.assertIsNone(self.grade.verdict_by)

    def test_scalar_stage_requires_redefense_below_cutoff(self):
        self.submit(7.49)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'for_redefense')
        from decimal import Decimal
        self.assertEqual(self.grade.panel_score, Decimal('74.90'))


class AutomaticOutcomeConcurrencyTests(APITransactionTestCase):
    serialized_rollback = True
    _rubric = AutomaticConceptOutcomeTests._rubric
    prepare = AutomaticConceptOutcomeTests.prepare
    scores = AutomaticConceptOutcomeTests.scores
    submit = AutomaticConceptOutcomeTests.submit
    setUp = AutomaticConceptOutcomeTests.setUp

    def _fixture_teardown(self):
        super()._fixture_teardown()
        # Keep --keepdb usable for the existing fixtures that read migration-
        # seeded stages. Restore Django's initial snapshot after the real commit
        # test flushes its rows; no development database is involved.
        from django.db import connections
        for alias in self._databases_names(include_mirrors=False):
            connection = connections[alias]
            if hasattr(connection, '_test_serialized_contents'):
                connection.creation.deserialize_db_from_string(connection._test_serialized_contents)

    def test_simultaneous_chair_choices_record_exactly_one_outcome(self):
        from concurrent.futures import ThreadPoolExecutor
        from threading import Barrier
        from unittest.mock import patch
        from django.db import close_old_connections
        from authentication_access_control.models import SystemAuditLog
        from .models import TeamGrade
        self.submit([8, 9, 6])
        token = outcome_payload(self.grade)['review_token']
        barrier = Barrier(2)

        def select(key):
            close_old_connections()
            try:
                grade = TeamGrade.objects.select_related('schedule').get(pk=self.grade.pk)
                barrier.wait(timeout=10)
                try:
                    resolve_outcome(grade, actor=self.panelist, selected_key=key, review_token=token)
                    return 'recorded'
                except ValidationError:
                    return 'stale'
            finally:
                close_old_connections()

        with patch('realtime.broadcast.notify_capstone_evaluation_flags'), ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(select, ['c1', 'c2']))
        self.assertCountEqual(results, ['recorded', 'stale'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertIn(self.grade.panel_score, [80, 90])
        self.assertEqual(SystemAuditLog.objects.filter(action='defense.outcome_resolved').count(), 1)
