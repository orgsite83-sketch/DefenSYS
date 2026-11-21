"""Chair-authored corrections for new hearings; captured history stays intact."""
import uuid
from copy import deepcopy
from datetime import timedelta
from io import BytesIO

from django.core.exceptions import ValidationError
from django.test import override_settings
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from . import test_deliberation as fixtures
from .deliberation import confirm, decision_payload, payload
from .models import TeamGrade
from .outcome_models import DefenseOutcome
from .outcome_rules import capture_policy as current_policy, outcome_payload


def capture_policy(schedule):
    """Retain regression coverage of already captured chair-authored v2 hearings."""
    return {**current_policy(schedule), 'deliberation_version': 2}


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ChairRevisionTests(APITestCase):
    _rubric = fixtures.PanelDeliberationTests._rubric
    new_hearing = fixtures.PanelDeliberationTests.new_hearing
    submit = fixtures.PanelDeliberationTests.submit
    booking = fixtures.PanelDeliberationTests.booking

    def setUp(self):
        fixtures.PanelDeliberationTests.setUp(self)
        self.stage.revision_areas = []
        self.stage.save(update_fields=['revision_areas'])
        self.capstone_schedule.assessment_policy = capture_policy(self.capstone_schedule)
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        self.grade = TeamGrade.objects.select_related('schedule').get(pk=self.grade.pk)

    def decision(self, verdict='approved_with_revisions', **changes):
        self.grade.refresh_from_db()
        data = {'request_id': str(uuid.uuid4()), 'review_token': outcome_payload(self.grade)['review_token'],
            'verdict': verdict, 'reason': '', 'instructions': '', 're_demo_required': False,
            'demo_requirements': [], 'revision_entries': [
                {'area_id': 'system', 'label': 'Access controls', 'severity': 'minor',
                 'instructions': 'Restrict report exports to the assigned coordinator.'},
                {'area_id': 'paper', 'label': 'Manuscript', 'severity': 'major',
                 'instructions': 'Update the access-control discussion and test results.'}]
            if verdict == 'approved_with_revisions' else []}
        data.update(changes)
        return data

    def confirm_source(self, demo=False):
        self.submit(8.2)
        return confirm(self.grade, actor=self.panelist, data=self.decision(
            re_demo_required=demo, demo_requirements=[
                {'area_id': 'system', 'text': 'Demonstrate report export restrictions.'}] if demo else []))

    def test_new_hearing_waits_for_chair_without_stage_categories(self):
        self.assertEqual(self.capstone_schedule.assessment_policy['deliberation_version'], 2)
        self.assertNotIn('revision_areas', self.capstone_schedule.assessment_policy)
        self.submit(8.2)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertFalse(DefenseOutcome.objects.exists())
        view = payload(self.grade, self.panelist)
        self.assertTrue(view['can_confirm'])
        self.assertEqual(view['revision_mode'], 'chair')
        self.assertEqual(view['revision_areas'], [])
        source = confirm(self.grade, actor=self.panelist, data=self.decision())
        self.assertEqual(source.revision_entries[0]['label'], 'Access controls')
        self.assertIn('assigned coordinator', source.revision_entries[0]['instructions'])

    def test_new_policy_ignores_legacy_categories_and_stage_edits(self):
        self.stage.revision_areas = [{'id': 'legacy', 'label': 'Old category', 'allows_demo': False}]
        self.stage.save(update_fields=['revision_areas'])
        self.assertEqual(capture_policy(self.capstone_schedule)['deliberation_version'], 2)
        self.assertNotIn('revision_areas', capture_policy(self.capstone_schedule))
        source = self.confirm_source()
        self.stage.revision_areas = []
        self.stage.save(update_fields=['revision_areas'])
        source.refresh_from_db()
        self.assertEqual(source.revision_entries[0]['label'], 'Access controls')

    def test_plain_approval_needs_no_revision_rows(self):
        self.submit(8.2)
        source = confirm(self.grade, actor=self.panelist, data=self.decision('approved'))
        self.assertEqual(source.revision_entries, [])
        self.assertFalse(source.re_demo_required)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, 82)

    def test_future_rule_edits_preserve_captured_categories_and_saved_hearings(self):
        categories = [{'id': 'legacy', 'label': 'Original category', 'allows_demo': False}]
        self.stage.revision_areas = categories
        self.stage.save(update_fields=['revision_areas'])
        self.capstone_schedule.assessment_policy = fixtures.legacy_policy(self.capstone_schedule)
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        captured = deepcopy(self.capstone_schedule.assessment_policy)
        self.client.force_authenticate(self.admin)
        response = self.client.patch(f'/api/defense/stages/{self.stage.pk}/',
            {'qualifying_score': 90, 'score_carryover': 'retain'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.stage.refresh_from_db()
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.stage.revision_areas, categories)
        self.assertEqual(self.capstone_schedule.assessment_policy, captured)
        self.assertEqual(capture_policy(self.capstone_schedule)['deliberation_version'], 2)

    def test_incomplete_or_invalid_corrections_reject_the_entire_decision(self):
        self.submit(8.2)
        valid = self.decision()['revision_entries']
        invalid = [[], [{'area_id': 'system', 'label': '', 'severity': 'minor', 'instructions': 'Fix it.'}],
            [{**valid[0], 'severity': 'none'}], [{**valid[0], 'instructions': '  '}],
            [{**valid[0], 'instructions': 'x' * 2001}], [valid[0], valid[0]],
            [valid[0], {**valid[1], 'label': 'ACCESS CONTROLS'}],
            [{**valid[0], 'allows_demo': True}], [{**valid[0], 'area_id': 'bad id'}],
            [*valid] * 7]
        for entries in invalid:
            with self.subTest(entries=entries), self.assertRaises(ValidationError):
                confirm(self.grade, actor=self.panelist, data=self.decision(revision_entries=entries))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertFalse(DefenseOutcome.objects.exists())

    def test_approval_and_redefense_reject_hidden_correction_or_demo_payloads(self):
        self.submit(8.2)
        for verdict in ('approved', 'for_redefense'):
            for changes in ({'revision_entries': self.decision()['revision_entries']},
                    {'re_demo_required': True, 'demo_requirements': [{'area_id': 'system', 'text': 'Show it.'}]}):
                with self.subTest(verdict=verdict, changes=changes), self.assertRaises(ValidationError):
                    confirm(self.grade, actor=self.panelist, data=self.decision(verdict,
                        reason='Another assessment is needed.', instructions='Complete the workflow.', **changes))
        self.assertFalse(DefenseOutcome.objects.exists())

    def test_only_assigned_chair_can_confirm_and_incomplete_panel_still_blocks(self):
        self.submit(8.2)
        for actor in (self.admin, self.adviser, self.student):
            with self.assertRaises(PermissionError):
                confirm(self.grade, actor=actor, data=self.decision())
        other = self.panelist.__class__.objects.create_user(username='chair-revision-extra', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=other)
        with self.assertRaises(ValidationError):
            confirm(self.grade, actor=self.panelist, data=self.decision())
        self.assertFalse(DefenseOutcome.objects.exists())

    def test_below_cutoff_still_requires_redefense_and_no_checklist(self):
        self.submit(6)
        with self.assertRaises(ValidationError):
            confirm(self.grade, actor=self.panelist, data=self.decision())
        source = confirm(self.grade, actor=self.panelist, data=self.decision('for_redefense'))
        self.assertEqual(source.decision_source, 'cutoff_required')
        self.assertEqual(source.revision_entries, [])

    def test_redefense_collects_fresh_panel_scores_and_can_receive_new_corrections(self):
        from .services import GradeContextService, submit_panelist_grade
        self.submit(8.2)
        source = confirm(self.grade, actor=self.panelist, data=self.decision('for_redefense',
            reason='The panel needs a complete demonstration.', instructions='Finish the report workflow.'))
        repeat = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric,
            scheduled_date=self.capstone_schedule.scheduled_date + timedelta(days=7), start_time='09:00', room='Repeat')
        repeat.assessment_policy['deliberation_version'] = 2
        repeat.save(update_fields=['assessment_policy'])
        SchedulePanelist.objects.create(schedule=repeat, panelist=self.panelist, is_chair=True)
        grade, _, _ = GradeContextService.get_or_create_for_schedule(repeat)
        self.assertIsNone(grade.panel_score)
        self.assertEqual(grade.verdict, '')
        self.assertEqual(repeat.assessment_policy['deliberation_version'], 2)
        submit_panelist_grade(repeat, grade,
            [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 9}], panelist=self.panelist)
        self.grade = grade
        followup = confirm(grade, actor=self.panelist, data=self.decision())
        self.assertEqual(followup.verdict, 'approved_with_revisions')
        source.refresh_from_db()
        self.assertEqual(source.verdict, 'for_redefense')
        self.assertEqual(source.revision_entries, [])

    def test_redemo_verifies_chair_tasks_without_rescoring_or_clearing_other_revisions(self):
        from defense.redemo.services import verify, token, outstanding
        from .defense_workflow import apply_workflow_action
        source = self.confirm_source(demo=True)
        counts = (TeamGrade.objects.count(), DefenseSchedule.objects.count())
        with self.assertRaisesMessage(ValidationError, 're-demo'):
            apply_workflow_action(self.grade, actor=self.panelist, action='clear_revisions', reason='Reviewed changes.')
        appointment = self.booking(source)
        self.assertEqual(appointment.requirements, source.demo_requirements)
        verify(appointment, actor=self.panelist, data={'request_id': str(uuid.uuid4()),
            'review_token': token(appointment), 'results': [
                {'requirement_id': item['id'], 'status': 'satisfied'} for item in appointment.requirements], 'remarks': ''})
        self.assertEqual(outstanding(source), [])
        self.assertEqual((TeamGrade.objects.count(), DefenseSchedule.objects.count()), counts)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, 82)
        self.assertIsNone(self.grade.revisions_cleared_at)
        apply_workflow_action(self.grade, actor=self.panelist, action='clear_revisions', reason='Reviewed manuscript and access controls.')

    def test_demo_requires_explicit_tasks_linked_to_current_corrections(self):
        self.submit(8.2)
        for changes in ({'re_demo_required': True}, {'demo_requirements': [{'area_id': 'system', 'text': 'Show export.'}]},
                {'re_demo_required': True, 'demo_requirements': [{'area_id': 'missing', 'text': 'Show export.'}]},
                {'re_demo_required': True, 'demo_requirements': [{'area_id': 'system', 'text': '  '}]}):
            with self.subTest(changes=changes), self.assertRaises(ValidationError):
                confirm(self.grade, actor=self.panelist, data=self.decision(**changes))

    def test_amendment_preserves_original_correction_text_and_demo_identities(self):
        from .corrections import request_correction, review_correction
        source = self.confirm_source(demo=True)
        original = deepcopy(source.revision_entries)
        original_demonstrations = deepcopy(source.demo_requirements)
        changes = self.decision()
        changes.pop('request_id')
        changes['revision_entries'][0]['instructions'] = 'Restrict all export formats to the coordinator.'
        changes.update(source_revision=source.revision, re_demo_required=True,
            demo_requirements=[{'area_id': row['area_id'], 'text': row['text']} for row in source.demo_requirements])
        item = request_correction(self.grade.pk, self.panelist, {'reason': 'Clarify the requested correction.',
            'expected_updated_at': self.grade.updated_at.isoformat(), 'changes': {'panel_decision': changes}})
        source.refresh_from_db()
        self.assertEqual(source.revision_entries, original)
        review_correction(self.grade.pk, item['id'], self.admin,
            {'action': 'approve', 'reason': 'Checked the panel instructions.', 'acknowledge_published_change': True})
        source.refresh_from_db()
        self.assertEqual(source.history[0]['revision_entries'], original)
        self.assertEqual(source.revision_entries[0]['instructions'], changes['revision_entries'][0]['instructions'])
        self.assertEqual(source.demo_requirements, original_demonstrations)

    def test_minutes_pdf_includes_each_correction_and_demo_task(self):
        import pdfplumber
        from defense.minutes.models import DefenseMinutes
        from defense.minutes.pdf_generator import generate_minutes_pdf
        source = self.confirm_source(demo=True)
        minutes = DefenseMinutes.objects.create(schedule=self.capstone_schedule,
            team_name=self.capstone_team.name, defense_date=self.capstone_schedule.scheduled_date,
            defense_time=self.capstone_schedule.start_time, outcome_snapshot=decision_payload(source, public=True))
        with pdfplumber.open(BytesIO(generate_minutes_pdf(minutes, include_signatures=False))) as document:
            text = '\n'.join(page.extract_text() or '' for page in document.pages)
            for entry in source.revision_entries:
                self.assertIn(entry['instructions'], text)
            self.assertIn(source.demo_requirements[0]['text'], text)


class ChairConceptRevisionTests(fixtures.ConceptDeliberationTests):
    """Run real concept selection and repeats with the new correction policy."""

    def setUp(self):
        super().setUp()
        self.capstone_schedule.assessment_policy = capture_policy(self.capstone_schedule)
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        self.grade.refresh_from_db()

    def confirm(self, verdict='approved', **changes):
        changes.setdefault('revision_entries', [])
        return super().confirm(verdict, **changes)

    def test_qualifying_concept_and_its_corrections_are_confirmed_together(self):
        self.submit([8, 9, 7])
        source = self.confirm('approved_with_revisions', selected_key='c2', revision_entries=[
            {'area_id': 'scope', 'label': 'Concept scope', 'severity': 'minor',
             'instructions': 'Clarify the selected proposal boundaries.'}])
        self.assertEqual(source.selected_key, 'c2')
        self.assertEqual(source.revision_entries[0]['instructions'], 'Clarify the selected proposal boundaries.')


class ChairSharedRevisionTests(fixtures.SharedDeliberationTests):
    def setUp(self):
        super().setUp()
        self.schedule.assessment_policy = capture_policy(self.schedule)
        self.schedule.save(update_fields=['assessment_policy'])
        self.grade.refresh_from_db()
