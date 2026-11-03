"""Reviewed compatibility for active captured shared hearings, without losing drafts."""
from copy import deepcopy
from io import StringIO
import json

from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings
from rest_framework.test import APITestCase

from defense.scheduler.panelist_evaluation import evaluation_context, draft_payload, save_evaluation_draft, validate_evaluation_submissions
from grading.grades.outcome_rules import concept_keys, outcome_payload
from grading.grades.services import submit_panelist_grade
from . import test_redefense_direction as fixtures


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class OpenSharedScopeAdoptionTests(APITestCase):
    setUp = fixtures.SharedRedefenseDirectionTests.setUp
    prepare_hearing = fixtures.SharedRedefenseDirectionTests.prepare_hearing
    choose = fixtures.SharedRedefenseDirectionTests.choose
    score = fixtures.SharedRedefenseDirectionTests.score

    def legacy(self, *, draft=False):
        self.schedule.assessment_policy.pop('shared_module_scope_version')
        self.schedule.save(update_fields=['assessment_policy'])
        submissions = [{'concept_key': key, 'criteria_scores': [
            {'criterion_id': self.criterion.pk, 'score': 0 if key == 'c1' else 7}]} for key in ('c1', 'c2', 'c3')]
        if draft:
            save_evaluation_draft(self.schedule, {'evaluation_context': evaluation_context(self.schedule, self.grade),
                'submissions': submissions}, panelist=self.chair)
        self.choose()
        self.grade.refresh_from_db()
        return submissions

    def report(self, *, reviewed=True, **options):
        output = StringIO()
        call_command('automatic_outcome_adoption_report', shared_module_scope=True,
            review_open_shared_scope=reviewed, schedule_id=[self.schedule.pk], stdout=output, **options)
        return json.loads(output.getvalue())

    def adopt(self, report=None):
        current = report or self.report()
        return self.report(apply=True, review_token=current['review_token'],
            reason='Apply selected-module scope to this reviewed open hearing.')

    def test_opt_in_retains_draft_scores_and_changes_only_required_work(self):
        self.legacy(draft=True)
        draft = self.schedule.evaluation_drafts.get()
        original = deepcopy(draft.submissions)
        policy = deepcopy(self.schedule.assessment_policy)
        self.assertFalse(self.report(reviewed=False)['hearings'][0]['eligible'])
        report = self.report()
        self.assertTrue(report['hearings'][0]['eligible'], report)
        self.assertEqual(report['hearings'][0]['preserved_draft_count'], 1)
        self.schedule.refresh_from_db()
        self.assertEqual(self.schedule.assessment_policy, policy)
        self.adopt(report)
        self.schedule.refresh_from_db()
        draft.refresh_from_db()
        self.grade.refresh_from_db()
        self.assertEqual(concept_keys(self.schedule), ['c2'])
        self.assertEqual(draft.submissions, original)
        self.assertEqual(draft_payload(draft, evaluation_context(self.schedule, self.grade,
            include_scope=False))['submissions'], original)
        self.assertEqual(self.grade.panelist_submissions.count(), 0)
        self.assertEqual(self.grade.verdict, '')
        self.assertFalse(outcome_payload(self.grade)['panel_complete'])
        adopted = self.schedule.assessment_policy.copy()
        self.assertEqual(adopted.pop('shared_module_scope_version'), 1)
        adopted.pop('shared_module_scope_adoption')
        self.assertEqual(adopted, policy)
        with self.assertRaises(ValidationError):
            validate_evaluation_submissions(self.schedule, original)
        validate_evaluation_submissions(self.schedule, [original[1]])
        with self.assertRaises(ValidationError):
            self.score('c1', 8)

    def test_submitted_selected_score_is_reused_without_grading_alternatives_again(self):
        from defense.scheduler.models import SchedulePanelist
        self.legacy()
        second = self.chair.__class__.objects.create_user(username='scope-second-panel', role='faculty')
        SchedulePanelist.objects.create(schedule=self.schedule, panelist=second)
        for key in ('c1', 'c2', 'c3'):
            self.score(key, 6 if key == 'c2' else 9)
        original_ids = list(self.grade.panelist_submissions.values_list('pk', flat=True))
        self.adopt()
        self.schedule.refresh_from_db()
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertCountEqual(self.grade.panelist_submissions.values_list('pk', flat=True), original_ids)
        submit_panelist_grade(self.schedule, self.grade,
            [{'criterion_id': self.criterion.pk, 'score': 8}], panelist=second, concept_key='c2')
        self.grade.refresh_from_db()
        self.assertTrue(outcome_payload(self.grade)['panel_complete'])
        self.assertEqual(self.grade.verdict, 'for_redefense')

    def test_matching_completed_selected_evaluation_resolves_on_explicit_adoption(self):
        self.legacy()
        self.score('c2', 8)
        self.assertEqual(self.grade.verdict, '')
        self.adopt()
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.panel_score, 80)
        self.assertEqual(self.grade.panelist_submissions.count(), 1)

    def test_draft_edit_invalidates_review_and_stale_context_blocks_adoption(self):
        self.legacy(draft=True)
        report = self.report()
        draft = self.schedule.evaluation_drafts.get()
        draft.submissions[0]['criteria_scores'][0]['score'] = 5
        draft.save(update_fields=['submissions', 'updated_at'])
        with self.assertRaises(CommandError):
            self.adopt(report)
        self.schedule.refresh_from_db()
        self.assertNotIn('shared_module_scope_version', self.schedule.assessment_policy)
        draft.context_signature = 'unrelated-rubric-context'
        draft.save(update_fields=['context_signature'])
        self.assertFalse(self.report()['hearings'][0]['eligible'])

    def test_unselected_and_published_hearings_and_wrong_opt_in_are_rejected(self):
        self.schedule.assessment_policy.pop('shared_module_scope_version')
        self.schedule.save(update_fields=['assessment_policy'])
        self.assertFalse(self.report()['hearings'][0]['eligible'])
        self.choose()
        self.grade.__class__.objects.filter(pk=self.grade.pk).update(status='published')
        report = self.report()
        self.assertFalse(report['hearings'][0]['eligible'])
        with self.assertRaises(CommandError):
            self.adopt(report)
        with self.assertRaises(CommandError):
            call_command('automatic_outcome_adoption_report', review_open_shared_scope=True, stdout=StringIO())
