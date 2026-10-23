"""PIT concept hearings retain event/year ownership through repeat attempts."""
from datetime import timedelta
from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from defense.scheduler import test_year_scope as fixtures
from defense.scheduler.models import DefenseSchedule, PitEventGradingConfig
from defense.scheduler.progress import schedule_progress
from grading.grades.models import TeamGrade
from grading.grades.services import GradeContextService, submit_panelist_grade
from . import concepts
from .models import ConceptRound
from .services import upsert_submission, review_submission, endorse_team, stage_payload, unendorse_team


class PitConceptTests(APITestCase):
    rubric = fixtures.PitYearIsolationTests.rubric
    data = fixtures.PitYearIsolationTests.data
    slot = fixtures.PitYearIsolationTests.slot

    def setUp(self):
        fixtures.PitYearIsolationTests.setUp(self)
        self.team = self.teams[0]
        root = Path(__file__).resolve().parents[4] / '.tmp'
        root.mkdir(exist_ok=True)
        media = TemporaryDirectory(dir=root)
        self.addCleanup(media.cleanup)
        settings = override_settings(MEDIA_ROOT=media.name)
        settings.enable()
        self.addCleanup(settings.disable)
        extraction = patch('repository.deliverables.pdf_processor.extract_pdf_from_file_object',
                           return_value={'text': 'Concept fixture'})
        extraction.start()
        self.addCleanup(extraction.stop)
        self.configure()

    def configure(self, **changes):
        deliverables = changes.pop('deliverables', None) or [{
            'deliverable_id': 'CONCEPTS', 'label': 'Concept papers', 'required': True,
            'deliverable_type': 'pre', 'is_defense_material': True, 'file_policy': {'mode': 'concepts'},
        }]
        config = {'enabled': True, 'required_count': 3, 'review_policy': 'replacement',
                  'score_carryover': 'reassess', **changes}
        self.client.force_authenticate(self.first)
        response = self.client.post(fixtures.CONFIG, self.data(concept_config=config, deliverables=deliverables), format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.event.refresh_from_db()

    def titles(self, actor=None, team=None, label=None):
        self.client.force_authenticate(actor or self.team.leader)
        return self.client.post('/api/repository/deliverables/concepts/', {
            'team_id': (team or self.team).pk, 'stage_label': label or self.event.event_name,
            'action': 'save_titles', 'response_mode': 'team', 'scope': 'pit',
            'concepts': [{'key': f'c{i}', 'title': f'PIT proposal {i}'}
                         for i in range(1, self.event.concept_config['required_count'] + 1)],
        }, format='json')

    def prepare(self, *, accepted=True):
        response = self.titles()
        self.assertEqual(response.status_code, 200, response.data)
        for i in range(1, self.event.concept_config['required_count'] + 1):
            sub = upsert_submission(self.team, self.event.event_name, 'CONCEPTS', f'concept-{i}.pdf',
                '10 B', self.team.leader, file=SimpleUploadedFile(f'concept-{i}.pdf', b'concept fixture'),
                slot_key=f'c{i}:paper')
            if accepted:
                review_submission(self.team, self.event.event_name, 'CONCEPTS', 'accepted', '', self.first,
                    file_id=sub.files.get(slot_key=f'c{i}:paper', is_current=True).pk)
        if accepted:
            endorse_team(self.team, self.event.event_name, self.first)

    def schedule(self, day=0):
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/defense/schedules/', self.slot(self.team,
            scheduled_date=str(timezone.localdate() + timedelta(days=day)),
            chair_panelist_id=self.panelist.pk), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        return DefenseSchedule.objects.filter(team=self.team).latest('pk')

    def verdict(self, schedule, *, approved=False, actor=None):
        grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
        if not schedule.panelist_grade_submissions.filter(panelist=self.panelist).exists():
            submit_panelist_grade(schedule, grade, [{'criterion_id': self.panel.criteria.first().pk, 'score': 8}],
                                  panelist=self.panelist)
        self.client.force_authenticate(actor or self.first)
        from .pit_decisions import review_token
        return self.client.post('/api/repository/deliverables/concepts/', {
            'team_id': self.team.pk, 'stage_label': self.event.event_name, 'action': 'pit_decision',
            'review_token': review_token(ConceptRound.objects.get(schedule=schedule)),
            'reason': 'Panel hearing feedback recorded by the PIT Lead.',
            'concepts': [{'key': f'c{i}', 'decision': 'approved' if approved and i == 2 else 'rejected',
                                  'remarks': 'Recorded panel feedback.', 'next_action': 'omit' if approved else 'replace'} for i in range(1, 4)],
        }, format='json')

    def test_config_and_documents_are_persisted_in_assigned_event_only(self):
        self.assertTrue(self.event.concept_config['enabled'])
        self.assertEqual(self.event.deliverables.get(deliverable_id='CONCEPTS').file_policy, {'mode': 'concepts'})
        self.assertEqual(self.event.deliverables.filter(file_policy__purpose='approved_concept', required=True).count(), 1)
        self.assertEqual(concepts.stage_for(self.team, self.event.event_name), self.event)
        self.assertIsNone(concepts.stage_for(self.teams[1], self.event.event_name))
        for actor in (self.second, self.unassigned):
            self.client.force_authenticate(actor)
            self.assertEqual(self.client.get(fixtures.CONFIG, {'event_name': self.event.event_name}).status_code, 403)
            response = self.client.post(fixtures.CONFIG, self.data(concept_config={'enabled': False}), format='json')
            self.assertIn(response.status_code, (400, 403))
        self.event.refresh_from_db()
        self.assertTrue(self.event.concept_config['enabled'])

    def test_other_year_leads_and_other_team_students_cannot_read_or_write_concepts(self):
        for actor in (self.second, self.unassigned, self.teams[1].leader):
            response = self.titles(actor=actor)
            self.assertIn(response.status_code, (403, 404), response.data)
        self.assertFalse(ConceptRound.objects.exists())
        self.assertEqual(self.titles(actor=self.admin, team=self.teams[1]).status_code, 400)
        with self.assertRaises(ValidationError):
            concepts.get_round(self.teams[1], self.event)
        self.assertFalse(ConceptRound.objects.exists())

    def test_config_requires_scheduling_timed_concept_papers_and_valid_limits(self):
        self.client.force_authenticate(self.first)
        for config in ({'enabled': True, 'required_count': 11}, {'enabled': True, 'required_count': True},
                       {'enabled': 'true'}):
            response = self.client.post(fixtures.CONFIG, self.data(concept_config=config, deliverables=[]), format='json')
            self.assertEqual(response.status_code, 400, response.data)
        self.event.refresh_from_db()
        self.assertEqual(self.event.concept_config['required_count'], 3)

    def test_four_concepts_use_four_reviewed_document_slots(self):
        self.configure(required_count=4)
        self.prepare()
        payload = stage_payload(self.team, self.event.event_name)
        self.assertEqual(len(payload['pre'][0]['document_slots']), 4)
        self.assertEqual(payload['concept_workflow']['status'], 'ready_to_schedule')
        self.assertIn('PIT Lead', payload['concept_workflow']['next_step'])
        self.assertTrue(concepts.pit_ready(self.team, self.event))

    def test_started_concept_rules_and_document_structure_are_locked(self):
        self.assertEqual(self.titles().status_code, 200)
        self.client.force_authenticate(self.first)
        response = self.client.post(fixtures.CONFIG,
            self.data(concept_config={'enabled': True, 'required_count': 1}), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.event.refresh_from_db()
        self.assertEqual(self.event.concept_config['required_count'], 3)

    def test_all_rejected_requires_new_clearance_then_allows_second_attempt(self):
        self.prepare()
        first = self.schedule()
        response = self.verdict(first)
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assertEqual(self.team.status, self.team.STATUS_PENDING)
        self.assertFalse(concepts.pit_ready(self.team, self.event))
        prior = ConceptRound.objects.get(schedule=first)
        self.assertEqual(len(prior.documents_snapshot[0]['files']), 3)
        self.assertEqual(schedule_progress(DefenseSchedule.objects.get(pk=first.pk))['display_status'], 'redefense_required')
        self.prepare(accepted=False)
        self.assertFalse(concepts.pit_ready(self.team, self.event))
        with self.assertRaises(ValueError):
            endorse_team(self.team, self.event.event_name, self.first)
        for row in self.team.deliverable_submissions.get().files.filter(is_current=True):
            review_submission(self.team, self.event.event_name, 'CONCEPTS', 'accepted', '', self.first, file_id=row.pk)
        endorse_team(self.team, self.event.event_name, self.first)
        second = self.schedule(day=1)
        self.assertNotEqual(first.pk, second.pk)
        self.assertEqual(ConceptRound.objects.get(schedule=second).number, 2)
        grade = TeamGrade.objects.get(team=self.team)
        self.assertEqual(grade.attempt_count, 2)
        self.assertIsNone(grade.panel_score)
        self.assertEqual(len(ConceptRound.objects.get(schedule=first).documents_snapshot[0]['files']), 3)

    def test_peer_retention_policy_preserves_scores_on_repeat_hearing(self):
        self.configure(score_carryover='retain')
        self.prepare()
        first = self.schedule()
        self.assertEqual(self.verdict(first).status_code, 200)
        grade = TeamGrade.objects.get(team=self.team)
        grade.peer_score = Decimal('86')
        grade.save()
        self.prepare()
        self.schedule(day=1)
        grade.refresh_from_db()
        self.assertEqual(grade.peer_score, Decimal('86'))

    def test_acceptance_selects_official_title_and_prevents_another_hearing(self):
        self.prepare()
        schedule = self.schedule()
        response = self.verdict(schedule, approved=True)
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assertEqual(self.team.project_title, 'PIT proposal 2')
        self.assertFalse(concepts.pit_ready(self.team, self.event))
        self.assertEqual(self.titles().status_code, 400)

    def test_pit_lead_can_select_concepts_but_cannot_override_clearance(self):
        self.prepare()
        schedule = self.schedule()
        response = self.verdict(schedule, actor=self.second)
        self.assertIn(response.status_code, (403, 404))
        self.assertEqual(self.verdict(schedule, actor=self.panelist).status_code, 200)
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/repository/deliverables/concepts/', {
            'team_id': self.team.pk, 'stage_label': self.event.event_name,
            'action': 'override_clearance', 'reason': 'Lead is not an administrator.',
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)

    def test_cancelling_endorsement_and_changing_titles_revoke_clearance(self):
        self.prepare()
        self.assertTrue(concepts.pit_ready(self.team, self.event))
        unendorse_team(self.team, self.event.event_name)
        self.assertFalse(concepts.pit_ready(self.team, self.event))
        endorse_team(self.team, self.event.event_name, self.first)
        concepts.save_titles(self.team, self.event, [
            {'key': f'c{i}', 'title': f'Changed idea {i}'} for i in range(1, 4)])
        self.assertFalse(concepts.pit_ready(self.team, self.event))

    def test_review_endorsement_rejects_a_token_for_earlier_concept_titles(self):
        from .endorsement import endorsement_review, review_and_endorse, StaleEndorsementReview
        self.prepare(accepted=False)
        token = endorsement_review(self.team, self.event.event_name)['review_token']
        self.assertTrue(token)
        concepts.save_titles(self.team, self.event, [
            {'key': f'c{i}', 'title': f'Changed idea {i}'} for i in range(1, 4)])
        with self.assertRaises(StaleEndorsementReview):
            review_and_endorse(self.team, self.event.event_name, actor=self.first, review_token=token)
        self.assertFalse(concepts.clearance_valid(self.team, self.event))

    def test_numeric_result_stays_independent_but_completion_requires_concept_selection(self):
        self.prepare()
        schedule = self.schedule()
        grade = TeamGrade.objects.get(team=self.team)
        submit_panelist_grade(schedule, grade, [{'criterion_id': self.panel.criteria.first().pk, 'score': 8}],
                              panelist=self.panelist)
        grade.refresh_from_db()
        grade.peer_score = Decimal('86')
        grade.save()
        self.assertEqual(grade.result, 'passed')
        with self.assertRaises(ValidationError):
            GradeContextService.publish(grade, user=self.first)
        with self.assertRaises(ValidationError):
            GradeContextService.finalize_for_archive(grade, user=self.first)
        response = self.verdict(schedule)
        self.assertEqual(response.status_code, 200, response.data)
        grade.refresh_from_db()
        with self.assertRaises(ValidationError):
            GradeContextService.publish(grade, user=self.first)
        self.assertNotEqual(grade.status, TeamGrade.STATUS_PUBLISHED)

    def test_bulk_plan_requires_current_clearance_and_preserves_year_isolation(self):
        self.prepare()
        first = self.schedule()
        self.assertEqual(self.verdict(first).status_code, 200)
        self.client.force_authenticate(self.first)
        plan = self.slot(self.team, scheduled_date=str(timezone.localdate() + timedelta(days=1)))
        response = self.client.post('/api/defense/schedules/confirm-plan/', {
            **plan, 'slots': [{'team_id': self.team.pk}],
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.prepare()
        self.client.force_authenticate(self.first)
        response = self.client.post('/api/defense/schedules/confirm-plan/', {
            **plan, 'slots': [{'team_id': self.team.pk}],
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(ConceptRound.objects.filter(team=self.team, schedule__isnull=False).count(), 2)
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/schedules/confirm-plan/', {
            **plan, 'slots': [{'team_id': self.teams[1].pk}],
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(DefenseSchedule.objects.filter(team=self.teams[1]).exists())

    def test_retired_policy_cannot_skip_review_of_replacement_papers(self):
        self.configure(review_policy='panel_requested')
        self.prepare()
        first = self.schedule()
        self.assertEqual(self.verdict(first).status_code, 200)
        self.prepare(accepted=False)
        self.assertFalse(concepts.pit_ready(self.team, self.event))
        self.prepare(accepted=True)
        self.assertTrue(concepts.pit_ready(self.team, self.event))
        self.assertEqual(self.schedule(day=1).concept_round.number, 2)

    def test_foreign_year_cannot_upload_review_or_endorse_concept_files(self):
        self.prepare(accepted=False)
        sub = self.team.deliverable_submissions.get()
        file_id = sub.files.first().pk
        for actor in (self.second, self.unassigned, self.teams[1].leader):
            self.client.force_authenticate(actor)
            base = {'team_id': self.team.pk, 'stage_label': self.event.event_name, 'deliverable_id': 'CONCEPTS'}
            response = self.client.post('/api/repository/deliverables/upload/', {
                **base, 'slot_key': 'c1:paper', 'file_name': 'wrong.pdf',
                'file': SimpleUploadedFile('wrong.pdf', b'wrong year'),
            }, format='multipart')
            self.assertIn(response.status_code, (403, 404), response.data)
            response = self.client.post('/api/repository/deliverables/review/', {
                **base, 'file_id': file_id, 'status': 'accepted'}, format='json')
            self.assertIn(response.status_code, (403, 404), response.data)
            response = self.client.post('/api/repository/deliverables/endorse/', base, format='json')
            self.assertIn(response.status_code, (403, 404), response.data)
        self.assertFalse(concepts.clearance_valid(self.team, self.event))

    def test_assigned_section_instructor_can_review_and_endorse_own_team(self):
        from user_management.models import SectionInstructorAssignment
        from .endorsement import endorsement_review, review_and_endorse
        instructor = self.first.__class__.objects.create_user(username='concept-instructor', role='faculty')
        self.team.section = 'Concept Section A'
        self.team.save(update_fields=['section', 'updated_at'])
        SectionInstructorAssignment.objects.create(faculty=instructor, semester=self.semester,
            year_level='1st Year', section=self.team.section)
        self.prepare(accepted=False)
        review = endorsement_review(self.team, self.event.event_name)
        review_and_endorse(self.team, self.event.event_name, actor=instructor, review_token=review['review_token'])
        self.assertTrue(concepts.pit_ready(self.team, self.event))
        self.assertEqual(ConceptRound.objects.get(team=self.team).endorsed_by_id, instructor.pk)
