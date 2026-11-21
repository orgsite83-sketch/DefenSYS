"""The documenter records an announced decision through reviewed submission."""
import uuid
from copy import deepcopy
from io import BytesIO
from tempfile import TemporaryDirectory

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APITestCase

from grading.grades import test_deliberation as fixtures
from grading.grades.deliberation import source_for, payload
from grading.grades.outcome_rules import capture_policy, outcome_payload
from grading.grades.models import TeamGrade
from .models import DefenseMinutes


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class DocumenterDecisionTests(APITestCase):
    _rubric = fixtures.PanelDeliberationTests._rubric
    new_hearing = fixtures.PanelDeliberationTests.new_hearing
    submit = fixtures.PanelDeliberationTests.submit
    booking = fixtures.PanelDeliberationTests.booking

    def setUp(self):
        fixtures.PanelDeliberationTests.setUp(self)
        self.media = TemporaryDirectory()
        self.addCleanup(self.media.cleanup)
        setting = override_settings(MEDIA_ROOT=self.media.name)
        setting.enable()
        self.addCleanup(setting.disable)
        self.doc = self.panelist.__class__.objects.create_user(username='outcome-documenter', role='faculty', is_documenter=True)
        self.doc.e_signature = SimpleUploadedFile('signature.png', b'test signature')
        self.doc.save(update_fields=['e_signature'])
        self.capstone_schedule.documenter = self.doc
        self.capstone_schedule.assessment_policy = capture_policy(self.capstone_schedule)
        self.capstone_schedule.save(update_fields=['documenter', 'assessment_policy'])
        self.grade = TeamGrade.objects.select_related('schedule').get(pk=self.grade.pk)
        self.url = f'/api/defense/minutes/{self.capstone_schedule.pk}/'
        self.client.force_authenticate(self.doc)
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200, response.data)
        self.minutes_id = response.data['id']

    def draft(self, verdict='approved_with_revisions', demo=True):
        self.grade.refresh_from_db()
        return {'request_id': str(uuid.uuid4()), 'review_token': outcome_payload(self.grade)['review_token'],
            'verdict': verdict, 'selected_key': '', 'reason': '', 'instructions': '',
            'revision_entries': [{'area_id': 'manuscript', 'label': 'Manuscript', 'severity': 'major'},
                {'area_id': 'system', 'label': 'System', 'severity': 'minor'}] if verdict == 'approved_with_revisions' else [],
            're_demo_required': demo if verdict == 'approved_with_revisions' else False,
            'demo_requirements': [{'text': 'Demonstrate the corrected report exports.'}] if demo and verdict == 'approved_with_revisions' else []}

    def save_draft(self, data=None):
        detail = self.client.get(self.url).data
        return self.client.patch(self.url, {'decision_draft': data or self.draft(), 'comments': [
            {'id': row['id'], 'comments': 'The panel recommended manuscript and system corrections.'}
            for row in detail['panelist_comments']]}, format='json')

    def submit_minutes(self, token=None):
        if token is None:
            preview = self.client.get(self.url + 'preview/')
            self.assertEqual(preview.status_code, 200)
            token = preview['X-Minutes-Review-Token']
        return self.client.post(self.url + 'submit/', {'review_token': token}, format='json')

    def test_draft_and_pdf_are_unofficial_and_chair_is_read_only(self):
        self.submit(8.2)
        response = self.save_draft()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['decision_context']['draft_ready'])
        self.assertIsNone(response.data['official_outcome'])
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertIsNone(source_for(self.capstone_schedule))
        view = payload(self.grade, self.panelist)
        self.assertFalse(view['can_confirm'])
        self.assertFalse(view['requires_chair_confirmation'])
        self.assertEqual(view['revision_mode'], 'documenter')
        preview = self.client.get(self.url + 'preview/')
        import pdfplumber
        with pdfplumber.open(BytesIO(preview.content)) as pdf:
            text = '\n'.join(page.extract_text() or '' for page in pdf.pages)
            self.assertIn('Major revision', text)
            self.assertIn('Demonstrate the corrected report exports.', text)
        self.assertIsNone(source_for(self.capstone_schedule))

    def test_submission_records_outcome_and_freezes_the_same_minutes_block(self):
        self.submit(8.2)
        self.assertEqual(self.save_draft().status_code, 200)
        response = self.submit_minutes()
        self.assertEqual(response.status_code, 200, response.data)
        source = source_for(self.capstone_schedule)
        self.assertEqual(source.recorded_by, self.doc)
        self.assertIsNone(source.confirmed_by)
        self.assertEqual(source.assessment_snapshot['announced_by_id'], self.panelist.pk)
        self.assertEqual(response.data['official_outcome']['recording_method'], 'documenter_minutes')
        self.assertEqual(response.data['official_outcome']['demo_requirements'], source.demo_requirements)
        minutes = DefenseMinutes.objects.get(pk=self.minutes_id)
        self.assertEqual(minutes.status, 'submitted')
        self.assertEqual(minutes.documenter_signed_by, self.doc)
        self.assertEqual(minutes.outcome_snapshot['revision_entries'], source.revision_entries)
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, 82)

    def test_only_assigned_documenter_records_the_outcome(self):
        self.submit(8.2)
        for actor in (self.panelist, self.adviser, self.admin, self.student):
            self.client.force_authenticate(actor)
            response = self.client.patch(self.url, {'decision_draft': self.draft()}, format='json')
            self.assertIn(response.status_code, (400, 403))
            response = self.client.post(f'/api/grading/grades/{self.grade.pk}/panel-decision/', self.draft(), format='json')
            self.assertIn(response.status_code, (400, 403, 404))
        self.assertIsNone(source_for(self.capstone_schedule))

    def test_incomplete_draft_can_save_but_cannot_be_submitted(self):
        self.submit(8.2)
        data = self.draft()
        data['demo_requirements'] = [{'text': ''}]
        response = self.save_draft(data)
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['decision_context']['draft_ready'])
        result = self.submit_minutes()
        self.assertEqual(result.status_code, 400)
        self.assertIsNone(source_for(self.capstone_schedule))
        self.assertEqual(DefenseMinutes.objects.get(pk=self.minutes_id).status, 'draft')

    def test_changed_draft_or_assessment_invalidates_review(self):
        self.submit(8.2)
        self.save_draft()
        token = self.client.get(self.url + 'preview/')['X-Minutes-Review-Token']
        changed = self.draft()
        changed['demo_requirements'] = [{'text': 'Demonstrate permission checks.'}]
        self.save_draft(changed)
        self.assertEqual(self.submit_minutes(token).status_code, 400)
        self.assertIsNone(source_for(self.capstone_schedule))
        self.capstone_schedule.revision += 1
        self.capstone_schedule.save(update_fields=['revision'])
        self.assertEqual(self.submit_minutes().status_code, 400)
        self.assertIsNone(source_for(self.capstone_schedule))

    def test_plain_approval_has_no_revision_or_demo_list(self):
        self.submit(8.2)
        self.save_draft(self.draft('approved', demo=False))
        result = self.submit_minutes()
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(result.data['official_outcome']['revision_entries'], [])

    def test_below_cutoff_cannot_be_approved_or_sent_to_redemo(self):
        self.submit(6)
        self.save_draft()
        self.assertEqual(self.submit_minutes().status_code, 400)
        data = self.draft('for_redefense', demo=False)
        data['instructions'] = 'Revise the system and defend again.'
        self.save_draft(data)
        result = self.submit_minutes()
        self.assertEqual(result.status_code, 200, result.data)
        self.assertEqual(result.data['official_outcome']['revision_entries'], [])

    def test_redemo_uses_the_recorded_checklist_without_a_new_grade(self):
        from defense.redemo.services import token, verify, outstanding
        from defense.scheduler.models import DefenseSchedule
        self.submit(8.2)
        self.save_draft()
        self.assertEqual(self.submit_minutes().status_code, 200)
        source = source_for(self.capstone_schedule)
        counts = (TeamGrade.objects.count(), DefenseSchedule.objects.count())
        appointment = self.booking(source)
        self.assertEqual(appointment.requirements, source.demo_requirements)
        verify(appointment, actor=self.panelist, data={'request_id': str(uuid.uuid4()),
            'review_token': token(appointment), 'results': [
                {'requirement_id': row['id'], 'status': 'satisfied'} for row in appointment.requirements], 'remarks': ''})
        self.assertEqual(outstanding(source), [])
        self.assertEqual(counts, (TeamGrade.objects.count(), DefenseSchedule.objects.count()))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.panel_score, 82)
        self.assertIsNone(self.grade.revisions_cleared_at)

    def test_failed_canonical_write_rolls_back_the_outcome_and_signature(self):
        from unittest.mock import patch
        self.submit(8.2)
        self.save_draft()
        token = self.client.get(self.url + 'preview/')['X-Minutes-Review-Token']
        from django.core.exceptions import ValidationError
        with patch('grading.grades.deliberation.DefenseOutcome.objects.create', side_effect=ValidationError('Cannot record decision.')):
            response = self.submit_minutes(token)
        self.assertEqual(response.status_code, 400)
        self.assertIsNone(source_for(self.capstone_schedule))
        self.grade.refresh_from_db()
        self.assertEqual(self.grade.verdict, '')
        self.assertIsNone(DefenseMinutes.objects.get(pk=self.minutes_id).documenter_signed_at)

    def test_documenter_correction_uses_admin_review_and_retains_signed_snapshot(self):
        self.submit(8.2)
        self.save_draft()
        self.assertEqual(self.submit_minutes().status_code, 200)
        source = source_for(self.capstone_schedule)
        old = deepcopy(DefenseMinutes.objects.get(pk=self.minutes_id).outcome_snapshot)
        detail = self.client.get(self.url).data
        changes = self.draft()
        changes.pop('request_id')
        changes['source_revision'] = source.revision
        changes['revision_entries'][0]['severity'] = 'minor'
        body = {'reason': 'Correct the announced manuscript level.',
            'expected_updated_at': detail['decision_context']['grade_updated_at'],
            'changes': {'panel_decision': changes}}
        response = self.client.post(self.url + 'decision-correction/', body, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'pending')
        source.refresh_from_db()
        self.assertEqual(source.revision, 1)
        from grading.grades.corrections import review_correction
        review_correction(self.grade.pk, response.data['id'], self.admin,
            {'action': 'approve', 'reason': 'Checked against the panel announcement.', 'acknowledge_published_change': True})
        source.refresh_from_db()
        self.assertEqual(source.revision, 2)
        self.assertEqual(source.recorded_by, self.doc)
        self.assertIsNone(source.confirmed_by)
        self.assertEqual(source.demo_requirements, old['demo_requirements'])
        self.assertEqual(DefenseMinutes.objects.get(pk=self.minutes_id).outcome_snapshot, old)

    def test_recorded_outcome_stays_private_until_existing_admin_release(self):
        from grading.grades.defense_workflow import workflow_payload
        self.submit(8.2)
        self.save_draft()
        self.assertEqual(self.submit_minutes().status_code, 200)
        self.grade.refresh_from_db()
        self.assertIsNone(workflow_payload(self.grade, self.student)['panel_decision'])
        self.client.force_authenticate(self.panelist)
        self.assertEqual(self.client.post(self.url + 'decision-correction/', {}, format='json').status_code, 403)

    def test_fresh_redefense_still_collects_new_scores_and_uses_documenter_recording(self):
        from datetime import timedelta
        from defense.scheduler.models import DefenseSchedule, SchedulePanelist
        from grading.grades.services import GradeContextService, submit_panelist_grade
        self.submit(6)
        self.save_draft(self.draft('for_redefense', demo=False))
        self.assertEqual(self.submit_minutes().status_code, 200)
        source = source_for(self.capstone_schedule)
        repeat = DefenseSchedule.objects.create(team=self.capstone_team, semester=self.semester,
            defense_stage=self.stage, rubric=self.panel_rubric, documenter=self.doc,
            scheduled_date=self.capstone_schedule.scheduled_date + timedelta(days=7), start_time='09:00', room='Next attempt')
        SchedulePanelist.objects.create(schedule=repeat, panelist=self.panelist, is_chair=True)
        grade, _, _ = GradeContextService.get_or_create_for_schedule(repeat)
        self.assertIsNone(grade.panel_score)
        self.assertEqual(repeat.assessment_policy['deliberation_version'], 3)
        submit_panelist_grade(repeat, grade, [{'criterion_id': self.panel_rubric.criteria.first().pk, 'score': 9}], panelist=self.panelist)
        grade.refresh_from_db()
        self.assertEqual(grade.verdict, '')
        self.assertEqual(payload(grade, self.panelist)['revision_mode'], 'documenter')
        source.refresh_from_db()
        self.assertEqual(source.verdict, 'for_redefense')


class DocumenterConceptDecisionTests(APITestCase):
    _rubric = fixtures.ConceptDeliberationTests._rubric
    prepare = fixtures.ConceptDeliberationTests.prepare
    scores = fixtures.ConceptDeliberationTests.scores
    submit = fixtures.ConceptDeliberationTests.submit
    draft = DocumenterDecisionTests.draft
    save_draft = DocumenterDecisionTests.save_draft
    submit_minutes = DocumenterDecisionTests.submit_minutes

    def setUp(self):
        fixtures.ConceptDeliberationTests.setUp(self)
        self.doc = self.panelist.__class__.objects.create_user(username='concept-recorder', role='faculty',
            is_documenter=True, e_signature='fixture-signature.png')
        self.capstone_schedule.documenter = self.doc
        self.capstone_schedule.assessment_policy = capture_policy(self.capstone_schedule)
        self.capstone_schedule.save(update_fields=['documenter', 'assessment_policy'])
        self.grade.refresh_from_db()
        self.url = f'/api/defense/minutes/{self.capstone_schedule.pk}/'
        self.client.force_authenticate(self.doc)
        result = self.client.get(self.url)
        self.assertEqual(result.status_code, 200, result.data)
        self.minutes_id = result.data['id']

    def test_documenter_records_the_announced_qualifying_concept(self):
        self.submit([8, 9, 7])
        data = self.draft('approved', demo=False)
        data['selected_key'] = 'c1'
        self.assertEqual(self.save_draft(data).status_code, 200)
        response = self.submit_minutes()
        self.assertEqual(response.status_code, 200, response.data)
        source = source_for(self.capstone_schedule)
        self.assertEqual(source.selected_key, 'c1')
        self.assertEqual(source.recorded_by, self.doc)


class SharedDocumenterDecisionTests(APITestCase):
    fixture = fixtures.SharedDeliberationTests.fixture
    prepare_hearing = fixtures.SharedDeliberationTests.prepare_hearing
    choose = fixtures.SharedDeliberationTests.choose
    score = fixtures.SharedDeliberationTests.score
    draft = DocumenterDecisionTests.draft
    save_draft = DocumenterDecisionTests.save_draft
    submit_minutes = DocumenterDecisionTests.submit_minutes

    def setUp(self):
        fixtures.SharedDeliberationTests.setUp(self)
        self.capstone_schedule = self.schedule
        self.panelist = self.chair
        self.doc = self.chair.__class__.objects.create_user(username='shared-recorder', role='faculty',
            is_documenter=True, e_signature='fixture-signature.png')
        self.schedule.documenter = self.doc
        self.schedule.assessment_policy = capture_policy(self.schedule)
        self.schedule.save(update_fields=['documenter', 'assessment_policy'])
        self.grade.refresh_from_db()
        self.url = f'/api/defense/minutes/{self.schedule.pk}/'
        self.client.force_authenticate(self.doc)
        result = self.client.get(self.url)
        self.assertEqual(result.status_code, 200, result.data)
        self.minutes_id = result.data['id']

    def test_shared_module_approval_keeps_the_panels_shared_selection(self):
        self.choose()
        self.score(score=8)
        self.save_draft(self.draft('approved', demo=False))
        result = self.submit_minutes()
        self.assertEqual(result.status_code, 200, result.data)
        source = source_for(self.schedule)
        self.assertEqual(source.selected_key, 'c2')
        self.assertEqual(source.recorded_by, self.doc)
