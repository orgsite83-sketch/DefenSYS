"""Panel-only concepts retain real selection, files, minutes, and closure gates."""
from decimal import Decimal

from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.scheduler.progress import schedule_progress
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from student_teams.capstone_lifecycle import capture_participation, configured_requirements, stage_cleared
from . import test_automatic_outcomes as fixtures
from .automatic_outcomes import resolve_outcome
from .availability import adviser_grading_unavailable_reason, peer_grading_unavailable_reason
from .evaluation_policy import PANEL_ONLY_CONCEPT, PANEL_ONLY_WEIGHTS
from .models import TeamGrade
from .outcome_rules import capture_policy, outcome_payload
from .serializers import TeamGradeSerializer, TeamGradeUpdateSerializer
from .services import (adviser_capstone_grades_for_user, group_completion_readiness,
                       team_grading_readiness, update_group_settings)


class PanelOnlyCalculationTests(SimpleTestCase):
    def grade(self, *, mode=PANEL_ONLY_CONCEPT, scope='capstone'):
        schedule = DefenseSchedule(pk=1, scope=scope, assessment_policy={
            'version': 1, 'evaluation_mode': mode, 'weights': dict(PANEL_ONLY_WEIGHTS),
        })
        return TeamGrade(schedule=schedule, scope=scope, panel_score=Decimal('82.75'),
                         **PANEL_ONLY_WEIGHTS)

    def test_panel_only_total_does_not_require_or_multiply_null_peer_scores(self):
        grade = self.grade()
        grade.recalculate()
        self.assertTrue(grade.is_complete)
        self.assertEqual(grade.final_grade, Decimal('82.75'))
        self.assertIsNone(grade.peer_score)
        self.assertIsNone(grade.adviser_score)

    def test_missing_panel_is_pending_even_with_zero_role_weights(self):
        grade = self.grade()
        grade.panel_score = None
        grade.recalculate()
        self.assertFalse(grade.is_complete)
        self.assertEqual(grade.status, 'pending')
        self.assertIsNone(grade.final_grade)

    def test_legacy_and_pit_captures_keep_their_original_completeness_contract(self):
        for mode, scope in [('standard', 'capstone'), (PANEL_ONLY_CONCEPT, 'pit')]:
            with self.subTest(mode=mode, scope=scope):
                grade = self.grade(mode=mode, scope=scope)
                self.assertFalse(grade.panel_only_evaluation)
                self.assertIn('peer_score', grade.required_score_fields)

    def test_new_capture_uses_flag_and_preserves_existing_outcome_version(self):
        stage = DefenseStage(pk=1, label='Custom Research Screening',
                             concept_config={'enabled': True}, qualifying_score=75)
        schedule = DefenseSchedule(scope='capstone', defense_stage=stage)
        policy = capture_policy(schedule)
        self.assertEqual(policy['version'], 1)
        self.assertEqual(policy['evaluation_mode'], PANEL_ONLY_CONCEPT)
        self.assertEqual(policy['weights'], PANEL_ONLY_WEIGHTS)
        self.assertTrue(policy['per_concept'])


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PanelOnlyConceptWorkflowTests(APITestCase):
    _rubric = fixtures.AutomaticConceptOutcomeTests._rubric
    prepare = fixtures.AutomaticConceptOutcomeTests.prepare
    scores = fixtures.AutomaticConceptOutcomeTests.scores
    submit = fixtures.AutomaticConceptOutcomeTests.submit
    post = fixtures.AutomaticConceptOutcomeTests.post

    def setUp(self):
        fixtures.AutomaticConceptOutcomeTests.setUp(self)
        self.grade.adviser_score = self.grade.peer_score = None
        self.grade.adviser_score_is_override = self.grade.peer_score_is_override = False
        self.grade.student_grades.update(adviser_score=None, peer_score=None)
        self.grade.save()

    def preview(self):
        return group_completion_readiness(semester=self.semester, scope='capstone',
                                         stage_label=self.stage.label, user=self.admin)

    def progress(self):
        return schedule_progress(DefenseSchedule.objects.get(pk=self.capstone_schedule.pk),
                                 reconcile_status=False)

    def test_only_qualifier_publishes_and_clears_stage_without_adviser_or_peer_grades(self):
        result = self.post([6, 7.5, 7])
        self.assertEqual(result.status_code, 201, result.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.final_grade, Decimal('75'))
        self.assertIsNone(self.grade.adviser_score)
        self.assertIsNone(self.grade.peer_score)
        self.assertTrue(all(row.final_grade == Decimal('75') for row in self.grade.student_grades.all()))
        readiness = team_grading_readiness(self.grade, self.semester, 'capstone')
        self.assertTrue(readiness['ready'], readiness)
        self.assertFalse(readiness['adviser_required'])
        self.assertFalse(readiness['peer_required'])
        self.assertEqual(self.progress()['display_status'], 'awaiting_completion')
        preview = self.preview()
        self.assertTrue(preview['can_complete'], preview)
        update_group_settings(semester=self.semester, scope='capstone', stage_label=self.stage.label,
                              user=self.admin, is_officially_complete=True,
                              completion_token=preview['completion_token'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.status, 'published')
        self.assertEqual(self.progress()['display_status'], 'completed')
        self.assertTrue(stage_cleared(self.capstone_team, {'id': self.stage.pk, 'label': self.stage.label}, self.grade))
        from reports.assessment_reports import _individual_rows, _team_rows
        self.assertNotIn('Peer Evaluation', [row['component'] for row in _individual_rows(self.grade, self.student)])
        self.assertTrue(all(row['peer_rating'] == 'N/A' for row in _team_rows(self.grade)))

    def test_multiple_qualifiers_require_chair_selection_before_post_completion(self):
        self.submit([8, 9, 6])
        self.assertEqual(self.progress()['display_status'], 'awaiting_concept_selection')
        self.assertIsNone(self.grade.panel_score)
        self.assertFalse(self.preview()['can_complete'])
        rule = outcome_payload(self.grade)
        resolve_outcome(self.grade, actor=self.panelist, selected_key='c1', review_token=rule['review_token'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.final_grade, Decimal('80'))
        self.assertEqual(self.progress()['display_status'], 'awaiting_completion')

    def test_required_post_files_remain_a_gate_after_automatic_concept_approval(self):
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='FINAL',
            label='Configured final attachments', deliverable_type='post', required=True,
            file_policy={'mode': 'multiple', 'min_files': 1, 'max_files': 3})
        capture_participation(self.capstone_team, requirements=configured_requirements())
        self.submit([8, 6, 7])
        self.assertEqual(self.progress()['display_status'], 'pending_post_defense')
        preview = self.preview()
        self.assertFalse(preview['can_complete'])
        self.assertEqual(preview['incomplete_teams'][0]['missing_components'], ['post_defense'])
        submission = DeliverableSubmission.objects.create(team=self.capstone_team, stage_label=self.stage.label,
            deliverable_id='FINAL', label='Configured final attachments', deliverable_type='post',
            status='accepted', file_name='final.pdf', file='test-evidence/final.pdf', extracted_text='Final evidence')
        DeliverableSubmissionFile.objects.create(submission=submission, file='test-evidence/final.pdf',
            file_name='final.pdf', slot_key='attachment-1', status='accepted', extracted_text='Final evidence')
        self.assertEqual(self.progress()['display_status'], 'awaiting_completion')
        self.assertTrue(self.preview()['can_complete'])

    def test_signed_minutes_and_every_assigned_panel_assessment_are_still_required(self):
        from .test_workflow_completion import WorkflowCompletionTests
        WorkflowCompletionTests.require_minutes(self)
        other = self.panelist.__class__.objects.create_user(username='concept-extra-panel', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=other)
        self.submit([8, 6, 7])
        self.assertEqual(self.grade.verdict, '')
        self.assertIn('panel', self.preview()['incomplete_teams'][0]['missing_components'])
        SchedulePanelist.objects.filter(schedule=self.capstone_schedule, panelist=other).delete()
        resolve_outcome(self.grade)
        self.assertEqual(self.preview()['incomplete_teams'][0]['missing_components'], ['minutes'])
        WorkflowCompletionTests.make_minutes(self, finalized=True)
        self.assertTrue(self.preview()['can_complete'])

    def test_grading_tasks_and_direct_role_writes_are_unavailable(self):
        self.assertIn('not required', adviser_grading_unavailable_reason(self.grade))
        self.assertIn('not required', peer_grading_unavailable_reason(self.grade))
        self.assertNotIn(self.grade.pk, [g.pk for g in adviser_capstone_grades_for_user(self.adviser)])
        for field in ('adviser_score', 'peer_score'):
            serializer = TeamGradeUpdateSerializer(data={field: 80}, context={'grade': self.grade})
            self.assertFalse(serializer.is_valid())
            self.assertIn(field, serializer.errors)
        payload = TeamGradeSerializer(self.grade).data
        self.assertTrue(payload['panel_only_evaluation'])
        self.assertFalse(payload['adviser_required'])
        self.assertFalse(payload['peer_required'])
        self.assertEqual(payload['peer_submissions_required'], 0)
        self.client.force_authenticate(self.adviser)
        adviser = self.client.post(f'/api/grading/grades/adviser-grades/{self.grade.pk}/submit/',
                                  {'adviser_score': 80}, format='json')
        self.assertEqual(adviser.status_code, 400, adviser.data)
        self.assertIn('not required', str(adviser.data))
        self.client.force_authenticate(self.student)
        peer = self.client.post('/api/grading/grades/peer-evaluations/', {
            'teamId': self.capstone_team.pk, 'evaluateeId': self.second_student.pk,
            'stage': self.stage.label, 'breakdown': [{'criterion_id': 1, 'score': 8}],
        }, format='json')
        self.assertEqual(peer.status_code, 400, peer.data)
        self.assertIn('not required', str(peer.data))

    def test_live_stage_edits_do_not_rewrite_a_captured_evaluation_mode(self):
        self.stage.concept_config = {'enabled': False}
        self.stage.save(update_fields=['concept_config'])
        self.grade.refresh_from_db()
        self.assertTrue(self.grade.panel_only_evaluation)
        self.capstone_schedule.assessment_policy.pop('evaluation_mode')
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        self.stage.concept_config = {'enabled': True}
        self.stage.save(update_fields=['concept_config'])
        self.grade.refresh_from_db()
        self.assertFalse(self.grade.panel_only_evaluation)

    def test_editable_stage_setup_normalizes_weights_and_rejects_stale_mixed_payloads(self):
        from defense.stages.grading_config import get_or_create_stage_grading_config
        from defense.stages.serializers import StageGradingConfigWriteSerializer
        stage = DefenseStage.objects.create(label='New custom screening', setup_semester=self.semester,
            concept_config={'enabled': True, 'required_count': 3}, qualifying_score=75, is_active=False)
        config = get_or_create_stage_grading_config(stage, self.semester)
        self.assertEqual(config.as_weights_dict(), PANEL_ONLY_WEIGHTS)
        invalid = StageGradingConfigWriteSerializer(data={
            'panel_weight': 50, 'adviser_weight': 30, 'peer_weight': 20,
        }, context={'config': config})
        self.assertFalse(invalid.is_valid())
        self.assertIn('weights', invalid.errors)
        valid = StageGradingConfigWriteSerializer(data=PANEL_ONLY_WEIGHTS, context={'config': config})
        self.assertTrue(valid.is_valid(), valid.errors)
        valid.save()
        config.refresh_from_db()
        self.assertEqual(config.as_weights_dict(), PANEL_ONLY_WEIGHTS)

    def test_config_save_preserves_mixed_weights_captured_without_an_outcome_version(self):
        from defense.stages.models import StageGradingConfig
        from .services import peer_required_for_grade, weights_for_schedule
        legacy = {'panel_weight': 50, 'adviser_weight': 30, 'peer_weight': 20}
        self.capstone_schedule.assessment_policy = {'weights': legacy}
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        for field, value in legacy.items():
            setattr(self.grade, field, value)
        self.grade.save()
        config = StageGradingConfig.objects.get(defense_stage=self.stage, semester=self.semester)
        config.save()
        self.grade.refresh_from_db()
        self.semester.capstone_peer_evaluation_enabled = True
        self.assertEqual(weights_for_schedule(self.capstone_schedule), legacy)
        self.assertEqual(self.grade.peer_weight, 20)
        self.assertTrue(peer_required_for_grade(self.grade, self.semester, 'capstone', config))
