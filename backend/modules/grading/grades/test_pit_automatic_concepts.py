"""PIT concept hearings share assessment rules without joining Capstone stages."""
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from defense.scheduler.models import SchedulePanelist, PitEventGradingConfig
from repository.deliverables import concepts, pit_decisions
from repository.deliverables.models import ConceptRound
from repository.deliverables import test_pit_concepts as fixtures
from .automatic_outcomes import resolve_outcome, save_recommendations
from .models import TeamGrade
from .outcome_rules import outcome_payload
from .services import submit_panelist_grade
from repository.section_concepts import tests as shared_fixtures


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PitAutomaticConceptTests(APITestCase):
    rubric = fixtures.PitConceptTests.rubric
    data = fixtures.PitConceptTests.data
    slot = fixtures.PitConceptTests.slot
    configure = fixtures.PitConceptTests.configure
    prepare = fixtures.PitConceptTests.prepare
    titles = fixtures.PitConceptTests.titles
    schedule = fixtures.PitConceptTests.schedule

    def setUp(self):
        fixtures.PitConceptTests.setUp(self)
        self.configure(qualifying_score='75')
        self.prepare()
        self.hearing = self.schedule()
        self.grade = TeamGrade.objects.get(schedule=self.hearing)

    def submit(self, values, panelist=None):
        criterion = self.panel.criteria.first()
        for i, value in enumerate(values, 1):
            submit_panelist_grade(self.hearing, self.grade,
                [{'criterion_id': criterion.pk, 'score': value}],
                panelist=panelist or self.panelist, concept_key=f'c{i}')
        self.grade.refresh_from_db()

    def test_one_qualifies_and_only_selected_concept_becomes_team_grade(self):
        self.submit([6, 8, 7])
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.final_grade, Decimal('80'))
        self.assertIsNone(self.grade.peer_score)
        self.assertEqual(self.grade.scope, 'pit')
        self.assertIsNone(self.grade.defense_stage_id)
        self.assertEqual(self.grade.pit_event_config_id, self.event.pk)
        self.team.refresh_from_db()
        self.assertEqual(self.team.project_title, 'PIT proposal 2')

    def test_multiple_qualify_only_chair_can_select_and_low_scoring_concept_is_rejected(self):
        self.submit([8, 9, 6])
        self.assertEqual(self.grade.verdict, '')
        self.assertIsNone(self.grade.final_grade)
        rule = outcome_payload(self.grade)
        with self.assertRaises(PermissionError):
            resolve_outcome(self.grade, actor=self.first, selected_key='c1', review_token=rule['review_token'])
        with self.assertRaises(ValidationError):
            resolve_outcome(self.grade, actor=self.panelist, selected_key='c3', review_token=rule['review_token'])
        resolve_outcome(self.grade, actor=self.panelist, selected_key='c1', review_token=rule['review_token'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.final_grade, Decimal('80'))

    def test_no_qualifier_repeats_current_event_without_fabricating_grade(self):
        self.submit([6, 5, 7])
        self.assertEqual(self.grade.verdict, 'for_redefense')
        self.assertIsNone(self.grade.final_grade)
        following = concepts.latest_round(self.team, self.event)
        self.assertEqual(following.number, 2)
        self.assertEqual([c['key'] for c in following.concepts], ['c1', 'c2', 'c3'])
        self.assertEqual(following.pit_event_config_id, self.event.pk)
        self.assertIsNone(following.defense_stage_id)
        self.assertEqual(self.hearing.panelist_grade_submissions.count(), 3)

    def test_incomplete_panel_and_exact_cutoff(self):
        SchedulePanelist.objects.create(schedule=self.hearing, panelist=self.unassigned)
        self.submit([Decimal('7.5'), 5, 6])
        self.assertEqual(self.grade.verdict, '')
        self.assertFalse(outcome_payload(self.grade)['panel_complete'])
        self.submit([Decimal('7.5'), 5, 6], panelist=self.unassigned)
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(self.grade.final_grade, Decimal('75'))

    def test_legacy_decision_route_cannot_override_automatic_hearing(self):
        self.submit([8, 9, 6])
        with self.assertRaises(ValidationError):
            pit_decisions.record_decision(self.team, self.event, self.first,
                [{'key': 'c3', 'decision': 'approved'}],
                token=pit_decisions.review_token(ConceptRound.objects.get(schedule=self.hearing)))

    def test_chair_selects_through_shared_assessment_api(self):
        self.submit([8, 9, 6])
        self.client.force_authenticate(self.panelist)
        response = self.client.post(f'/api/grading/grades/{self.grade.pk}/assessment/', {
            'action': 'select_concept', 'concept_key': 'c2',
            'review_token': outcome_payload(self.grade)['review_token'],
            'recommendations': 'Proceed with this concept.',
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.final_grade, Decimal('90'))
        self.assertEqual(self.grade.scope, 'pit')

    def test_repeat_hearing_preserves_attempt_and_starts_fresh_in_same_event(self):
        self.submit([6, 5, 7])
        self.prepare()
        following = self.schedule(day=1)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.schedule_id, following.pk)
        self.assertEqual(self.grade.attempt_count, 2)
        self.assertIsNone(self.grade.final_grade)
        self.assertEqual(self.grade.verdict, '')
        self.assertTrue(self.grade.attempt_history.filter(schedule=self.hearing).exists())
        self.assertEqual(self.hearing.panelist_grade_submissions.count(), 3)

    def test_selected_concept_and_required_post_file_complete_the_event(self):
        from django.core.files.uploadedfile import SimpleUploadedFile
        from repository.deliverables.services import upsert_submission, review_submission
        from .services import StageCompletionService
        self.submit([6, 8, 7])
        post = upsert_submission(self.team, self.event.label, 'APPROVED_CONCEPT',
            'approved.pdf', '10 B', self.team.leader,
            file=SimpleUploadedFile('approved.pdf', b'%PDF-1.4 selected concept'))
        review_submission(self.team, self.event.label, 'APPROVED_CONCEPT', 'accepted', '',
            self.first, file_id=post.files.get(is_current=True).pk)
        StageCompletionService.complete_group(semester=self.semester, scope='pit',
            stage_label=self.event.label, config=self.event, user=self.first)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.status, 'published')
        self.assertEqual(self.grade.final_grade, Decimal('80'))

    def test_concept_retry_does_not_block_an_independent_normal_event(self):
        from django.utils import timezone
        self.submit([6, 5, 7])
        event = PitEventGradingConfig.objects.create(semester=self.semester,
            year_level=self.team.year_level, event_name='Independent demonstration',
            panel_rubric=self.panel, peer_rubric=self.peer)
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/defense/schedules/', self.slot(self.team,
            event_name=event.event_name, start_time='14:00',
            scheduled_date=str(timezone.localdate()), chair_panelist_id=self.panelist.pk), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        from defense.scheduler.models import DefenseSchedule
        schedule = DefenseSchedule.objects.filter(event_name=event.event_name).get()
        self.assertEqual(schedule.assessment_policy, {})
        self.assertFalse(schedule.grade_records.get().uses_defense_verdict)

    def test_recommendations_do_not_leak_into_another_event(self):
        self.submit([6, 5, 7])
        other = PitEventGradingConfig.objects.create(semester=self.semester, year_level='1st Year',
            event_name='Other concept event', concept_config={'enabled': True})
        unrelated = ConceptRound.objects.create(team=self.team, pit_event_config=other,
            project_version=self.team.project_version, number=2, concepts=[{'key': 'c1', 'title': 'Other'}])
        save_recommendations(self.grade, actor=self.panelist, notes='Revise this event only.')
        unrelated.refresh_from_db()
        self.assertNotIn('panel_feedback', unrelated.concepts[0])

    def test_cutoff_is_captured_and_cannot_be_changed_by_live_setup(self):
        PitEventGradingConfig.objects.filter(pk=self.event.pk).update(
            concept_config={**self.event.concept_config, 'qualifying_score': '90'})
        self.submit([6, 8, 7])
        self.assertEqual(self.grade.verdict, 'approved')
        self.assertEqual(outcome_payload(self.grade)['qualifying_score'], 75)

    def adoption(self, **options):
        import json
        from io import StringIO
        from django.core.management import call_command
        output = StringIO()
        call_command('adopt_pit_concept_flow', event_id=self.event.pk,
            qualifying_score='75', schedule_id=[self.hearing.pk], stdout=output, **options)
        return json.loads(output.getvalue())

    def test_existing_untouched_hearing_has_preview_and_explicit_adoption(self):
        self.hearing.assessment_policy = {}
        self.hearing.save(update_fields=['assessment_policy'])
        report = self.adoption()
        self.assertTrue(report['read_only'])
        self.assertTrue(report['hearings'][0]['eligible'], report)
        self.hearing.refresh_from_db()
        self.assertEqual(self.hearing.assessment_policy, {})
        result = self.adoption(apply=True, review_token=report['review_token'], reason='Adopt reviewed PIT concepts')
        self.assertEqual(result['adopted_count'], 1)
        self.hearing.refresh_from_db()
        self.assertTrue(self.hearing.assessment_policy['automatic_outcomes'])

    def test_adoption_rejects_existing_scores(self):
        from django.core.management.base import CommandError
        submit_panelist_grade(self.hearing, self.grade,
            [{'criterion_id': self.panel.criteria.first().pk, 'score': 8}],
            panelist=self.panelist, concept_key='c1')
        report = self.adoption()
        self.assertFalse(report['hearings'][0]['eligible'])
        with self.assertRaises(CommandError):
            self.adoption(apply=True, review_token=report['review_token'], reason='Must refuse evidence')

    def test_full_assignment_payload_preserves_pit_scope_and_per_concept_work(self):
        from defense.scheduler.views import _team_assignment_payload
        self.assertTrue(self.grade.uses_defense_verdict)
        payload = _team_assignment_payload(self.hearing, team_grade=self.grade,
            is_chair=True, actor=self.panelist)
        self.assertEqual(payload['scope'], 'pit')
        self.assertFalse(payload['is_capstone'])
        self.assertTrue(payload['grade_record']['workflow']['outcome_rule']['automatic'])
        self.assertEqual(len(payload['assessment_concepts']), 3)


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PitSharedAutomaticConceptTests(APITestCase):
    setUp = shared_fixtures.SharedSystemConceptTests.setUp
    rubric = shared_fixtures.SharedSystemConceptTests.rubric
    data = shared_fixtures.SharedSystemConceptTests.data
    slot = shared_fixtures.SharedSystemConceptTests.slot
    titles = shared_fixtures.SharedSystemConceptTests.titles
    action = shared_fixtures.SharedSystemConceptTests.action
    prepare_shared = shared_fixtures.SharedSystemConceptTests.prepare_shared
    prepare_team = shared_fixtures.SharedSystemConceptTests.prepare_team
    hearing = shared_fixtures.SharedSystemConceptTests.hearing
    select = shared_fixtures.SharedSystemConceptTests.select

    def configure(self, **changes):
        return shared_fixtures.SharedSystemConceptTests.configure(self, qualifying_score='75', **changes)

    def test_shared_system_selection_resolves_only_its_linked_module(self):
        schedules = self.hearing(evaluated=False)
        for schedule, values in zip(schedules, ([9, 6, 8], [6, 8, 9])):
            grade = schedule.grade_records.get()
            for i, value in enumerate(values, 1):
                submit_panelist_grade(schedule, grade,
                    [{'criterion_id': self.panel.criteria.first().pk, 'score': value}],
                    panelist=self.panelist, concept_key=f'c{i}')
        response = self.select(actor=self.panelist)
        self.assertEqual(response.status_code, 200, response.data)
        first, second = [s.grade_records.get() for s in schedules]
        self.assertEqual(first.verdict, 'for_redefense')
        self.assertIsNone(first.final_grade)
        self.assertEqual(second.verdict, 'approved')
        self.assertEqual(second.final_grade, Decimal('80'))


class PitConceptPolicyValidationTests(SimpleTestCase):
    def test_cutoff_boundaries_and_invalid_values(self):
        from defense.document_policy import validate_concept_config
        for value in ('0', '75.25', '100'):
            with self.subTest(value=value):
                self.assertEqual(validate_concept_config({'enabled': True,
                    'qualifying_score': value})['qualifying_score'], value)
        for value in ('NaN', 'Infinity', '-1', '101', '75.555', True, ''):
            with self.subTest(value=value), self.assertRaises(ValidationError):
                validate_concept_config({'enabled': True, 'qualifying_score': value})
