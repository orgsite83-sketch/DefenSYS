"""Correct shared choices through the chair while preserving proposal identities."""
from copy import deepcopy
from django.core.exceptions import ValidationError
from django.test import override_settings
from rest_framework.test import APITestCase, APITransactionTestCase

from defense.scheduler.panelist_evaluation import evaluation_context, save_evaluation_draft, draft_payload
from grading.grades.services import submit_panelist_grade, GradeContextService
from . import services, test_redefense_direction as fixtures
from .selection_corrections import correct, payload


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedSelectionCorrectionTests(APITestCase):
    prepare_hearing = fixtures.SharedRedefenseDirectionTests.prepare_hearing

    def setUp(self):
        fixtures.SharedRedefenseDirectionTests.setUp(self)
        self.chair.is_panelist = True
        self.chair.save(update_fields=['is_panelist'])

    def choose(self, key='c1'):
        services.decide(self.project, self.chair, [{'key': k,
            'decision': 'approved' if k == key else 'not_selected'} for k in services.KEYS], 'approved', '')

    def correction(self, key='c2', token=None, actor=None, reason='The panel agreed on Concept 2; Concept 1 was clicked.'):
        round = services.latest(self.project)
        return correct(self.project, actor or self.chair, concept_key=key, reason=reason,
            review_token=token or payload(round, self.chair)['review_token'])

    def score(self, schedule=None, grade=None, key='c1', actor=None, score=8):
        return submit_panelist_grade(schedule or self.schedule, grade or self.grade,
            [{'criterion_id': self.criterion.pk, 'score': score}], panelist=actor or self.chair, concept_key=key)

    def second_team(self):
        from django.contrib.auth import get_user_model
        from django.core.files.uploadedfile import SimpleUploadedFile
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from student_teams.models import StudentTeam, TeamMembership
        from repository.deliverables import concepts
        from repository.deliverables.services import upsert_submission, review_submission, endorse_team
        from .models import SectionProjectTeam
        student = get_user_model().objects.create_user(username='correction-second-leader', role='student')
        team = StudentTeam.objects.create(name='Second shared team', leader=student, adviser=self.adviser,
            level=self.team.level, year_level=self.team.year_level, section=self.team.section,
            semester=self.semester, status=self.team.status)
        TeamMembership.objects.create(team=team, student=student, is_leader=True)
        SectionProjectTeam.objects.create(project=self.project, team=team, project_version=team.project_version)
        concepts.save_titles(team, self.stage, [{'key': k, 'title': f'Second module {k}'} for k in services.KEYS], actor=self.adviser)
        for key in services.KEYS:
            sub = upsert_submission(team, self.stage.label, 'CONCEPTS', f'{key}.pdf', '10 B', student,
                file=SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 module'), slot_key=f'{key}:paper')
            review_submission(team, self.stage.label, 'CONCEPTS', 'accepted', '', self.adviser,
                file_id=sub.files.get(is_current=True, slot_key=f'{key}:paper').pk)
        endorse_team(team, self.stage.label, self.adviser)
        schedule = DefenseSchedule.objects.create(team=team, semester=self.semester, defense_stage=self.stage,
            rubric=self.schedule.rubric, scheduled_date=self.schedule.scheduled_date, start_time='10:00', room=self.schedule.room)
        SchedulePanelist.objects.create(schedule=schedule, panelist=self.chair, is_chair=True)
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        services.schedule_hearing(self.project, self.admin, [self.schedule.pk, schedule.pk])
        return team, schedule, grade

    def test_updates_every_participating_team_and_keeps_prior_decision_and_evidence(self):
        from repository.deliverables.models import ConceptRound
        from authentication_access_control.models import SystemAuditLog
        second, schedule, grade = self.second_team()
        self.choose()
        round = services.latest(self.project)
        documents = deepcopy(round.decision_snapshot['shared_documents'])
        original = deepcopy(round.decision_snapshot['systems'])
        result = self.correction()
        self.assertEqual(result.selected_key, 'c2')
        self.assertEqual(result.decision_snapshot['shared_documents'], documents)
        change = result.decision_snapshot['selection_corrections'][0]
        self.assertEqual((change['from_key'], change['to_key']), ('c1', 'c2'))
        self.assertEqual(change['previous_decision']['systems'], original)
        self.team.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(self.team.project_title, 'Module c2')
        self.assertEqual(second.project_title, 'Second module c2')
        self.assertEqual(ConceptRound.objects.filter(section_round=round).count(), 2)
        self.assertTrue(SystemAuditLog.objects.filter(action='section_concepts.selection_corrected').exists())
        self.assertEqual(grade.panelist_submissions.count(), 0)

    def test_only_common_assigned_chair_can_correct_including_admin(self):
        from defense.scheduler.models import SchedulePanelist
        self.choose()
        token = payload(services.latest(self.project), self.chair)['review_token']
        for actor in (self.admin, self.adviser, self.student):
            self.assertFalse(payload(services.latest(self.project), actor)['can_correct'])
            with self.assertRaises(PermissionError):
                self.correction(actor=actor, token=token)
        SchedulePanelist.objects.filter(schedule=self.schedule).update(panelist=self.admin)
        result = self.correction(actor=self.admin, token=payload(services.latest(self.project), self.admin)['review_token'])
        self.assertEqual(result.decided_by_id, self.admin.pk)

    def test_preserves_drafts_and_allows_a_panelist_to_assess_the_corrected_module(self):
        from defense.scheduler.models import SchedulePanelist
        second = self.chair.__class__.objects.create_user(username='correction-other-panel', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.schedule, panelist=second)
        self.choose()
        self.score()
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        saved = save_evaluation_draft(self.schedule, {'evaluation_context': evaluation_context(self.schedule, self.grade),
            'submissions': [{'concept_key': 'c2', 'criteria_scores': [{'criterion_id': self.criterion.pk, 'score': 0}]}]}, panelist=second)
        immutable = evaluation_context(self.schedule, self.grade, include_scope=False)
        old_final_context = evaluation_context(self.schedule, self.grade)
        self.correction()
        self.schedule.refresh_from_db()
        self.grade.refresh_from_db()
        self.assertNotEqual(evaluation_context(self.schedule, self.grade), old_final_context)
        self.assertEqual(evaluation_context(self.schedule, self.grade, include_scope=False), immutable)
        self.assertEqual(draft_payload(self.schedule.evaluation_drafts.get(), immutable), saved)
        self.assertEqual(list(self.grade.panelist_submissions.values_list('concept_key', flat=True)), ['c1'])
        self.client.force_authenticate(self.chair)
        response = self.client.get('/api/defense/schedules/panelist-assignments/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['teams'][0]['is_posted'])
        self.assertTrue(response.data['teams'][0]['grading_available'])
        self.assertEqual([c['key'] for c in response.data['teams'][0]['assessment_concepts']], ['c2'])
        response = self.client.post('/api/defense/schedules/submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': self.schedule.pk,
            'evaluation_context': evaluation_context(self.schedule, self.grade),
            'submissions': [{'concept_key': 'c2', 'criteria_scores': [{'criterion_id': self.criterion.pk, 'score': 8}]}]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertCountEqual(self.grade.panelist_submissions.values_list('concept_key', flat=True), ['c1', 'c2'])

    def test_existing_valid_correct_module_assessments_are_reused(self):
        self.score(key='c2')
        self.choose()
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.correction()
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panel_score, 80)
        self.assertEqual(self.grade.panelist_submissions.count(), 1)

    def test_a_recorded_outcome_in_any_team_blocks_the_correction(self):
        second, schedule, grade = self.second_team()
        self.choose()
        self.score(schedule, grade)
        self.assertFalse(payload(services.latest(self.project), self.chair)['can_correct'])
        with self.assertRaises(ValidationError):
            self.correction()
        self.assertEqual(services.latest(self.project).selected_key, 'c1')
        self.assertEqual(services.latest(self.project).decision_snapshot.get('selection_corrections', []), [])

    def test_stale_review_empty_reason_and_wrong_target_cannot_change_selection(self):
        self.choose()
        token = payload(services.latest(self.project), self.chair)['review_token']
        save_evaluation_draft(self.schedule, {'evaluation_context': evaluation_context(self.schedule, self.grade),
            'submissions': [{'concept_key': 'c1', 'criteria_scores': []}]}, panelist=self.chair)
        for values in ({'token': token}, {'reason': ''}, {'key': 'c1'}, {'key': 'unknown'}):
            with self.assertRaises(ValidationError):
                self.correction(**values)
        self.assertEqual(services.latest(self.project).selected_key, 'c1')

    def test_api_and_every_team_outcome_expose_the_same_correction(self):
        from grading.grades.defense_workflow import workflow_payload
        self.choose()
        review = workflow_payload(self.grade, self.chair)['shared_selection_correction']
        self.assertEqual(review['id'], self.project.pk)
        self.assertTrue(review['selection_correction']['can_correct'])
        self.client.force_authenticate(self.chair)
        response = self.client.post(f'/api/repository/section-concepts/{self.project.pk}/', {
            'action': 'correct_selection', 'round_id': review['round_id'], 'concept_key': 'c2',
            'review_token': review['selection_correction']['review_token'], 'remarks': 'Wrong proposal clicked.'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['selected_key'], 'c2')
        self.assertEqual(len(response.data['selection_correction']['history']), 1)

    def test_guest_can_submit_the_corrected_module_without_replacing_old_scores(self):
        from authentication_access_control.guest_authentication import GuestPanelistPrincipal
        from user_management.models import GuestPanelistCode
        invitation = GuestPanelistCode.objects.create(guest_name='Correction external panel', defense_schedule=self.schedule)
        invitation.schedules.add(self.schedule)
        guest = GuestPanelistPrincipal({'guest_code_id': str(invitation.pk), 'guest_code': invitation.code,
            'defense_schedule_id': self.schedule.pk, 'team_id': self.team.pk,
            'guest_name': invitation.guest_name}, invitation=invitation)
        self.choose()
        submit_panelist_grade(self.schedule, self.grade,
            [{'criterion_id': self.criterion.pk, 'score': 8}], guest=guest, concept_key='c1')
        self.correction()
        self.client.force_authenticate(guest)
        response = self.client.get('/api/defense/schedules/guest-assignments/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['teams'][0]['is_posted'])
        self.grade.refresh_from_db()
        response = self.client.post('/api/defense/schedules/guest-submit-grades/', {
            'team_id': self.team.pk, 'schedule_id': self.schedule.pk,
            'evaluation_context': evaluation_context(self.schedule, self.grade),
            'submissions': [{'concept_key': 'c2', 'criteria_scores': [{'criterion_id': self.criterion.pk, 'score': 9}]}]}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertCountEqual(self.grade.panelist_submissions.values_list('concept_key', flat=True), ['c1', 'c2'])

    def test_partial_submitted_targets_are_immutable_and_missing_targets_can_finish(self):
        from grading.grades.outcome_rules import capture_policy
        from grading.rubrics.models import RubricCriterion
        rubric = self.schedule.rubric
        rubric.target_type = 'both'
        rubric.save(update_fields=['target_type'])
        individual = RubricCriterion.objects.create(rubric=rubric, name='Individual defense',
            scale=rubric.SCALE_10, max_score=10, target_type='individual', display_order=1)
        self.schedule.assessment_policy = capture_policy(self.schedule)
        self.schedule.save(update_fields=['assessment_policy'])
        self.score(key='c2', score=9)
        self.choose()
        self.correction()
        self.client.force_authenticate(self.chair)
        self.grade.refresh_from_db()
        data = {'team_id': self.team.pk, 'schedule_id': self.schedule.pk,
            'evaluation_context': evaluation_context(self.schedule, self.grade), 'submissions': [
                {'concept_key': 'c2', 'student_id': self.student.pk,
                    'criteria_scores': [{'criterion_id': individual.pk, 'score': 8}]},
                {'concept_key': 'c2', 'student_id': None,
                    'criteria_scores': [{'criterion_id': self.criterion.pk, 'score': 1}]}]}
        response = self.client.post('/api/defense/schedules/submit-grades/', data, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self.grade.panelist_submissions.count(), 1)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        data['submissions'][1]['criteria_scores'][0]['score'] = 9
        response = self.client.post('/api/defense/schedules/submit-grades/', data, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panelist_submissions.count(), 2)

    def test_failure_rolls_back_the_choice_every_team_title_and_history(self):
        from unittest.mock import patch
        second, _, second_grade = self.second_team()
        self.choose()
        titles = (self.team.__class__.objects.get(pk=self.team.pk).project_title,
            second.__class__.objects.get(pk=second.pk).project_title)
        with patch('grading.grades.automatic_outcomes.resolve_outcome', side_effect=RuntimeError('test failure')):
            with self.assertRaisesRegex(RuntimeError, 'test failure'):
                self.correction()
        round = services.latest(self.project)
        self.assertEqual(round.selected_key, 'c1')
        self.assertEqual(round.decision_snapshot.get('selection_corrections', []), [])
        self.team.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual((self.team.project_title, second.project_title), titles)
        second_grade.refresh_from_db()
        self.assertEqual(second_grade.project_title_snapshot, 'Second module c1')


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedSelectionCorrectionConcurrencyTests(APITransactionTestCase):
    # Inhibit post-migrate content-type recreation before restoring the snapshot.
    serialized_rollback = True
    setUp = SharedSelectionCorrectionTests.setUp
    prepare_hearing = SharedSelectionCorrectionTests.prepare_hearing
    choose = SharedSelectionCorrectionTests.choose

    def _fixture_teardown(self):
        super()._fixture_teardown()
        from django.db import connections
        for alias in self._databases_names(include_mirrors=False):
            connection = connections[alias]
            if hasattr(connection, '_test_serialized_contents'):
                connection.creation.deserialize_db_from_string(connection._test_serialized_contents)

    def test_simultaneous_corrections_record_one_choice_and_reject_the_stale_review(self):
        from concurrent.futures import ThreadPoolExecutor
        from threading import Barrier
        from unittest.mock import patch
        from django.db import close_old_connections
        self.choose()
        token = payload(services.latest(self.project), self.chair)['review_token']
        barrier = Barrier(2)

        def change(key):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                try:
                    correct(self.project, self.chair, concept_key=key,
                        reason='Correct the mistaken selection.', review_token=token)
                    return 'recorded'
                except ValidationError:
                    return 'stale'
            finally:
                close_old_connections()

        with patch('realtime.broadcast.notify_capstone_evaluation_flags'), ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(change, ['c2', 'c3']))
        self.assertCountEqual(results, ['recorded', 'stale'])
        round = services.latest(self.project)
        self.assertIn(round.selected_key, ['c2', 'c3'])
        self.assertEqual(len(round.decision_snapshot['selection_corrections']), 1)
        self.team.refresh_from_db()
        self.assertEqual(self.team.project_title, f'Module {round.selected_key}')
