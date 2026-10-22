"""Phase 1 review rules, legacy clients, and existing-hearing compatibility."""
from importlib import import_module
from types import SimpleNamespace

from django.apps import apps
from django.db import connection
from django.test import override_settings
from rest_framework.test import APITestCase

from defense.document_policy import validate_concept_config
from defense.scheduler.models import DefenseSchedule, PitEventDeliverable, PitEventGradingConfig
from defense.scheduler.pit_config import pit_endorsement_required, upsert_pit_event_config
from defense.stages.models import StageDeliverable
from defense.stages.serializers import DefenseStageWriteSerializer, StageDeliverableSerializer
from grading.grades.models import TeamGrade
from student_teams.services import is_stage_ready, mark_stage_ready
from . import concepts
from .models import ConceptRound
from .services import (archive_unlocked, endorse_team, post_deliverables_complete, required_complete,
                       review_submission, stage_payload)
from .timing import materials_readiness
from . import test_submission_timing as fixtures


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class FacultyReviewPolicyTests(APITestCase):
    setUp = fixtures.SubmissionTimingTests.setUp
    upload = fixtures.SubmissionTimingTests.upload

    def accept(self, number, name='file.docx'):
        self.upload(number, name)
        review_submission(self.team, self.stage.label, number, 'accepted', '', self.adviser)

    def hearing(self, **kwargs):
        return DefenseSchedule.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            scheduled_date=self.date, start_time='09:00', room='Review room', **kwargs)

    def migrate_policy(self):
        migration = import_module('defense.migrations.0042_unified_faculty_review')
        migration.unify_faculty_review(apps, SimpleNamespace(connection=connection))
        migration = import_module('defense.migrations.0043_reconcile_pending_faculty_review')
        migration.reconcile_pending_review(apps, SimpleNamespace(connection=connection))

    def test_required_material_needs_acceptance_before_endorsement(self):
        self.accept('PAPER')
        with self.assertRaises(ValueError):
            endorse_team(self.team, self.stage.label, self.adviser)
        self.upload('DECK', 'deck.pptx')
        self.assertFalse(required_complete(self.team, self.stage.label))
        with self.assertRaises(ValueError):
            endorse_team(self.team, self.stage.label, self.adviser)
        review_submission(self.team, self.stage.label, 'DECK', 'accepted', '', self.adviser)
        endorse_team(self.team, self.stage.label, self.adviser)
        self.assertTrue(is_stage_ready(self.team, self.stage))

    def test_optional_files_do_not_create_missing_required_files(self):
        self.deck.required = False
        self.deck.save()
        self.accept('PAPER')
        endorse_team(self.team, self.stage.label, self.adviser)
        self.assertTrue(required_complete(self.team, self.stage.label))

    def test_stale_endorsement_cannot_schedule_missing_required_material(self):
        self.accept('PAPER')
        mark_stage_ready(self.team, self.stage, self.adviser)
        self.assertFalse(is_stage_ready(self.team, self.stage))

    def test_plain_pass_never_waives_a_required_file_by_name_or_legacy_option(self):
        hearing = self.hearing(status='done')
        TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            schedule=hearing, panel_score=85, verdict='approved')
        document = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='CUSTOM',
            label='A renamed compliance file', deliverable_type='post', required=True,
            verdict_condition='revisions_only')
        self.assertFalse(post_deliverables_complete(self.team, self.stage.label))
        row = next(d for d in stage_payload(self.team, self.stage.label)['deliverables'] if d['id'] == 'CUSTOM')
        self.assertFalse(row['is_waived'])
        self.assertEqual(row['verdict_condition'], 'all_pass')
        self.accept('CUSTOM')
        self.assertTrue(post_deliverables_complete(self.team, self.stage.label))
        document.label = 'Revision Matrix'
        document.save()
        self.assertTrue(post_deliverables_complete(self.team, self.stage.label))

    def test_old_stage_payload_cannot_restore_timing_or_verdict_exemption(self):
        serializer = DefenseStageWriteSerializer(self.stage, partial=True, data={'deliverables': [
            {'deliverable_id': 'DECK', 'label': 'Slides', 'required': True,
             'deliverable_type': 'pre', 'requirement_timing': 'defense', 'deadline_hours_before': 72},
            {'deliverable_id': 'POST', 'label': 'Compliance', 'required': True,
             'deliverable_type': 'post', 'verdict_condition': 'revisions_only'},
        ]})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        serializer.save()
        for row in self.stage.deliverables.all():
            self.assertEqual((row.requirement_timing, row.deadline_hours_before, row.verdict_condition),
                             ('scheduling', 24, 'all_pass'))

    def test_individual_file_endpoint_also_normalizes_retired_options(self):
        serializer = StageDeliverableSerializer(self.deck, partial=True,
            data={'requirement_timing': 'defense', 'deadline_hours_before': 48, 'verdict_condition': 'revisions_only'})
        self.assertTrue(serializer.is_valid(), serializer.errors)
        serializer.save()
        self.deck.refresh_from_db()
        self.assertEqual((self.deck.requirement_timing, self.deck.verdict_condition), ('scheduling', 'all_pass'))

    def test_pit_configuration_also_uses_one_review_gate(self):
        config = upsert_pit_event_config(semester=self.semester, year_level='3rd Year',
            event_name='Faculty review event', deliverables=[{'deliverable_id': 'DECK', 'label': 'Slides',
                'required': True, 'deliverable_type': 'pre', 'requirement_timing': 'defense',
                'deadline_hours_before': 48}])
        self.assertTrue(pit_endorsement_required(config))
        self.assertEqual(config.deliverables.get().requirement_timing, 'scheduling')

    def test_legacy_pit_required_material_still_requires_endorsement(self):
        config = PitEventGradingConfig.objects.create(semester=self.semester, year_level='3rd Year', event_name='Old event')
        PitEventDeliverable.objects.create(pit_event_config=config, deliverable_id='DECK', label='Slides',
            deliverable_type='pre', required=True, requirement_timing='defense')
        self.assertTrue(pit_endorsement_required(config))

    def test_retired_review_policy_is_always_normalized(self):
        for old in ('replacement', 'panel_requested', 'always'):
            self.assertEqual(validate_concept_config({'enabled': True, 'required_count': 3,
                'review_policy': old})['review_policy'], 'always')

    def test_migration_preserves_existing_schedule_deadline_without_waiving_new_requirements(self):
        hearing = self.hearing()
        self.migrate_policy()
        hearing.refresh_from_db()
        self.deck.refresh_from_db()
        self.assertEqual(hearing.status, 'scheduled')
        self.assertEqual(self.deck.requirement_timing, 'scheduling')
        self.assertEqual(hearing.legacy_deliverable_policy['timings']['DECK']['requirement_timing'], 'defense')
        self.assertEqual(materials_readiness(hearing)['required_total'], 1)
        row = next(d for d in stage_payload(self.team, self.stage.label)['deliverables'] if d['id'] == 'DECK')
        self.assertTrue(row['can_upload'])
        self.assertEqual(row['requirement_timing'], 'defense')

    def test_completed_exemption_is_historical_and_never_reused_for_a_new_attempt(self):
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='POST', label='Historical file',
            deliverable_type='post', required=True, verdict_condition='revisions_only')
        hearing = self.hearing(status='done')
        grade = TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            schedule=hearing, panel_score=85, adviser_score=85, peer_score=85, verdict='approved', status='published')
        self.migrate_policy()
        self.assertTrue(post_deliverables_complete(self.team, self.stage.label))
        grade.status, grade.verdict = 'pending', 'for_redefense'
        grade.save()
        self.assertFalse(post_deliverables_complete(self.team, self.stage.label))

    def test_migration_reopens_only_unscheduled_synthetic_clearance(self):
        self.stage.concept_config = {'enabled': True, 'required_count': 3, 'review_policy': 'panel_requested'}
        self.stage.save()
        hearing = ConceptRound.objects.create(team=self.team, defense_stage=self.stage,
            concepts=[{'key': f'c{i}', 'title': f'Concept {i}'} for i in range(1, 4)],
            review_required=False, endorsed_at=self.now, endorsed_by=self.admin)
        self.team.ready_for_stage = self.stage.label
        self.team.save()
        self.migrate_policy()
        hearing.refresh_from_db()
        self.team.refresh_from_db()
        self.assertTrue(hearing.review_required)
        self.assertIsNone(hearing.endorsed_at)
        self.assertIsNone(self.team.ready_for_stage)
        self.assertFalse(concepts.clearance_valid(self.team, self.stage, hearing))

    def test_completed_import_without_schedule_keeps_only_its_own_exemption(self):
        StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='POST', label='Historical file',
            deliverable_type='post', required=True, verdict_condition='revisions_only')
        grade = TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            panel_score=85, adviser_score=85, peer_score=85, verdict='approved', status='published')
        self.migrate_policy()
        self.assertTrue(post_deliverables_complete(self.team, self.stage.label))
        grade.refresh_from_db()
        grade.attempt_count += 1
        grade.save()
        self.assertFalse(post_deliverables_complete(self.team, self.stage.label))

    def test_unscheduled_legacy_endorsement_is_reset_but_files_are_preserved(self):
        self.accept('PAPER')
        mark_stage_ready(self.team, self.stage, self.adviser)
        self.migrate_policy()
        self.team.refresh_from_db()
        self.assertIsNone(self.team.ready_for_stage)
        self.assertEqual(self.team.deliverable_submissions.get(deliverable_id='PAPER').status, 'accepted')

    def test_phase_two_verdict_upload_restrictions_are_unchanged(self):
        hearing = self.hearing(status='done')
        TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            schedule=hearing, panel_score=60, verdict='failed')
        self.assertFalse(archive_unlocked(self.team, self.stage.label))

    def test_pit_endorsement_record_does_not_lock_missing_new_requirements(self):
        from student_teams.pit_rosters import set_endorsed, endorsed
        self.team.level, self.team.year_level = '1st Year PIT', '1st Year'
        self.team.ready_for_stage = self.stage.label
        self.team.save()
        event = PitEventGradingConfig.objects.create(semester=self.semester, year_level='1st Year',
            event_name=self.stage.label)
        PitEventDeliverable.objects.create(pit_event_config=event, deliverable_id='DECK', label='Slides',
            deliverable_type='pre', required=True, requirement_timing='defense')
        set_endorsed(self.team, event.event_name, True, self.adviser)
        self.assertTrue(endorsed(self.team, event.event_name))
        self.migrate_policy()
        self.team.refresh_from_db()
        self.assertFalse(endorsed(self.team, event.event_name))
        self.upload('DECK', 'deck.pptx')

    def test_nonconcept_redefense_allows_faculty_to_review_required_corrections(self):
        from student_teams.services import mark_stage_result
        self.accept('PAPER')
        mark_stage_ready(self.team, self.stage, self.adviser)
        hearing = self.hearing(status='done')
        grade = TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
            schedule=hearing, panel_score=60, verdict='for_redefense')
        mark_stage_result(grade, self.adviser)
        self.upload('DECK', 'revised.pptx')
        payload = stage_payload(self.team, self.stage.label, evaluator=self.adviser)
        row = next(d for d in payload['pre'] if d['id'] == 'DECK')
        self.assertTrue(row['can_faculty_review'])
        self.assertFalse(required_complete(self.team, self.stage.label))
        review_submission(self.team, self.stage.label, 'DECK', 'accepted', '', self.adviser)
        self.assertTrue(required_complete(self.team, self.stage.label))

    def test_pending_concept_endorsement_reopens_only_when_acceptance_is_missing(self):
        self.stage.concept_config = {'enabled': True, 'required_count': 3, 'review_policy': 'always'}
        self.stage.save()
        self.accept('PAPER')
        hearing = ConceptRound.objects.get(team=self.team, defense_stage=self.stage)
        hearing.endorsed_at, hearing.endorsed_by = self.now, self.adviser
        hearing.save()
        self.migrate_policy()
        hearing.refresh_from_db()
        self.assertIsNone(hearing.endorsed_at)
        self.accept('DECK', 'deck.pptx')
        hearing.endorsed_at, hearing.endorsed_by = self.now, self.adviser
        hearing.save()
        self.migrate_policy()
        hearing.refresh_from_db()
        self.assertIsNotNone(hearing.endorsed_at)
