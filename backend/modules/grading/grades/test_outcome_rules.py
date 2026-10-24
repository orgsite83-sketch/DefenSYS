from decimal import Decimal

from django.core.exceptions import ValidationError
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.scheduler.panelist_evaluation import validate_evaluation_submissions
from defense.stages.models import StageGradingConfig
from grading.rubrics.models import RubricCriterion
from repository.deliverables.models import ConceptRound
from . import tests as fixtures
from . import test_concept_workflow as concept_fixtures
from .defense_workflow import record_verdict
from .models import TeamGrade
from .outcome_rules import outcome_payload
from .services import GradeContextService, submit_panelist_grade, weights_for_schedule


class ConfiguredOutcomeTests(APITestCase):
    _rubric = fixtures.GradeCenterApiTests._rubric

    def setUp(self):
        fixtures.GradeCenterApiTests.setUp(self)
        self.stage.qualifying_score = Decimal('75')
        self.stage.score_carryover = 'reassess'
        self.stage.save()
        self.new_hearing()

    def new_hearing(self):
        self.capstone_schedule.delete()
        self.capstone_schedule = DefenseSchedule.objects.create(
            team=self.capstone_team, semester=self.semester, defense_stage=self.stage,
            rubric=self.panel_rubric, scheduled_date='2026-05-15', start_time='08:00', room='Phase 3')
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=self.panelist, is_chair=True)
        self.grade, _, _ = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)

    def submit(self, score, student=None, criteria=None):
        return submit_panelist_grade(self.capstone_schedule, self.grade,
            criteria or [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': score}],
            panelist=self.panelist, student=student)

    def test_cutoff_and_role_weights_are_independent_and_exact_match_qualifies(self):
        self.submit(7.5)
        self.grade.refresh_from_db()
        self.assertEqual(outcome_payload(self.grade)['outcome'], 'approved')
        self.grade.adviser_score = 0
        self.grade.peer_score = 0
        self.grade.save()
        self.assertEqual(outcome_payload(self.grade)['outcome'], 'approved')
        result = record_verdict(self.grade, actor=self.admin, verdict='approved')
        self.assertEqual(result.verdict, 'approved')
        self.assertNotEqual(result.status, TeamGrade.STATUS_PUBLISHED)

    def test_below_cutoff_cannot_be_approved_even_with_perfect_other_roles(self):
        self.submit(7.49)
        self.grade.refresh_from_db()
        self.grade.adviser_score = self.grade.peer_score = Decimal('100')
        self.grade.save()
        self.assertEqual(outcome_payload(self.grade)['outcome'], 'for_redefense')
        with self.assertRaises(ValidationError):
            record_verdict(self.grade, actor=self.admin, verdict='approved')
        result = record_verdict(self.grade, actor=self.admin, verdict='for_redefense', remarks='Revise and present again.')
        self.assertEqual(result.verdict, 'for_redefense')

    def test_incomplete_panel_stays_pending(self):
        second = self.panelist.__class__.objects.create_user(username='phase3-extra', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=second)
        self.submit(10)
        self.assertEqual(outcome_payload(self.grade)['outcome'], 'pending')
        with self.assertRaises(ValidationError):
            record_verdict(self.grade, actor=self.admin, verdict='approved')

    def test_score_is_compared_before_display_rounding(self):
        criterion = self.panel_rubric.criteria.first()
        criterion.max_score = 100
        criterion.save()
        self.new_hearing()
        self.submit(Decimal('74.99'))
        second = self.panelist.__class__.objects.create_user(username='rounding-panel', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=second)
        submit_panelist_grade(self.capstone_schedule, self.grade,
            [{'criterion_id': criterion.pk, 'score': 75}], panelist=second)
        rule = outcome_payload(self.grade)
        self.assertEqual(rule['assessments'][0]['score'], 74.995)
        self.assertEqual(rule['outcome'], 'for_redefense')

    def test_locked_stage_policy_can_change_for_future_hearings_only(self):
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'/api/defense/stages/{self.stage.pk}/',
            {'qualifying_score': 90, 'score_carryover': 'retain'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.stage.refresh_from_db()
        self.assertEqual(self.stage.qualifying_score, 90)
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(Decimal(self.capstone_schedule.assessment_policy['qualifying_score']), 75)
        for invalid in ('-1', '100.01', 'NaN'):
            response = self.client.patch(f'/api/defense/stages/{self.stage.pk}/',
                {'qualifying_score': invalid}, format='json')
            self.assertEqual(response.status_code, 400, response.data)

    def test_policy_only_edit_does_not_regenerate_legacy_concept_requirements(self):
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        original = list(self.stage.deliverables.values_list('pk', flat=True))
        self.client.force_authenticate(self.admin)
        result = self.client.patch(f'/api/defense/stages/{self.stage.pk}/',
            {'qualifying_score': 80}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(list(self.stage.deliverables.values_list('pk', flat=True)), original)

    def test_configured_redefense_requires_new_endorsement(self):
        from defense.stages.models import StageDeliverable
        from repository.deliverables.models import DeliverableSubmission
        from repository.deliverables.services import endorse_team
        from student_teams.services import is_stage_ready, was_stage_endorsed
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='P3PRE', label='Manuscript', required=True)
        from student_teams.capstone_lifecycle import capture_participation, configured_requirements
        capture_participation(self.capstone_team, requirements=configured_requirements())
        DeliverableSubmission.objects.create(team=self.capstone_team, stage_label=self.stage.label,
            deliverable_id='P3PRE', label='Manuscript', deliverable_type='pre', file_name='manuscript.pdf', status='accepted')
        self.submit(6)
        grade = record_verdict(self.grade, actor=self.admin, verdict='for_redefense', remarks='Revise and present again.')
        self.assertFalse(is_stage_ready(grade.team, self.stage))
        self.assertFalse(was_stage_endorsed(grade.team, self.stage))
        endorse_team(grade.team, self.stage.label, self.adviser)
        self.assertTrue(is_stage_ready(grade.team, self.stage))

    def test_correction_cannot_leave_a_contradictory_approval(self):
        from .corrections import request_correction
        from rest_framework.exceptions import ValidationError as ApiValidationError
        self.submit(8)
        grade = record_verdict(self.grade, actor=self.admin, verdict='approved')
        score = grade.panelist_submissions.get().criterion_scores.get()
        with self.assertRaises(ApiValidationError):
            request_correction(grade.pk, self.admin, {'reason': 'Correct the original score.',
                'expected_updated_at': grade.updated_at.isoformat(),
                'changes': {'criterion': {'id': score.pk, 'score': 4}}})
        score.refresh_from_db()
        self.assertEqual(score.score, 8)

    def test_snapshot_is_independent_of_stage_name_and_later_changes(self):
        weights = weights_for_schedule(self.capstone_schedule)
        self.stage.label = 'Custom Research Review'
        self.stage.qualifying_score = 99
        self.stage.save()
        self.submit(8)
        self.assertEqual(outcome_payload(self.grade)['qualifying_score'], 75)
        self.assertEqual(outcome_payload(self.grade)['outcome'], 'approved')
        StageGradingConfig.objects.filter(defense_stage=self.stage).update(panel_weight=80, adviser_weight=10, peer_weight=10)
        self.assertEqual(weights_for_schedule(self.capstone_schedule), weights)

    def test_both_target_preserves_students_and_aggregates_team_and_individual_weights(self):
        self.panel_rubric.target_type = 'both'
        self.panel_rubric.save()
        criterion = self.panel_rubric.criteria.first()
        criterion.target_type, criterion.weight = 'team', 60
        criterion.save()
        individual = RubricCriterion.objects.create(rubric=self.panel_rubric, name='Oral',
            scale=criterion.scale, max_score=10, weight=40, target_type='individual', display_order=1)
        self.new_hearing()
        self.submit(9)
        self.submit(0, student=self.student, criteria=[{'criterion_id': individual.pk, 'score': 5}])
        self.submit(0, student=self.second_student, criteria=[{'criterion_id': individual.pk, 'score': 10}])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, Decimal('84'))
        self.assertEqual(self.grade.student_grades.get(student=self.student).panel_score, Decimal('74'))
        self.assertEqual(self.grade.student_grades.get(student=self.second_student).panel_score, Decimal('94'))
        self.assertEqual(outcome_payload(self.grade)['outcome'], 'approved')

    def test_both_target_requires_members_before_accepting_an_assessment(self):
        self.panel_rubric.target_type = 'both'
        self.panel_rubric.save()
        self.capstone_team.memberships.all().delete()
        with self.assertRaisesMessage(ValidationError, 'no members'):
            validate_evaluation_submissions(self.capstone_schedule, [{'student_id': None,
                'criteria_scores': [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 8}]}])

    def test_new_repeat_policy_applies_without_concept_selection(self):
        for carryover in ('retain', 'reassess'):
            with self.subTest(carryover=carryover):
                self.grade.adviser_score, self.grade.peer_score = Decimal('84'), Decimal('88')
                self.grade.panel_score = Decimal('40')
                self.grade.verdict = 'for_redefense'
                self.grade.save()
                self.stage.score_carryover = carryover
                self.stage.save()
                next_schedule = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
                    defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date='2026-05-16',
                    start_time='11:00', room=f'Repeat {carryover}')
                grade, _, _ = GradeContextService.get_or_create_for_schedule(next_schedule)
                self.assertEqual(grade.adviser_score, Decimal('84') if carryover == 'retain' else None)
                self.assertEqual(grade.peer_score, Decimal('88') if carryover == 'retain' else None)
                self.assertIsNone(grade.panel_score)
                self.assertEqual(grade.attempt_history.order_by('-attempt_number').first().verdict, 'for_redefense')
                self.grade = grade


class PerConceptOutcomeTests(APITestCase):
    _rubric = fixtures.GradeCenterApiTests._rubric
    prepare = concept_fixtures.ConceptHearingWorkflowTests.prepare

    def setUp(self):
        concept_fixtures.ConceptHearingWorkflowTests.setUp(self)
        # Reuse reviewed fixture documents, then schedule a genuinely new hearing.
        ConceptRound.objects.filter(schedule=self.capstone_schedule).update(schedule=None)
        self.capstone_schedule.delete()
        self.stage.qualifying_score = 75
        self.stage.save()
        self.capstone_schedule = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, scheduled_date='2026-05-15', start_time='08:00', room='Concepts')
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=self.panelist, is_chair=True)
        self.grade, _, _ = GradeContextService.get_or_create_for_schedule(self.capstone_schedule)

    def scores(self, values):
        return [{'concept_key': f'c{i}', 'student_id': None,
                 'criteria_scores': [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': score}]}
                for i, score in enumerate(values, 1)]

    def post(self, values):
        self.client.force_authenticate(self.panelist)
        return self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.capstone_team.pk, 'schedule_id': self.capstone_schedule.pk,
            'submissions': self.scores(values)}, format='json')

    def submit(self, values):
        for row in validate_evaluation_submissions(self.capstone_schedule, self.scores(values)):
            submit_panelist_grade(self.capstone_schedule, self.grade, row['criteria_scores'],
                panelist=self.panelist, concept_key=row['concept_key'])
        self.grade.refresh_from_db()

    def decisions(self, selected=None):
        return [{'key': f'c{i}', 'decision': 'approved' if i == selected else 'not_selected', 'remarks': 'Panel feedback.',
                 'next_action': 'revise' if selected is None else 'omit'}
                for i in range(1, 4)]

    def test_each_concept_required_and_unselected_scores_do_not_enter_grade(self):
        with self.assertRaises(ValidationError):
            validate_evaluation_submissions(self.capstone_schedule, self.scores([8]))
        self.submit([8, 9, 6])
        self.assertIsNone(self.grade.panel_score)
        self.assertEqual(outcome_payload(self.grade)['outcome'], 'approved')
        with self.assertRaises(ValidationError):
            record_verdict(self.grade, actor=self.admin, verdict='approved', concept_decisions=self.decisions(3))
        result = record_verdict(self.grade, actor=self.admin, verdict='approved', concept_decisions=self.decisions(1))
        self.assertEqual(result.panel_score, Decimal('80'))
        self.assertEqual(result.panelist_submissions.count(), 3)
        hearing = ConceptRound.objects.get(schedule=self.capstone_schedule)
        self.assertEqual([c['panel_score'] for c in hearing.concepts], [80, 90, 60])

    def test_no_qualifying_concept_starts_redefense_and_preserves_history(self):
        self.submit([5, 6, 7])
        result = record_verdict(self.grade, actor=self.admin, verdict='for_redefense',
            remarks='Revise the concepts and present again.', concept_decisions=self.decisions())
        self.assertEqual(result.verdict, 'for_redefense')
        self.assertIsNone(result.panel_score)
        self.assertEqual(ConceptRound.objects.get(number=1, team=self.capstone_team).concepts[2]['panel_score'], 70)
        self.assertNotIn('panel_score', ConceptRound.objects.get(number=2, team=self.capstone_team).concepts[2])

    def test_api_submits_every_concept_atomically_and_returns_separate_scores(self):
        result = self.post([8, 9, 6])
        self.assertEqual(result.status_code, 201, result.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panelist_submissions.count(), 3)
        self.assertIsNone(self.grade.panel_score)
        assignments = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(assignments.status_code, 200, assignments.data)
        team = next(t for t in assignments.data['teams'] if t['schedule_id'] == self.capstone_schedule.pk)
        self.assertTrue(team['can_issue_verdict'])
        self.assertEqual({s['concept_key'] for s in team['submissions']}, {'c1', 'c2', 'c3'})
        rule = team['grade_record']['workflow']['outcome_rule']
        self.assertEqual([s['score'] for s in rule['assessments']], [80, 90, 60])
        results = self.client.get('/api/defense/schedules/panelist-results/')
        self.assertEqual(results.status_code, 200, results.data)
        self.assertIsNone(results.data['results'][0]['percentage'])
        self.assertEqual(len(results.data['results'][0]['concept_assessments']), 3)

    def test_invalid_concept_set_cannot_partially_write_scores(self):
        result = self.post([8, 9])
        self.assertEqual(result.status_code, 400, result.data)
        self.assertFalse(self.grade.panelist_submissions.exists())

    def test_private_draft_keeps_concept_identity_and_deliberate_zero(self):
        from defense.scheduler.panelist_evaluation import evaluation_context
        self.client.force_authenticate(self.panelist)
        result = self.client.post('/api/defense/schedules/grade-draft/', {
            'schedule_id': self.capstone_schedule.pk,
            'evaluation_context': evaluation_context(self.capstone_schedule, self.grade),
            'submissions': self.scores([0])}, format='json')
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(result.data['draft']['submissions'][0]['concept_key'], 'c1')
        self.assertEqual(result.data['draft']['submissions'][0]['criteria_scores'][0]['score'], 0)
        self.assertFalse(self.grade.panelist_submissions.exists())

    def test_guest_must_assess_every_concept_before_panel_is_complete(self):
        from authentication_access_control.guest_authentication import GuestPanelistPrincipal
        from user_management.models import GuestPanelistCode
        invitation = GuestPanelistCode.objects.create(guest_name='Phase 3 external panel', defense_schedule=self.capstone_schedule)
        invitation.schedules.add(self.capstone_schedule)
        guest = GuestPanelistPrincipal({'guest_code_id': str(invitation.pk), 'guest_code': invitation.code,
            'defense_schedule_id': self.capstone_schedule.pk, 'team_id': self.capstone_team.pk,
            'guest_name': invitation.guest_name}, invitation=invitation)
        self.submit([8, 9, 6])
        self.assertFalse(outcome_payload(self.grade)['panel_complete'])
        self.client.force_authenticate(guest)
        result = self.client.post('/api/defense/schedules/guest-submit-grades/', {
            'team_id': self.capstone_team.pk, 'schedule_id': self.capstone_schedule.pk,
            'submissions': self.scores([6, 9, 8])}, format='json')
        self.assertEqual(result.status_code, 201, result.data)
        rule = outcome_payload(self.grade)
        self.assertTrue(rule['panel_complete'])
        self.assertEqual([r['score'] for r in rule['assessments']], [70, 90, 70])

    def test_peer_evaluation_does_not_wait_for_the_official_concept_selection(self):
        from .availability import peer_grading_unavailable_reason
        self.semester.capstone_peer_evaluation_enabled = True
        self.semester.save()
        self.submit([8, 9, 6])
        self.grade.refresh_from_db()
        self.assertIsNone(self.grade.panel_score)
        self.assertEqual(peer_grading_unavailable_reason(self.grade), '')
