"""Chair routes reuse the real shared hearing, repeat, title and file services."""
from copy import deepcopy

from django.core.exceptions import ValidationError
from django.test import override_settings
from rest_framework.test import APITestCase, APITransactionTestCase

from defense.scheduler.panelist_evaluation import (
    evaluation_context, save_evaluation_draft, draft_payload, validate_evaluation_submissions,
)
from grading.grades.corrections import evaluator_completion
from grading.grades.outcome_rules import concept_keys, outcome_payload
from grading.grades.services import submit_panelist_grade
from repository.deliverables import concepts, test_submission_timing
from repository.deliverables.models import ConceptRound
from student_teams.concept_policy import resolve_policy
from . import services, shared_deliverables
from .models import SharedModuleRedefenseDecision as Decision
from .redefense_direction import confirm, independent, payload
from . import test_hearing_flow as hearing_fixtures


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedRedefenseDirectionTests(APITestCase):
    prepare_hearing = hearing_fixtures.CapstoneSharedHearingFlowTests.prepare_hearing

    def setUp(self):
        test_submission_timing.faculty_review_setup(self)
        self.stage.qualifying_score = 75
        self.stage.save()
        self.project, self.schedule, self.grade, self.criterion = self.prepare_hearing()
        self.source = ConceptRound.objects.get(schedule=self.schedule)

    def choose(self):
        services.start_presentation(self.project, self.chair)
        services.decide(self.project, self.chair, [{'key': key,
            'decision': 'approved' if key == 'c2' else 'not_selected'}
            for key in services.KEYS], 'approved', '')

    def score(self, key='c2', score=6):
        submit_panelist_grade(self.schedule, self.grade,
            [{'criterion_id': self.criterion.pk, 'score': score}],
            panelist=self.chair, concept_key=key)
        self.grade.refresh_from_db()

    def prepare_redefense(self):
        self.choose()
        self.score()
        self.assertEqual(self.grade.verdict, 'for_redefense')
        return ConceptRound.objects.get(team=self.team, number=2)

    def decide(self, direction='independent', **kwargs):
        self.grade.refresh_from_db()
        current = payload(self.grade, self.chair)
        return confirm(self.grade, actor=self.chair, direction=direction,
            source_round_id=current['source_round_id'],
            review_token=kwargs.pop('review_token', current['review_token']), **kwargs)

    def test_selection_narrows_required_work_and_reuses_submitted_selected_score(self):
        self.assertEqual(concept_keys(self.schedule), ['c1', 'c2', 'c3'])
        self.score('c2', 8)
        self.assertFalse(outcome_payload(self.grade)['panel_complete'])
        self.choose()
        self.grade.refresh_from_db()
        self.assertEqual(concept_keys(self.schedule), ['c2'])
        self.assertTrue(outcome_payload(self.grade)['panel_complete'])
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panel_score, 80)
        self.assertEqual(self.grade.panelist_submissions.count(), 1)

    def test_alternative_submissions_remain_evidence_without_blocking_completion(self):
        for key in services.KEYS:
            self.score(key, 6 if key == 'c2' else 9)
        self.choose()
        self.grade.refresh_from_db()
        self.assertEqual(evaluator_completion(self.grade)['submitted'], 1)
        self.assertEqual(self.grade.panelist_submissions.count(), 3)
        self.assertEqual(self.grade.verdict, 'for_redefense')
        self.assertFalse(any(r['qualifies'] for r in outcome_payload(self.grade)['assessments']))

    def test_legacy_captured_policy_keeps_its_required_set(self):
        self.schedule.assessment_policy.pop('shared_module_scope_version')
        self.schedule.save(update_fields=['assessment_policy'])
        self.choose()
        self.score()
        self.assertEqual(concept_keys(self.schedule), ['c1', 'c2', 'c3'])
        self.assertFalse(outcome_payload(self.grade)['panel_complete'])

    def test_selection_preserves_draft_alternatives_but_invalidates_old_final_context(self):
        submissions = [{'concept_key': key, 'criteria_scores': [
            {'criterion_id': self.criterion.pk, 'score': 7}]} for key in services.KEYS]
        old_context = evaluation_context(self.schedule, self.grade)
        save_evaluation_draft(self.schedule, {'evaluation_context': old_context,
            'submissions': submissions}, panelist=self.chair)
        self.choose()
        self.assertNotEqual(old_context, evaluation_context(self.schedule, self.grade))
        draft = self.schedule.evaluation_drafts.get()
        saved = draft_payload(draft, evaluation_context(self.schedule, self.grade, include_scope=False))
        self.assertEqual([row['concept_key'] for row in saved['submissions']], list(services.KEYS))
        self.assertTrue(all(row['criteria_scores'][0]['score'] == 7 for row in saved['submissions']))
        self.assertEqual(self.grade.panelist_submissions.count(), 0)
        with self.assertRaises(ValidationError):
            save_evaluation_draft(self.schedule, {'evaluation_context': old_context,
                'submissions': submissions}, panelist=self.chair)
        with self.assertRaises(ValidationError):
            validate_evaluation_submissions(self.schedule, submissions)
        validate_evaluation_submissions(self.schedule, [submissions[1]])

    def test_default_repeat_exists_without_remarks_and_shared_confirmation_keeps_it(self):
        following = self.prepare_redefense()
        self.assertEqual([c['key'] for c in following.concepts], ['c2'])
        before = deepcopy(following.concepts)
        self.assertTrue(payload(self.grade, self.chair)['can_decide'])
        self.decide('shared_module')
        following.refresh_from_db()
        self.assertEqual(following.concepts, before)
        self.assertEqual(following.section_round_id, self.source.section_round_id)
        self.assertFalse(independent(self.team))

    def test_independent_route_is_atomic_and_preserves_assessment_and_project_identity(self):
        following = self.prepare_redefense()
        self.source.refresh_from_db()
        before = deepcopy(self.source.concepts)
        documents = deepcopy(self.source.documents_snapshot)
        version, semester = self.team.project_version, self.team.semester_id
        self.decide()
        following.refresh_from_db()
        self.source.refresh_from_db()
        self.team.refresh_from_db()
        self.assertEqual(self.source.concepts, before)
        self.assertEqual(self.source.documents_snapshot, documents)
        self.assertIsNone(following.section_round_id)
        self.assertEqual([c['key'] for c in following.concepts], ['c1', 'c2', 'c3'])
        self.assertTrue(all(not c['title'] and not c['faculty_confirmed'] for c in following.concepts))
        self.assertTrue(all(c['title_review']['state'] == 'draft' for c in following.concepts))
        self.assertTrue(following.review_required)
        self.assertIsNone(following.endorsed_at)
        self.assertTrue(independent(self.team))
        self.assertEqual((self.team.project_version, self.team.semester_id), (version, semester))
        self.assertIsNone(services.project_for(self.team, self.stage))
        self.assertFalse(services.active_links(self.project).exists())
        self.assertTrue(self.project.team_links.filter(team=self.team).exists())
        self.assertIsNone(shared_deliverables.resolve(self.team, self.stage))
        self.assertEqual(resolve_policy(self.team, self.stage)['source'], 'chair_independent')
        self.assertEqual(services.team_display(self.team)['system_name'], '')
        from student_teams.serializers import StudentTeamSerializer
        context = StudentTeamSerializer(self.team).data['defense_context']
        self.assertEqual(context['stage_verdict'], 'for_redefense')
        self.assertIsNone(context['concept_workflow']['section_project_id'])
        self.assertFalse(context['concept_workflow']['shared_import_pending'])
        self.assertEqual(context['concept_workflow']['system_concepts'], [])
        self.assertEqual(services.module_blocker(self.team, self.stage, following), '')
        from student_teams.capstone_lifecycle import team_snapshot
        self.assertEqual(team_snapshot(self.team)['project_direction'], 'independent')
        state = concepts.payload(self.team, self.stage, actor=self.student)
        self.assertEqual(state['selection_mode'], 'team_concept')
        self.assertFalse(state['shared_import_pending'])
        self.assertEqual(state['history'][0]['next_attempt_direction']['direction'], 'independent')
        self.assertEqual(Decision.objects.get().preparation_snapshot['concepts'][0]['key'], 'c2')
        self.assertEqual(self.grade.panelist_submissions.count(), 1)

    def test_only_assigned_chair_can_confirm_including_admin(self):
        self.prepare_redefense()
        token = payload(self.grade, self.chair)['review_token']
        for actor in (self.admin, self.adviser, self.student):
            self.assertFalse(payload(self.grade, actor)['can_decide'])
            with self.assertRaises(PermissionError):
                confirm(self.grade, actor=actor, direction='independent',
                    source_round_id=self.source.pk, review_token=token)
        self.assertFalse(Decision.objects.exists())

    def test_recommendations_do_not_confirm_route_and_confirmation_does_not_change_notes(self):
        from grading.grades.automatic_outcomes import save_recommendations
        self.prepare_redefense()
        save_recommendations(self.grade, actor=self.chair, notes='Adapt the inventory idea into a full project.')
        self.assertFalse(Decision.objects.exists())
        self.decide()
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict_remarks, 'Adapt the inventory idea into a full project.')

    def test_stale_preparation_token_rolls_back_and_repeat_confirmation_is_idempotent(self):
        following = self.prepare_redefense()
        old = payload(self.grade, self.chair)['review_token']
        following.concepts[0]['title'] = 'Saved revised module'
        following.save(update_fields=['concepts'])
        with self.assertRaises(ValidationError):
            self.decide(review_token=old)
        self.assertFalse(Decision.objects.exists())
        self.assertFalse(independent(self.team))
        self.decide()
        self.decide()
        self.assertEqual(Decision.objects.count(), 1)
        with self.assertRaises(ValidationError):
            self.decide('shared_module')

    def test_api_returns_recorded_direction_and_rejects_stale_review(self):
        self.prepare_redefense()
        self.client.force_authenticate(self.chair)
        url = f'/api/grading/grades/{self.grade.pk}/assessment/'
        data = {'action': 'redefense_direction', 'direction': 'independent',
            'source_round_id': self.source.pk, 'review_token': 'stale'}
        self.assertEqual(self.client.post(url, data, format='json').status_code, 400)
        data['review_token'] = payload(self.grade, self.chair)['review_token']
        response = self.client.post(url, data, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['grade']['workflow']['redefense_direction']['direction'], 'independent')

    def post_with_recommendations(self, direction, notes, **overrides):
        self.grade.refresh_from_db()
        current = payload(self.grade, self.chair)
        self.client.force_authenticate(self.chair)
        return self.client.post(f'/api/grading/grades/{self.grade.pk}/assessment/', {
            'action': 'redefense_direction', 'direction': direction,
            'source_round_id': self.source.pk, 'review_token': current['review_token'],
            'recommendations': notes, **overrides}, format='json')

    def assert_combined_submission(self, direction, notes):
        following = self.prepare_redefense()
        response = self.post_with_recommendations(direction, notes)
        self.assertEqual(response.status_code, 200, response.data)
        self.grade.refresh_from_db()
        self.source.refresh_from_db()
        following.refresh_from_db()
        self.assertEqual(Decision.objects.get().direction, direction)
        self.assertEqual(self.grade.verdict_remarks, notes)
        self.assertEqual(self.source.remarks, notes)
        self.assertTrue(all(c['panel_feedback'] == notes for c in following.concepts))
        self.assertEqual(response.data['grade']['verdict_remarks'], notes)
        return response

    def test_api_shared_direction_and_recommendations_save_together(self):
        self.assert_combined_submission('shared_module', 'Improve the inventory workflow.')

    def test_api_independent_direction_and_recommendations_save_together(self):
        self.assert_combined_submission('independent', 'Propose a complete independent inventory system.')

    def test_api_combined_confirmation_keeps_recommendations_optional(self):
        self.assert_combined_submission('independent', '')

    def test_api_feedback_failure_rolls_back_direction_and_draft_conversion(self):
        following = self.prepare_redefense()
        before = deepcopy(following.concepts)
        for notes in ('x' * 5001, None):
            with self.subTest(notes_type=type(notes).__name__):
                response = self.post_with_recommendations('independent', notes)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertFalse(Decision.objects.exists())
                self.assertFalse(independent(self.team))
                self.grade.refresh_from_db()
                self.source.refresh_from_db()
                following.refresh_from_db()
                self.assertEqual(self.grade.verdict_remarks, '')
                self.assertEqual(self.source.remarks, '')
                self.assertEqual(following.concepts, before)
                self.assertEqual(following.section_round_id, self.source.section_round_id)

    def test_api_stale_decision_does_not_save_recommendations(self):
        self.prepare_redefense()
        response = self.post_with_recommendations('independent', 'Do not save stale feedback.', review_token='stale')
        self.assertEqual(response.status_code, 400, response.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict_remarks, '')
        self.assertFalse(Decision.objects.exists())

    def test_api_repeated_combined_confirmation_preserves_newer_feedback(self):
        from grading.grades.automatic_outcomes import save_recommendations
        self.prepare_redefense()
        original_token = payload(self.grade, self.chair)['review_token']
        response = self.post_with_recommendations('independent', 'Initial feedback.')
        self.assertEqual(response.status_code, 200, response.data)
        self.grade.refresh_from_db()
        save_recommendations(self.grade, actor=self.chair, notes='Updated feedback.')
        response = self.post_with_recommendations('independent', 'Initial feedback.', review_token=original_token)
        self.assertEqual(response.status_code, 200, response.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict_remarks, 'Updated feedback.')
        self.assertEqual(Decision.objects.count(), 1)

    def test_endorsed_repeat_and_published_outcome_are_not_eligible(self):
        from django.utils import timezone
        following = self.prepare_redefense()
        following.endorsed_at = timezone.now()
        following.save(update_fields=['endorsed_at'])
        self.assertFalse(payload(self.grade, self.chair)['can_decide'])
        with self.assertRaises(ValidationError):
            self.decide()
        following.endorsed_at = None
        following.save(update_fields=['endorsed_at'])
        self.grade.status = 'published'
        self.grade.__class__.objects.filter(pk=self.grade.pk).update(status='published')
        self.assertFalse(payload(self.grade, self.chair)['can_decide'])

    def test_independent_titles_upload_review_endorsement_and_repeat_use_existing_flow(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from grading.grades.services import GradeContextService
        from repository import title_workflow
        from repository.deliverables.services import upsert_submission, review_submission, endorse_team
        from student_teams.services import is_stage_ready
        self.prepare_redefense()
        self.decide()
        for attempt in (2, 3):
            self.assertFalse(is_stage_ready(self.team, self.stage))
            for key in services.KEYS:
                title_workflow.team_action(self.team, self.stage, self.student, 'submit_title', key,
                    title=f'Independent project {attempt} {key}')
                # Upload is allowed before title acceptance, but scheduling is not.
                submission = upsert_submission(self.team, self.stage.label, 'CONCEPTS', f'{key}.pdf',
                    '20 B', self.student, file=SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 independent'),
                    slot_key=f'{key}:paper')
                title_workflow.team_action(self.team, self.stage, self.adviser, 'accept_title', key)
                review_submission(self.team, self.stage.label, 'CONCEPTS', 'accepted', '', self.adviser,
                    file_id=submission.files.get(is_current=True, slot_key=f'{key}:paper').pk,
                    title_review_token=concepts.module_review_token(self.team, self.stage))
                from repository.project_archive.payloads import capstone_entry_payload
                from repository.project_archive.shared_concepts import attach_shared_team_context
                entries = capstone_entry_payload(submission)
                attach_shared_team_context(entries)
                self.assertTrue(all(not entry.get('shared_owner') for entry in entries))
            self.assertFalse(is_stage_ready(self.team, self.stage))
            endorse_team(self.team, self.stage.label, self.adviser)
            self.assertTrue(is_stage_ready(self.team, self.stage))
            schedule = DefenseSchedule.objects.create(team=self.team, semester=self.semester,
                defense_stage=self.stage, rubric=self.schedule.rubric,
                scheduled_date=self.schedule.scheduled_date, start_time=f'{8 + attempt}:00',
                room=f'Independent {attempt}')
            SchedulePanelist.objects.create(schedule=schedule, panelist=self.chair, is_chair=True)
            grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
            current = ConceptRound.objects.get(schedule=schedule)
            self.assertIsNone(current.section_round_id)
            self.assertEqual(concept_keys(schedule), ['c1', 'c2', 'c3'])
            for key in services.KEYS:
                submit_panelist_grade(schedule, grade, [{'criterion_id': self.criterion.pk,
                    'score': 6 if attempt == 2 or key != 'c2' else 8}],
                    panelist=self.chair, concept_key=key)
            grade.refresh_from_db()
            self.assertEqual(grade.verdict, 'for_redefense' if attempt == 2 else 'approved')
            if attempt == 2:
                following = concepts.latest_round(self.team, self.stage)
                self.assertIsNone(following.section_round_id)
                self.assertEqual(len(following.concepts), 3)
                self.assertEqual(following.policy_snapshot['source'], 'chair_independent')
            else:
                self.assertEqual(grade.panel_score, 80)
        self.assertEqual(Decision.objects.count(), 1)
        self.assertEqual(self.source.section_round.project.team_links.count(), 1)

    def test_departure_preserves_other_teams_and_requires_remaining_project_manager(self):
        from django.contrib.auth import get_user_model
        from student_teams.models import StudentTeam, TeamMembership
        from .models import SectionProjectTeam
        following = self.prepare_redefense()
        leader = get_user_model().objects.create_user(username='remaining-shared-leader', role='student')
        remaining = StudentTeam.objects.create(name='Remaining shared team', project_title='Other module',
            level=self.team.level, year_level=self.team.year_level, section=self.team.section,
            semester=self.semester, leader=leader, adviser=self.adviser, status=self.team.status)
        TeamMembership.objects.create(team=remaining, student=leader, is_leader=True)
        SectionProjectTeam.objects.create(project=self.project, team=remaining,
            project_version=remaining.project_version)
        before = deepcopy(following.concepts)
        self.assertIn('manager', payload(self.grade, self.chair)['independent_unavailable_reason'])
        with self.assertRaises(ValidationError):
            self.decide()
        following.refresh_from_db()
        self.assertEqual(following.concepts, before)
        self.assertFalse(Decision.objects.exists())
        # Existing responsibility management updates the project manager.
        self.project.project_manager = leader
        self.project.save(update_fields=['project_manager'])
        self.decide()
        self.assertEqual(list(services.active_links(self.project).values_list('team_id', flat=True)), [remaining.pk])
        self.assertIsNotNone(services.project_for(remaining, self.stage))
        self.assertEqual(remaining.project_title, 'Other module')
        self.assertEqual(services.visible_projects(self.student, team_id=self.team.pk), [])
        self.assertFalse(services.can_read(self.student, self.project))
        paper = self.source.section_round.systems.get(key='c2').papers.get(is_current=True)
        self.assertTrue(shared_deliverables.can_read_legacy_file(self.student, paper))
        from datetime import timedelta
        from django.utils import timezone
        paper.uploaded_at = timezone.now() + timedelta(seconds=1)
        self.assertFalse(shared_deliverables.can_read_legacy_file(self.student, paper))

    def test_reviewed_scope_adoption_is_explicit_and_leaves_other_policy_values_intact(self):
        from django.core.management import call_command
        from io import StringIO
        import json
        self.schedule.assessment_policy.pop('shared_module_scope_version')
        self.schedule.save(update_fields=['assessment_policy'])
        before = deepcopy(self.schedule.assessment_policy)
        output = StringIO()
        call_command('automatic_outcome_adoption_report', shared_module_scope=True,
            schedule_id=[self.schedule.pk], stdout=output)
        report = json.loads(output.getvalue())
        self.assertTrue(report['hearings'][0]['eligible'], report)
        self.schedule.refresh_from_db()
        self.assertEqual(self.schedule.assessment_policy, before)
        call_command('automatic_outcome_adoption_report', shared_module_scope=True,
            schedule_id=[self.schedule.pk], apply=True, review_token=report['review_token'],
            reason='Reviewed this unstarted hearing.', stdout=StringIO())
        self.schedule.refresh_from_db()
        after = self.schedule.assessment_policy.copy()
        self.assertEqual(after.pop('shared_module_scope_version'), 1)
        after.pop('shared_module_scope_adoption')
        self.assertEqual(after, before)

    def test_admin_assigned_as_chair_decides_directly_without_second_approval(self):
        from defense.scheduler.models import SchedulePanelist
        SchedulePanelist.objects.filter(schedule=self.schedule).delete()
        SchedulePanelist.objects.create(schedule=self.schedule, panelist=self.admin, is_chair=True)
        self.chair = self.admin
        self.prepare_redefense()
        current = payload(self.grade, self.admin)
        self.assertTrue(current['can_decide'])
        confirm(self.grade, actor=self.admin, direction='independent', source_round_id=self.source.pk,
            review_token=current['review_token'])
        self.assertEqual(Decision.objects.get().decided_by_id, self.admin.pk)

    def test_final_submission_keeps_unselected_private_drafts(self):
        from defense.scheduler.panelist_evaluation import retire_submitted_draft
        submissions = [{'concept_key': key, 'criteria_scores': [
            {'criterion_id': self.criterion.pk, 'score': 7}]} for key in services.KEYS]
        save_evaluation_draft(self.schedule, {'evaluation_context': evaluation_context(self.schedule, self.grade),
            'submissions': submissions}, panelist=self.chair)
        self.choose()
        self.score()
        retire_submitted_draft(self.schedule, panelist=self.chair)
        self.assertEqual([row['concept_key'] for row in self.schedule.evaluation_drafts.get().submissions], ['c1', 'c3'])
        self.assertEqual(list(self.grade.panelist_submissions.values_list('concept_key', flat=True)), ['c2'])

    def test_file_preparation_failure_rolls_back_the_entire_direction(self):
        from unittest.mock import patch
        following = self.prepare_redefense()
        with patch('repository.deliverables.redefense.refresh_files', side_effect=ValidationError('File preparation failed.')):
            with self.assertRaises(ValidationError):
                self.decide()
        following.refresh_from_db()
        self.team.refresh_from_db()
        self.assertFalse(Decision.objects.exists())
        self.assertFalse(independent(self.team))
        self.assertEqual(following.section_round_id, self.source.section_round_id)
        self.assertEqual([c['key'] for c in following.concepts], ['c2'])

    def test_three_concept_configuration_is_required_only_for_independent_route(self):
        self.prepare_redefense()
        self.stage.concept_config['required_count'] = 4
        self.stage.save(update_fields=['concept_config'])
        self.grade.refresh_from_db()
        state = payload(self.grade, self.chair)
        self.assertTrue(state['can_decide'])
        self.assertIn('three', state['independent_unavailable_reason'])
        with self.assertRaises(ValidationError):
            self.decide()
        self.assertFalse(Decision.objects.exists())
        self.decide('shared_module')

    def test_selected_module_still_requires_every_member_and_external_evaluator(self):
        from django.contrib.auth import get_user_model
        from authentication_access_control.guest_authentication import GuestPanelistPrincipal
        from grading.grades.outcome_rules import capture_policy
        from grading.rubrics.models import RubricCriterion
        from student_teams.models import TeamMembership
        from user_management.models import GuestPanelistCode
        member = get_user_model().objects.create_user(username='selected-second-member', role='student')
        TeamMembership.objects.create(team=self.team, student=member)
        rubric = self.schedule.rubric
        rubric.target_type = 'both'
        rubric.save(update_fields=['target_type'])
        individual = RubricCriterion.objects.create(rubric=rubric, name='Individual defense',
            max_score=10, scale=rubric.SCALE_10, target_type='individual', display_order=1)
        self.schedule.assessment_policy = capture_policy(self.schedule)
        self.schedule.save(update_fields=['assessment_policy'])
        invitation = GuestPanelistCode.objects.create(guest_name='Selected module external panel',
            defense_schedule=self.schedule)
        invitation.schedules.add(self.schedule)
        guest = GuestPanelistPrincipal({'guest_code_id': str(invitation.pk), 'guest_code': invitation.code,
            'defense_schedule_id': self.schedule.pk, 'team_id': self.team.pk,
            'guest_name': invitation.guest_name}, invitation=invitation)
        self.choose()
        rows = [{'concept_key': 'c2', 'student_id': student.pk if student else None,
            'criteria_scores': [{'criterion_id': individual.pk if student else self.criterion.pk, 'score': 8}]}
            for student in (None, self.student, member)]
        with self.assertRaises(ValidationError):
            validate_evaluation_submissions(self.schedule, rows[:2])
        validate_evaluation_submissions(self.schedule, rows)
        for actor in (self.chair, guest):
            for index, student in enumerate((None, self.student, member)):
                submit_panelist_grade(self.schedule, self.grade, [{'criterion_id':
                    individual.pk if student else self.criterion.pk,
                    'score': 0 if actor is guest and student is self.student else 8}],
                    student=student, concept_key='c2',
                    **({'panelist': actor} if actor is self.chair else {'guest': actor}))
                self.grade.refresh_from_db()
                if actor is self.chair or index < 2:
                    self.assertEqual(self.grade.verdict, '')
        self.assertEqual(evaluator_completion(self.grade), {'submitted': 2, 'required': 2})
        self.assertEqual(self.grade.verdict, 'for_redefense')
        self.assertEqual(set(self.grade.panelist_submissions.values_list('concept_key', flat=True)), {'c2'})


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedDirectionConcurrencyTests(APITransactionTestCase):
    # Suppress post_migrate during the flush below: it would recreate content
    # types with new IDs before restoring the serialized migration fixtures.
    serialized_rollback = True
    setUp = SharedRedefenseDirectionTests.setUp
    prepare_hearing = SharedRedefenseDirectionTests.prepare_hearing
    prepare_redefense = SharedRedefenseDirectionTests.prepare_redefense
    choose = SharedRedefenseDirectionTests.choose
    score = SharedRedefenseDirectionTests.score

    def _fixture_teardown(self):
        super()._fixture_teardown()
        from django.db import connections
        for alias in self._databases_names(include_mirrors=False):
            connection = connections[alias]
            if hasattr(connection, '_test_serialized_contents'):
                connection.creation.deserialize_db_from_string(connection._test_serialized_contents)

    def test_simultaneous_different_routes_record_exactly_one_direction(self):
        from concurrent.futures import ThreadPoolExecutor
        from threading import Barrier
        from unittest.mock import patch
        from django.db import close_old_connections
        from grading.grades.models import TeamGrade
        self.prepare_redefense()
        token = payload(self.grade, self.chair)['review_token']
        barrier = Barrier(2)

        def decide(direction):
            close_old_connections()
            try:
                grade = TeamGrade.objects.select_related('schedule').get(pk=self.grade.pk)
                barrier.wait(timeout=10)
                try:
                    confirm(grade, actor=self.chair, direction=direction,
                        source_round_id=self.source.pk, review_token=token,
                        recommendations=f'Feedback for {direction}.')
                    return 'recorded'
                except ValidationError:
                    return 'stale'
            finally:
                close_old_connections()

        with patch('realtime.broadcast.notify_capstone_evaluation_flags'), ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(decide, ['shared_module', 'independent']))
        self.assertCountEqual(results, ['recorded', 'stale'])
        self.assertEqual(Decision.objects.count(), 1)
        following = ConceptRound.objects.get(team=self.team, number=2)
        independent_route = Decision.objects.get().direction == 'independent'
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict_remarks, f'Feedback for {Decision.objects.get().direction}.')
        self.assertEqual(independent(self.team), independent_route)
        self.assertEqual(following.section_round_id is None, independent_route)
        self.assertEqual(len(following.concepts), 3 if independent_route else 1)
