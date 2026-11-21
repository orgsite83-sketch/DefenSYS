"""In-person decisions preserve real scores and do not depend on minutes."""
import uuid
from datetime import timedelta

from django.core.exceptions import ValidationError
from rest_framework.test import APITestCase

from defense.scheduler.models import SchedulePanelist
from . import test_outcome_rules as fixtures
from .outcome_rules import capture_policy, outcome_payload
from .outcome_models import DefenseOutcome
from .models import TeamGrade
from django.test import override_settings


def legacy_policy(schedule):
    """Exercise saved v1 hearings independently of the policy for new bookings."""
    from copy import deepcopy
    return {**capture_policy(schedule), 'deliberation_version': 1,
            'revision_areas': deepcopy(schedule.defense_stage.revision_areas)}


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class PanelDeliberationTests(APITestCase):
    _rubric = fixtures.ConfiguredOutcomeTests._rubric
    new_hearing = fixtures.ConfiguredOutcomeTests.new_hearing
    submit = fixtures.ConfiguredOutcomeTests.submit

    def setUp(self):
        fixtures.ConfiguredOutcomeTests.setUp(self)
        self.semester.starts_on = '2026-01-01'
        self.semester.ends_on = '2026-12-31'
        self.semester.save(update_fields=['starts_on', 'ends_on'])
        self.stage.revision_areas = [
            {'id': 'system', 'label': 'System', 'allows_demo': True},
            {'id': 'manuscript', 'label': 'Manuscript', 'allows_demo': False}]
        self.stage.save(update_fields=['revision_areas'])
        self.capstone_schedule.assessment_policy = legacy_policy(self.capstone_schedule)
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        self.grade = TeamGrade.objects.select_related('schedule').get(pk=self.grade.pk)

    def decision(self, verdict='approved_with_revisions', **changes):
        self.grade.refresh_from_db()
        data = {'request_id': str(uuid.uuid4()), 'review_token': outcome_payload(self.grade)['review_token'],
            'verdict': verdict, 'revision_entries': [
                {'area_id': 'system', 'severity': 'minor'}, {'area_id': 'manuscript', 'severity': 'major'}],
            'instructions': 'Demonstrate the corrections and revise the manuscript.',
            'reason': '', 're_demo_required': False, 'demo_requirements': []}
        data.update(changes)
        return data

    def post_decision(self, data, actor=None):
        self.client.force_authenticate(actor or self.panelist)
        return self.client.post(f'/api/grading/grades/{self.grade.pk}/panel-decision/', data, format='json')

    def confirm_source(self, demo=False):
        self.submit(8.2)
        from .deliberation import confirm
        data = self.decision(re_demo_required=demo, demo_requirements=[
            {'area_id': 'system', 'text': 'Demonstrate report export.'},
            {'area_id': 'system', 'text': 'Demonstrate access restrictions.'}] if demo else [])
        return confirm(self.grade, actor=self.panelist, data=data)

    def test_complete_passing_assessment_waits_for_chair_without_minutes(self):
        self.submit(8.2)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertFalse(DefenseOutcome.objects.exists())
        from .deliberation import confirm
        result = confirm(self.grade, actor=self.panelist, data=self.decision())
        self.grade.refresh_from_db()
        self.assertEqual(result.verdict, 'approved_with_revisions')
        self.assertEqual(self.grade.panel_score, 82)
        self.assertEqual(self.grade.verdict_by, self.panelist)
        self.assertFalse(hasattr(self.capstone_schedule, 'minutes'))

    def test_panel_can_require_redefense_despite_qualifying_score(self):
        self.submit(8.2)
        from .deliberation import confirm
        data = self.decision('for_redefense', revision_entries=[], reason='Core functionality is not ready.',
                             instructions='Complete the core workflow and defend again.')
        result = confirm(self.grade, actor=self.panelist, data=data)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, 82)
        self.assertEqual(self.grade.verdict, 'for_redefense')
        self.assertEqual(result.decision_source, 'panel_deliberation')
        self.assertNotEqual(self.grade.status, 'published')
        self.assertEqual(float(self.grade.panelist_submissions.get().criterion_scores.get().score), 8.2)

    def test_passing_redefense_requires_human_reason(self):
        self.submit(8)
        from .deliberation import confirm
        with self.assertRaises(ValidationError):
            confirm(self.grade, actor=self.panelist, data=self.decision('for_redefense', revision_entries=[]))
        self.assertFalse(DefenseOutcome.objects.exists())

    def test_zero_is_valid_and_below_cutoff_cannot_be_approved(self):
        self.submit(0)
        from .deliberation import confirm
        self.assertTrue(outcome_payload(self.grade)['panel_complete'])
        with self.assertRaises(ValidationError):
            confirm(self.grade, actor=self.panelist, data=self.decision())
        decision = confirm(self.grade, actor=self.panelist, data=self.decision('for_redefense', revision_entries=[], instructions=''))
        self.assertEqual(decision.decision_source, 'cutoff_required')

    def test_incomplete_roster_cannot_issue_a_verdict(self):
        user = self.panelist.__class__.objects.create_user(username='deliberation-second', role='faculty', is_panelist=True)
        SchedulePanelist.objects.create(schedule=self.capstone_schedule, panelist=user)
        self.submit(9)
        from .deliberation import confirm
        with self.assertRaises(ValidationError):
            confirm(self.grade, actor=self.panelist, data=self.decision())

    def test_admin_and_documenter_cannot_replace_assigned_chair(self):
        self.submit(8)
        from .deliberation import confirm
        for actor in (self.admin, self.adviser, self.student):
            with self.assertRaises(PermissionError):
                confirm(self.grade, actor=actor, data=self.decision())

    def test_confirmation_is_idempotent_and_rejects_changed_replay(self):
        self.submit(8)
        from .deliberation import confirm
        data = self.decision()
        first = confirm(self.grade, actor=self.panelist, data=data)
        self.assertEqual(confirm(self.grade, actor=self.panelist, data=data).pk, first.pk)
        with self.assertRaises(ValidationError):
            confirm(self.grade, actor=self.panelist, data={**data, 'instructions': 'Different decision'})
        self.assertEqual(DefenseOutcome.objects.count(), 1)

    def test_review_token_and_complete_area_validation(self):
        self.submit(8)
        from .deliberation import confirm
        for changes in ({'review_token': 'stale'}, {'revision_entries': []},
                        {'re_demo_required': True}, {'demo_requirements': [{'area_id': 'manuscript', 'text': 'Show changes'}]}):
            with self.assertRaises(ValidationError):
                confirm(self.grade, actor=self.panelist, data=self.decision(**changes))

    def test_demo_is_an_appointment_not_an_assessed_attempt(self):
        source = self.confirm_source(demo=True)
        from defense.redemo.services import book, verify, token, outstanding
        from defense.scheduler.models import DefenseSchedule
        counts = (TeamGrade.objects.count(), DefenseSchedule.objects.count())
        data = {'request_id': str(uuid.uuid4()), 'source_revision': source.revision,
            'scheduled_date': str(self.capstone_schedule.scheduled_date + timedelta(days=21)),
            'start_time': '09:00', 'room': 'Re-demo room', 'chair_id': self.panelist.pk}
        appointment = book(source, actor=self.admin, data=data)
        self.assertEqual(book(source, actor=self.admin, data=data).pk, appointment.pk)
        self.assertEqual((TeamGrade.objects.count(), DefenseSchedule.objects.count()), counts)
        result = verify(appointment, actor=self.panelist, data={'request_id': str(uuid.uuid4()),
            'review_token': token(appointment), 'results': [{'requirement_id': item['id'], 'status': 'satisfied'}
                for item in appointment.requirements], 'remarks': ''})
        self.assertEqual(result.status, 'done')
        self.assertEqual(outstanding(source), [])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, 'approved_with_revisions')
        self.assertEqual(self.grade.panel_score, 82)
        self.assertIsNone(self.grade.revisions_cleared_at)

    def booking(self, source, **changes):
        from defense.redemo.services import book
        data = {'request_id': str(uuid.uuid4()), 'source_revision': source.revision,
            'scheduled_date': str(self.capstone_schedule.scheduled_date + timedelta(days=21)),
            'start_time': '09:00', 'room': 'Re-demo room', 'chair_id': self.panelist.pk}
        data.update(changes)
        return book(source, actor=self.admin, data=data)

    def demo_progress(self):
        from defense.scheduler.models import DefenseSchedule
        from defense.scheduler.progress import schedule_progress
        return schedule_progress(DefenseSchedule.objects.get(pk=self.capstone_schedule.pk), reconcile_status=False)

    def test_team_status_tracks_redemo_and_retains_the_original_verdict(self):
        from defense.redemo.services import verify, token
        from defense.scheduler.serializers import ScheduleTeamSerializer
        self.confirm_source(demo=True)
        progress = self.demo_progress()
        self.assertEqual(progress['display_status'], 're_demo_required')
        self.assertTrue(progress['re_demo']['can_schedule'])
        self.assertEqual(progress['verdict'], 'approved_with_revisions')
        team = ScheduleTeamSerializer(self.capstone_team).data
        self.assertEqual(team['stage_progress'][self.stage.label], 're_demo_required')
        self.assertEqual(team['re_demo_stages'][self.stage.label]['outstanding_count'], 2)
        appointment = self.booking(self.capstone_schedule.official_outcome)
        progress = self.demo_progress()
        self.assertEqual(progress['display_status'], 're_demo_scheduled')
        self.assertEqual(progress['re_demo']['appointment_id'], appointment.pk)
        self.assertFalse(progress['re_demo']['can_schedule'])
        verify(appointment, actor=self.panelist, data={'request_id': str(uuid.uuid4()),
            'review_token': token(appointment), 'results': [{'requirement_id': row['id'], 'status': 'satisfied'}
                for row in appointment.requirements], 'remarks': ''})
        progress = self.demo_progress()
        self.assertEqual(progress['display_status'], 'revisions_pending')
        self.assertEqual(progress['re_demo']['state'], 'verified')
        self.assertFalse(progress['is_completed'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, 82)
        self.assertEqual(self.grade.attempt_count, 1)
        self.assertIsNone(self.grade.revisions_cleared_at)

    def test_redemo_admin_booking_does_not_require_fresh_deliverables_or_endorsement(self):
        from repository.deliverables.models import DeliverableSubmission
        source = self.confirm_source(demo=True)
        DeliverableSubmission.objects.filter(team=self.capstone_team).delete()
        self.capstone_team.ready_for_stage = None
        self.capstone_team.save(update_fields=['ready_for_stage'])
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/re-demos/', {
            'request_id': str(uuid.uuid4()), 'outcome_id': source.pk, 'source_revision': source.revision,
            'scheduled_date': str(self.capstone_schedule.scheduled_date + timedelta(days=21)),
            'start_time': '10:00', 'room': 'Follow-up room', 'chair_id': self.panelist.pk,
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(self.demo_progress()['display_status'], 're_demo_scheduled')

    def test_cancelled_and_unsatisfied_redemos_return_to_required_status(self):
        from defense.redemo.services import operate, verify, token
        source = self.confirm_source(demo=True)
        appointment = self.booking(source)
        appointment = operate(appointment, actor=self.admin, data={
            'action': 'cancel', 'revision': appointment.revision, 'reason': 'Choose another date.'})
        self.assertEqual(self.demo_progress()['display_status'], 're_demo_required')
        appointment = self.booking(source)
        verify(appointment, actor=self.panelist, data={'request_id': str(uuid.uuid4()),
            'review_token': token(appointment), 'results': [
                {'requirement_id': row['id'], 'status': 'satisfied' if index == 0 else 'needs_work'}
                for index, row in enumerate(appointment.requirements)], 'remarks': 'Complete access restrictions.'})
        progress = self.demo_progress()
        self.assertEqual(progress['display_status'], 're_demo_required')
        self.assertEqual(progress['re_demo']['outstanding_count'], 1)
        self.assertTrue(progress['re_demo']['can_schedule'])

    def test_redemo_status_filters_and_unreleased_student_details(self):
        from .student_visibility import student_assessment_payload
        self.confirm_source(demo=True)
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/defense/board/', {'status': 're_demo_required'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([row['id'] for row in response.data['schedules']], [self.capstone_schedule.pk])
        self.assertEqual(response.data['counts']['re_demo_required'], 1)
        self.client.force_authenticate(self.student)
        response = self.client.get('/api/defense/board/')
        row = next(row for row in response.data['schedules'] if row['id'] == self.capstone_schedule.pk)
        self.assertEqual(row['display_status'], 'awaiting_release')
        self.assertIsNone(row['assessment']['re_demo'])
        self.assertEqual(response.data['counts']['re_demo_required'], 0)
        filtered = self.client.get('/api/defense/board/', {'status': 're_demo_required'})
        self.assertEqual(filtered.data['schedules'], [])
        public = student_assessment_payload(self.demo_progress(), self.student, schedule=self.capstone_schedule)
        self.assertEqual(public['display_status'], 'awaiting_release')
        self.assertIsNone(public['re_demo'])

    def test_api_confirmation_and_role_boundary(self):
        self.submit(8.2)
        data = self.decision()
        denied = self.post_decision(data, self.admin)
        self.assertEqual(denied.status_code, 403, denied.data)
        result = self.post_decision(data)
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(result.data['decision']['verdict'], 'approved_with_revisions')
        self.assertEqual(result.data['grade']['workflow']['deliberation']['decision']['id'], result.data['decision']['id'])

    def test_verification_authority_stale_reviews_unchecked_and_needs_work(self):
        from defense.redemo.services import verify, token, outstanding
        source = self.confirm_source(demo=True)
        appointment = self.booking(source)
        data = {'request_id': str(uuid.uuid4()), 'review_token': token(appointment),
            'results': [{'requirement_id': row['id'], 'status': 'needs_work'} for row in appointment.requirements], 'remarks': ''}
        with self.assertRaises(PermissionError):
            verify(appointment, actor=self.admin, data=data)
        for change in ({'review_token': 'stale'}, {'results': []}, {'remarks': ''}, {'panel_score': 0}):
            with self.assertRaises(ValidationError):
                verify(appointment, actor=self.panelist, data={**data, **change})
        result = verify(appointment, actor=self.panelist, data={**data, 'remarks': 'Export still omits the final page.'})
        self.assertEqual(result.status, 'done')
        self.assertEqual(len(outstanding(source)), 2)
        second = self.booking(source, start_time='10:00')
        self.assertNotEqual(second.pk, result.pk)
        self.assertEqual(len(second.requirements), 2)

    def test_booking_duplicates_conflicts_and_operational_controls(self):
        from defense.redemo.services import operate, verify, token
        from defense.scheduler.sessions import validate_plan_conflicts
        source = self.confirm_source(demo=True)
        appointment = self.booking(source)
        with self.assertRaises(ValidationError):
            self.booking(source, start_time='11:00')
        from rest_framework.exceptions import ValidationError as DRFValidationError
        with self.assertRaises((ValidationError, DRFValidationError)):
            validate_plan_conflicts([{'team': self.pit_team, 'scheduled_date': appointment.scheduled_date,
                'start_time': appointment.start_time, 'slot_duration': 30, 'room': appointment.room,
                'panelists': [], 'external_evaluators': []}])
        old_token = token(appointment)
        appointment = operate(appointment, actor=self.admin,
            data={'action': 'pause', 'reason': 'Equipment interruption', 'revision': appointment.revision})
        with self.assertRaises(ValidationError):
            verify(appointment, actor=self.panelist, data={'request_id': str(uuid.uuid4()),
                'review_token': old_token, 'results': [], 'remarks': ''})
        appointment = operate(appointment, actor=self.admin,
            data={'action': 'cancel', 'reason': 'Arrange another appointment', 'revision': appointment.revision})
        self.assertEqual(appointment.status, 'cancelled')
        self.assertNotEqual(self.booking(source).pk, appointment.pk)

    def test_released_snapshot_and_chair_amendment_preserve_versions(self):
        from .corrections import request_correction, review_correction
        from .deliberation import decision_payload
        from .dissemination import snapshot
        source = self.confirm_source(demo=True)
        original = decision_payload(source)
        self.grade.refresh_from_db()
        changes = self.decision()
        changes.pop('request_id')
        changes.update(source_revision=source.revision, instructions='Corrected panel instructions.',
            re_demo_required=True, demo_requirements=[{'area_id': row['area_id'], 'text': row['text']} for row in source.demo_requirements])
        item = request_correction(self.grade.pk, self.panelist, {'reason': 'Correct the recorded instructions',
            'expected_updated_at': self.grade.updated_at.isoformat(), 'changes': {'panel_decision': changes}})
        self.assertEqual(item['status'], 'pending')
        source.refresh_from_db()
        self.assertEqual(source.revision, 1)
        result = review_correction(self.grade.pk, item['id'], self.admin,
            {'action': 'approve', 'reason': 'Verified against panel deliberation', 'acknowledge_published_change': True})
        self.assertEqual(result['status'], 'applied')
        source.refresh_from_db()
        self.grade.refresh_from_db()
        self.assertEqual(source.revision, 2)
        self.assertEqual(source.history[0]['instructions'], original['instructions'])
        self.assertEqual(source.demo_requirements, original['demo_requirements'])
        self.assertEqual(snapshot(self.grade)['panel_decision']['revision'], 2)

    def test_minutes_need_a_reviewed_confirmed_decision_and_freeze_it(self):
        from defense.minutes.models import DefenseMinutes
        from defense.minutes.outcome import require_review, review_token, for_minutes
        from django.db import transaction
        minutes = DefenseMinutes.objects.create(schedule=self.capstone_schedule, team_name=self.capstone_team.name,
            defense_date=self.capstone_schedule.scheduled_date, defense_time=self.capstone_schedule.start_time)
        with transaction.atomic(), self.assertRaises(ValidationError):
            require_review(minutes, review_token(minutes), freeze=True)
        source = self.confirm_source()
        minutes.refresh_from_db()
        self.assertEqual(for_minutes(minutes)['id'], source.pk)
        with transaction.atomic(), self.assertRaises(ValidationError):
            require_review(minutes, 'old-preview', freeze=True)
        with transaction.atomic():
            require_review(minutes, review_token(minutes), freeze=True)
            minutes.save()
        source.instructions = 'Later unreviewed correction'
        source.revision += 1
        source.save()
        minutes.refresh_from_db()
        self.assertNotEqual(for_minutes(minutes)['instructions'], source.instructions)
        with transaction.atomic(), self.assertRaises(ValidationError):
            require_review(minutes, review_token(minutes))

    def test_minutes_pdf_contains_the_official_revision_and_demo_instructions(self):
        from defense.minutes.models import DefenseMinutes
        from defense.minutes.pdf_generator import generate_minutes_pdf
        from .deliberation import decision_payload
        from io import BytesIO
        import pdfplumber
        source = self.confirm_source(demo=True)
        minutes = DefenseMinutes.objects.create(schedule=self.capstone_schedule,
            team_name=self.capstone_team.name, project_title=self.capstone_team.project_title,
            defense_stage_label=self.stage.label, room=self.capstone_schedule.room,
            defense_date=self.capstone_schedule.scheduled_date, defense_time=self.capstone_schedule.start_time,
            documenter_name='Assigned documenter', adviser_name='Assigned adviser',
            outcome_snapshot=decision_payload(source, public=True))
        content = generate_minutes_pdf(minutes, include_signatures=False)
        with pdfplumber.open(BytesIO(content)) as document:
            text = '\n'.join(page.extract_text() or '' for page in document.pages)
            self.assertIn('OFFICIAL PANEL DECISION', text)
            self.assertIn('Approved with revisions', text)
            self.assertIn('Minor revision', text)
            self.assertIn('Major revision', text)
            self.assertIn('Demonstrate report export.', text)
            self.assertIn('Demonstrate access restrictions.', text)
            # Render real pages as well as extracting their canonical text.
            for page in document.pages:
                self.assertGreater(page.to_image(resolution=72).original.width, 500)

    def test_preview_cannot_authorize_a_decision_changed_during_rendering(self):
        from unittest.mock import patch
        from defense.minutes.models import DefenseMinutes
        from defense.minutes.outcome import for_minutes, review_token
        source = self.confirm_source()
        minutes = DefenseMinutes.objects.create(schedule=self.capstone_schedule,
            team_name=self.capstone_team.name, defense_date=self.capstone_schedule.scheduled_date,
            defense_time=self.capstone_schedule.start_time)

        def render(preview, **kwargs):
            source.instructions = 'Changed while the preview is generated.'
            source.revision += 1
            source.save()
            self.assertEqual(for_minutes(preview)['revision'], 1)
            return b'%PDF-1.4 preview fixture'

        self.client.force_authenticate(self.admin)
        with patch('defense.minutes.views.generate_minutes_pdf', side_effect=render):
            response = self.client.get(f'/api/defense/minutes/{self.capstone_schedule.pk}/preview/')
        self.assertEqual(response.status_code, 200)
        minutes.refresh_from_db()
        self.assertNotEqual(response['X-Minutes-Review-Token'], review_token(minutes))

    def test_adoption_is_read_only_and_rejects_recorded_results(self):
        from django.core.management import call_command
        from django.core.management.base import CommandError
        from io import StringIO
        import json
        # An older unresolved captured hearing can be inventoried without writes.
        policy = dict(self.capstone_schedule.assessment_policy)
        policy.pop('deliberation_version')
        policy.pop('revision_areas')
        self.stage.revision_areas = []
        self.stage.save(update_fields=['revision_areas'])
        self.capstone_schedule.assessment_policy = policy
        self.capstone_schedule.documenter = self.panelist.__class__.objects.create_user(
            username='adoption-documenter', role='faculty', is_documenter=True)
        self.capstone_schedule.save(update_fields=['assessment_policy', 'documenter'])
        report = StringIO()
        call_command('panel_deliberation_adoption', schedule_id=[self.capstone_schedule.pk], stdout=report)
        reviewed = json.loads(report.getvalue())
        self.assertTrue(reviewed['read_only'])
        self.assertTrue(reviewed['hearings'][0]['eligible'])
        self.capstone_schedule.refresh_from_db()
        self.assertNotIn('deliberation_version', self.capstone_schedule.assessment_policy)
        with self.assertRaises(CommandError):
            call_command('panel_deliberation_adoption', schedule_id=[self.capstone_schedule.pk], apply=True,
                actor_id=self.admin.pk, reason='Adopt the reviewed hearing', review_token='stale', stdout=StringIO())
        call_command('panel_deliberation_adoption', schedule_id=[self.capstone_schedule.pk], apply=True,
            actor_id=self.admin.pk, reason='Adopt the reviewed hearing', review_token=reviewed['review_token'], stdout=StringIO())
        self.capstone_schedule.refresh_from_db()
        self.assertEqual(self.capstone_schedule.assessment_policy['deliberation_version'], 3)
        self.assertEqual(self.capstone_schedule.assessment_policy['qualifying_score'], policy['qualifying_score'])

    def test_students_receive_only_released_decision_and_redemo(self):
        from . import dissemination
        from .defense_workflow import workflow_payload
        from defense.redemo.services import visible
        from types import SimpleNamespace
        source = self.confirm_source(demo=True)
        self.booking(source)
        self.grade.refresh_from_db()
        before = workflow_payload(self.grade, actor=self.student)
        self.assertIsNone(before['panel_decision'])
        self.assertNotIn('deliberation', before)
        self.assertFalse(visible(self.student).exists())
        request = SimpleNamespace(user=self.admin)
        preview = dissemination.preview(request, {'filters': {'scope': 'capstone', 'entity': 'teams',
            'semester_id': self.semester.pk, 'defense_stage_id': self.stage.pk, 'coverage': 'assessment'},
            'grade_ids': [self.grade.pk]})
        dissemination.confirm(request, {'review_token': preview['review_token'], 'batch_id': str(uuid.uuid4())})
        after = workflow_payload(self.grade, actor=self.student)
        self.assertEqual(after['panel_decision']['revision'], source.revision)
        self.assertNotIn('assessment_snapshot', after['panel_decision'])
        self.assertNotIn('confirmed_by', after['panel_decision'])
        self.assertTrue(visible(self.student).exists())
        from .student_visibility import student_assessment_payload
        public = student_assessment_payload(self.demo_progress(), self.student, schedule=self.capstone_schedule)
        self.assertEqual(public['display_status'], 're_demo_scheduled')
        self.assertEqual(public['re_demo']['source_revision'], source.revision)


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class ConceptDeliberationTests(APITestCase):
    _rubric = fixtures.PerConceptOutcomeTests._rubric
    prepare = fixtures.PerConceptOutcomeTests.prepare
    scores = fixtures.PerConceptOutcomeTests.scores
    submit = fixtures.PerConceptOutcomeTests.submit

    def setUp(self):
        fixtures.PerConceptOutcomeTests.setUp(self)
        self.stage.revision_areas = [{'id': 'concept', 'label': 'Concept', 'allows_demo': False}]
        self.stage.save(update_fields=['revision_areas'])
        self.capstone_schedule.assessment_policy = legacy_policy(self.capstone_schedule)
        self.capstone_schedule.save(update_fields=['assessment_policy'])
        self.grade.refresh_from_db()

    def confirm(self, verdict='approved', **changes):
        from .deliberation import confirm
        data = {'request_id': str(uuid.uuid4()), 'review_token': outcome_payload(self.grade)['review_token'],
            'verdict': verdict, 'revision_entries': [{'area_id': 'concept', 'severity': 'none'}]}
        data.update(changes)
        return confirm(self.grade, actor=self.panelist, data=data)

    def test_one_qualifier_is_selected_with_explicit_panel_confirmation(self):
        self.submit([6, 8, 7])
        self.assertEqual(self.grade.verdict, '')
        source = self.confirm()
        self.assertEqual(source.selected_key, 'c2')
        from repository.deliverables.models import ConceptRound
        hearing = ConceptRound.objects.get(schedule=self.capstone_schedule)
        self.assertEqual([c['key'] for c in hearing.concepts if c['decision'] == 'approved'], ['c2'])

    def test_multiple_qualifiers_require_an_explicit_choice(self):
        self.submit([8, 9, 7])
        with self.assertRaises(ValidationError):
            self.confirm()
        self.assertEqual(self.confirm(selected_key='c1').selected_key, 'c1')

    def test_panel_redefense_keeps_qualifying_concepts_without_awarding_a_choice(self):
        self.submit([8, 9, 7])
        source = self.confirm('for_redefense', revision_entries=[],
            reason='The panel requires another complete presentation.', instructions='Improve the captured proposals.')
        self.assertEqual(source.selected_key, '')
        from repository.deliverables.models import ConceptRound
        hearing = ConceptRound.objects.get(schedule=self.capstone_schedule)
        self.assertFalse(any(c['decision'] in ('approved', 'approved_with_revisions') for c in hearing.concepts))
        self.assertEqual(ConceptRound.objects.filter(team=self.capstone_team).count(), 2)


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class SharedDeliberationTests(APITestCase):
    from repository.section_concepts.test_redefense_direction import SharedRedefenseDirectionTests as fixture
    prepare_hearing = fixture.prepare_hearing
    choose = fixture.choose
    score = fixture.score
    decide = fixture.decide

    def setUp(self):
        self.fixture.setUp(self)
        self.stage.revision_areas = [{'id': 'module', 'label': 'Module', 'allows_demo': True}]
        self.stage.save(update_fields=['revision_areas'])
        self.schedule.assessment_policy = legacy_policy(self.schedule)
        self.schedule.save(update_fields=['assessment_policy'])

    def test_qualifying_module_can_enter_existing_panel_directed_repeat_route(self):
        from .deliberation import confirm
        from repository.section_concepts.redefense_direction import payload
        self.choose()
        self.score(score=8)
        self.assertEqual(self.grade.verdict, '')
        rule = outcome_payload(self.grade)
        self.assertEqual(rule['outcome'], 'approved')
        confirm(self.grade, actor=self.chair, data={'request_id': str(uuid.uuid4()),
            'review_token': rule['review_token'], 'verdict': 'for_redefense',
            'reason': 'Panel requires the complete module workflow.', 'instructions': 'Complete the missing module.',
            'revision_entries': []})
        self.grade.refresh_from_db()
        direction = payload(self.grade, self.chair)
        self.assertTrue(direction['can_decide'], direction)
        self.decide('shared_module', recommendations=self.grade.verdict_remarks)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panelist_submissions.get(concept_key='c2').criterion_scores.get().score, 8)
        self.assertEqual(next(row['score'] for row in outcome_payload(self.grade)['assessments'] if row['key'] == 'c2'), 80)
        self.assertEqual(self.grade.verdict, 'for_redefense')
