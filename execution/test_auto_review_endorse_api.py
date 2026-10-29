"""Run faculty automation against existing API views in the isolated test DB."""
from contextlib import redirect_stdout
from io import StringIO
from urllib.parse import urlencode, urlsplit
from unittest.mock import patch

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from authentication_access_control.models import SystemAuditLog
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import TeamStageProgress
from user_management.models import SectionInstructorAssignment

from execution import auto_review_endorse as reviews
from execution import test_upload_deliverables_api as upload_fixtures


class _FacultySession(upload_fixtures._ApiSession):
    def __init__(self, actor=None):
        super().__init__(actor)
        self.calls = []

    def request(self, method, url, *, params=None, json=None, **kwargs):
        self.calls.append((method, urlsplit(url).path, dict(params or {})))
        if method == 'POST' and json is not None:
            path = urlsplit(url).path
            if params:
                path += '?' + urlencode(params)
            authorization = {'HTTP_AUTHORIZATION': self.headers['Authorization']} if self.headers.get('Authorization') else {}
            self.posts += 1
            return self.client.post(path, json, format='json', **authorization)
        return super().request(method, url, params=params, **kwargs)


class ReviewEndorseAutomationApiTests(APITestCase):
    write = upload_fixtures.UploadAutomationApiTests.write

    def setUp(self):
        upload_fixtures.UploadAutomationApiTests.setUp(self)
        self.instructor = get_user_model().objects.create_user(username='review-instructor', role='faculty',
            is_pit_lead=True, pit_lead_year='2nd Year')
        self.pit.section = 'PIT Section A'
        self.pit.save(update_fields=['section'])
        self.assignment = SectionInstructorAssignment.objects.create(faculty=self.instructor,
            semester=self.semester, year_level='1st Year', section=self.pit.section)
        self.sessions = []

    def session(self):
        session = _FacultySession()
        self.sessions.append(session)
        return session

    def upload(self, team, deliverable, slot='primary'):
        scope = 'pit' if team.is_pit else 'capstone'
        stage = self.event.event_name if team.is_pit else self.stage.label
        relative = f'{team.pk}-{deliverable}-{reviews.common.component(slot)}.pdf'
        self.write(relative)
        client = reviews.common.ApiClient('http://testserver', session=_FacultySession(self.student))
        client.upload({'scope': scope, 'stage': stage},
            {'team_id': team.pk, 'deliverable_id': deliverable, 'slot_key': slot}, self.files / relative)

    def run_script(self, *extra, scope='pit', dry_run=False):
        arguments = ['--all-teams', '--base-url', 'http://testserver', '--scope', scope]
        arguments += ['--year', '1'] if scope == 'pit' else ['--stage', self.stage.label]
        if dry_run:
            arguments.append('--dry-run')
        with patch.object(reviews.common.requests, 'Session', side_effect=self.session), redirect_stdout(StringIO()):
            return reviews.main(arguments + list(extra))

    def prepare_pit(self):
        for slot in ['paper', 'notes']:
            self.upload(self.pit, 'DOCS', slot)

    def test_pit_preview_and_live_rerun_use_actual_instructor_without_credential_changes(self):
        self.prepare_pit()
        from rest_framework_simplejwt.token_blacklist.models import OutstandingToken
        credentials = dict(get_user_model().objects.values_list('pk', 'password'))
        token_count = OutstandingToken.objects.count()
        self.assertEqual(self.run_script(dry_run=True), 0)
        self.assertFalse(DeliverableSubmission.objects.exclude(status='pending').exists())
        self.assertFalse(SystemAuditLog.objects.filter(action='repository.review_and_endorse').exists())
        self.pit.refresh_from_db()
        self.assertFalse(self.pit.ready_for_stage)
        self.assertEqual(self.run_script(), 0)
        self.assertEqual(self.run_script(), 0)
        submission = DeliverableSubmission.objects.get(team=self.pit)
        self.assertEqual(submission.status, 'accepted')
        self.assertEqual(submission.reviewed_by_id, self.instructor.pk)
        self.assertIsNotNone(submission.reviewed_at)
        self.assertFalse(submission.files.exclude(status='accepted').exists())
        self.pit.refresh_from_db()
        self.assertEqual(self.pit.ready_for_stage, self.event.event_name)
        self.assertEqual(SystemAuditLog.objects.filter(action='repository.review_and_endorse').count(), 1)
        self.assertEqual(sum(session.posts for session in self.sessions), 1)
        self.assertEqual(dict(get_user_model().objects.values_list('pk', 'password')), credentials)
        self.assertEqual(OutstandingToken.objects.count(), token_count)
        for session in self.sessions:
            self.assertTrue(session.headers['Authorization'].startswith('Bearer '))
            self.assertTrue(all(params['workspace'] == 'instructor' for _, _, params in session.calls))

    def test_capstone_uses_assigned_adviser_workspace_and_progress_actor(self):
        self.upload(self.capstone, 'PAPER')
        self.assertEqual(self.run_script(scope='capstone', dry_run=True), 0)
        self.assertEqual(self.run_script(scope='capstone'), 0)
        self.assertEqual(self.run_script(scope='capstone'), 0)
        saved = DeliverableSubmission.objects.get(team=self.capstone)
        self.assertEqual(saved.reviewed_by_id, self.adviser.pk)
        self.assertEqual(saved.status, 'accepted')
        progress = TeamStageProgress.objects.get(team=self.capstone, defense_stage=self.stage)
        self.assertEqual(progress.updated_by_id, self.adviser.pk)
        self.assertEqual(sum(session.posts for session in self.sessions), 1)
        self.assertTrue(all(params['workspace'] == 'adviser' for session in self.sessions for _, _, params in session.calls))

    def test_missing_and_rejected_documents_do_not_get_accepted_or_endorsed(self):
        self.upload(self.pit, 'DOCS', 'paper')
        self.assertEqual(self.run_script(), 2)
        saved = DeliverableSubmission.objects.get(team=self.pit)
        self.assertEqual(saved.status, 'pending')
        self.upload(self.pit, 'DOCS', 'notes')
        saved.refresh_from_db()
        saved.status = 'rejected'
        saved.feedback = 'Revise the demo scope.'
        saved.save(update_fields=['status', 'feedback'])
        self.assertEqual(self.run_script(), 2)
        saved.refresh_from_db()
        self.assertEqual(saved.status, 'rejected')
        self.assertEqual(saved.feedback, 'Revise the demo scope.')
        self.assertEqual(sum(session.posts for session in self.sessions), 0)

    def test_missing_instructor_assignment_does_not_fall_back_to_pit_lead_or_admin(self):
        self.prepare_pit()
        self.assignment.delete()
        self.adviser.is_pit_lead = True
        self.adviser.pit_lead_year = '1st Year'
        self.adviser.save(update_fields=['is_pit_lead', 'pit_lead_year'])
        self.assertEqual(self.run_script(), 2)
        self.assertEqual(self.sessions, [])
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit).status, 'pending')

    def test_second_active_instructor_is_rejected_before_review_automation(self):
        self.prepare_pit()
        other = get_user_model().objects.create_user(username='second-review-instructor', role='faculty')
        from django.core.exceptions import ValidationError
        with self.assertRaises(ValidationError):
            SectionInstructorAssignment.objects.create(faculty=other, semester=self.semester,
                year_level='1st Year', section=self.pit.section)
        self.assertEqual(self.run_script('--reviewers', self.instructor.username), 0)
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit).reviewed_by_id, self.instructor.pk)

    def test_reassigned_reviewer_is_detected_before_posting(self):
        self.prepare_pit()
        semester, records = reviews.discover_reviewers(scope='pit', stage=self.event.event_name, year='1st Year')
        context = {'scope': 'pit', 'stage': self.event.event_name, 'year': '1st Year',
                   'semester_id': semester, 'reviewers': None}
        with patch.object(reviews.common.requests, 'Session', side_effect=self.session):
            batch = reviews.FacultyBatch('http://testserver')
            self.addCleanup(batch.close)
            current = batch.team(context, records[0])
            token = current['selected_stage']['endorsement_review']['review_token']
            self.assignment.is_active = False
            self.assignment.save(update_fields=['is_active'])
            with self.assertRaises(reviews.common.UploadError):
                batch.endorse(context, records[0], token)
        self.assertEqual(sum(session.posts for session in self.sessions), 0)
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit).status, 'pending')

    def test_server_rejects_changed_requirement_snapshot_without_retry(self):
        self.prepare_pit()
        semester, records = reviews.discover_reviewers(scope='pit', stage=self.event.event_name, year='1st Year')
        context = {'scope': 'pit', 'stage': self.event.event_name, 'year': '1st Year',
                   'semester_id': semester, 'reviewers': None}
        with patch.object(reviews.common.requests, 'Session', side_effect=self.session):
            batch = reviews.FacultyBatch('http://testserver')
            self.addCleanup(batch.close)
            current = batch.team(context, records[0])
            token = current['selected_stage']['endorsement_review']['review_token']
            definition = self.event.deliverables.get(deliverable_id='DOCS')
            definition.label = 'Updated document requirements'
            definition.save(update_fields=['label'])
            with self.assertRaises(reviews.common.ApiError) as error:
                batch.endorse(context, records[0], token)
            self.assertEqual(error.exception.status, 409)
        self.assertEqual(sum(session.posts for session in self.sessions), 1)
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit).status, 'pending')

    def test_capstone_does_not_use_section_instructor_when_adviser_missing(self):
        self.upload(self.capstone, 'PAPER')
        self.capstone.adviser = None
        self.capstone.save(update_fields=['adviser'])
        self.assertEqual(self.run_script(scope='capstone'), 2)
        self.assertEqual(self.sessions, [])
        self.assertEqual(DeliverableSubmission.objects.get(team=self.capstone).status, 'pending')

    def post_requirement(self, team, *, grouped=False, done=True, deliverable='FINAL', required=True):
        from django.utils import timezone
        from defense.stages.models import StageDeliverable
        from defense.scheduler.models import PitEventDeliverable, DefenseSchedule
        fields = {'deliverable_id': deliverable, 'label': 'Approved final manuscript',
                  'deliverable_type': 'post', 'file_format': 'pdf', 'required': required}
        if grouped:
            fields['file_policy'] = {'mode': 'named', 'slots': [
                {'key': 'paper', 'label': 'Final paper', 'file_format': 'pdf', 'required': True},
                {'key': 'notes', 'label': 'Supporting notes', 'file_format': 'pdf', 'required': False}]}
        definition = (PitEventDeliverable.objects.create(pit_event_config=self.event, **fields) if team.is_pit
                      else StageDeliverable.objects.create(defense_stage=self.stage, **fields))
        if done:
            schedule_fields = {'semester': self.semester, 'team': team,
                'scope': 'pit' if team.is_pit else 'capstone', 'scheduled_date': timezone.localdate(),
                'start_time': '09:00:00', 'room': 'Post review room', 'created_by': self.admin,
                'status': DefenseSchedule.STATUS_DONE}
            schedule_fields.update(event_name=self.event.event_name) if team.is_pit else schedule_fields.update(defense_stage=self.stage)
            # These fixtures represent an existing completed legacy defense,
            # rather than creating a new hearing through today's setup guards.
            DefenseSchedule.objects.bulk_create([DefenseSchedule(**schedule_fields)])
        return definition

    def test_post_pit_group_accepts_files_as_instructor_without_endorsement(self):
        self.post_requirement(self.pit, grouped=True)
        for slot in ['paper', 'notes']:
            self.upload(self.pit, 'FINAL', slot)
        from rest_framework_simplejwt.token_blacklist.models import OutstandingToken
        passwords = dict(get_user_model().objects.values_list('pk', 'password'))
        tokens = OutstandingToken.objects.count()
        self.assertEqual(self.run_script('--timing', 'post', dry_run=True), 0)
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit).status, 'pending')
        self.assertEqual(self.run_script('--timing', 'post'), 0)
        self.assertEqual(self.run_script('--timing', 'post'), 0)
        saved = DeliverableSubmission.objects.get(team=self.pit)
        self.assertEqual(saved.status, 'accepted')
        self.assertFalse(saved.files.exclude(status='accepted', reviewed_by=self.instructor).exists())
        self.assertEqual(saved.reviewed_by_id, self.instructor.pk)
        self.assertEqual(sum(session.posts for session in self.sessions), 2)
        self.assertTrue(all(path.endswith('/review/') for session in self.sessions for method, path, _ in session.calls if method == 'POST'))
        self.assertFalse(SystemAuditLog.objects.filter(action='repository.review_and_endorse').exists())
        self.pit.refresh_from_db()
        self.assertFalse(self.pit.ready_for_stage)
        self.assertEqual(dict(get_user_model().objects.values_list('pk', 'password')), passwords)
        self.assertEqual(OutstandingToken.objects.count(), tokens)

    def test_post_capstone_single_accepts_as_adviser_and_preserves_filename(self):
        self.post_requirement(self.capstone)
        self.upload(self.capstone, 'FINAL')
        saved = DeliverableSubmission.objects.get(team=self.capstone)
        original_name = saved.file_name
        self.assertEqual(self.run_script('--timing', 'post', scope='capstone'), 0)
        self.assertEqual(self.run_script('--timing', 'post', scope='capstone'), 0)
        saved.refresh_from_db()
        self.assertEqual(saved.status, 'accepted')
        self.assertEqual(saved.reviewed_by_id, self.adviser.pk)
        self.assertEqual(saved.file_name, original_name)
        self.assertEqual(sum(session.posts for session in self.sessions), 1)
        self.assertTrue(all(params['workspace'] == 'adviser' for session in self.sessions for _, _, params in session.calls))
        self.assertFalse(SystemAuditLog.objects.filter(action='repository.review_and_endorse').exists())

    def test_post_pending_optional_document_is_reviewed_after_required_paper_accepted(self):
        self.post_requirement(self.pit, grouped=True)
        for slot in ['paper', 'notes']:
            self.upload(self.pit, 'FINAL', slot)
        saved = DeliverableSubmission.objects.get(team=self.pit)
        paper = saved.files.get(slot_key='paper', is_current=True)
        client = reviews.common.ApiClient('http://testserver', session=_FacultySession(self.instructor))
        client.request('POST', reviews.common.API + 'review/', json={'team_id': self.pit.pk,
            'stage_label': self.event.event_name, 'deliverable_id': 'FINAL', 'file_id': paper.pk, 'status': 'accepted'})
        paper.refresh_from_db()
        original_review = paper.reviewed_at
        self.assertEqual(self.run_script('--timing', 'post'), 0)
        self.assertEqual(sum(session.posts for session in self.sessions), 1)
        paper.refresh_from_db()
        self.assertEqual(paper.reviewed_at, original_review)
        saved.refresh_from_db()
        self.assertEqual(saved.files.get(slot_key='notes', is_current=True).status, 'accepted')

    def test_post_review_stays_blocked_before_defense_despite_upload_override(self):
        self.post_requirement(self.pit, done=False)
        from repository.deliverables.stage_access import set_access
        set_access(self.admin, scope='team', program_scope='pit', team=self.pit,
            stage_label=self.event.event_name, unlock_type='post', target_state=True, reason='Allow demo upload only.')
        self.upload(self.pit, 'FINAL')
        self.assertEqual(self.run_script('--timing', 'post'), 2)
        self.assertEqual(sum(session.posts for session in self.sessions), 0)
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit).status, 'pending')

    def test_post_missing_and_rejected_files_are_not_automatically_approved(self):
        self.post_requirement(self.pit, grouped=True)
        self.assertEqual(self.run_script('--timing', 'post'), 2)
        self.upload(self.pit, 'FINAL', 'notes')
        self.assertEqual(self.run_script('--timing', 'post'), 2)
        self.upload(self.pit, 'FINAL', 'paper')
        saved = DeliverableSubmission.objects.get(team=self.pit)
        saved.status = 'rejected'
        saved.feedback = 'Fix the final manuscript first.'
        saved.save(update_fields=['status', 'feedback'])
        self.assertEqual(self.run_script('--timing', 'post'), 2)
        saved.refresh_from_db()
        self.assertEqual(saved.status, 'rejected')
        self.assertEqual(sum(session.posts for session in self.sessions), 0)

    def test_post_deliverable_filter_leaves_other_post_files_pending(self):
        self.post_requirement(self.pit)
        self.post_requirement(self.pit, done=False, deliverable='EXTRA')
        for deliverable in ['FINAL', 'EXTRA']:
            self.upload(self.pit, deliverable)
        self.assertEqual(self.run_script('--timing', 'post', '--deliverable', 'FINAL'), 0)
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit, deliverable_id='FINAL').status, 'accepted')
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit, deliverable_id='EXTRA').status, 'pending')

    def test_post_file_replaced_after_preview_is_not_reviewed_as_the_old_version(self):
        self.post_requirement(self.pit)
        self.upload(self.pit, 'FINAL')
        semester, records = reviews.discover_reviewers(scope='pit', stage=self.event.event_name, year='1st Year')
        context = {'scope': 'pit', 'stage': self.event.event_name, 'year': '1st Year',
                   'semester_id': semester, 'reviewers': None, 'timing': 'post'}
        with patch.object(reviews.common.requests, 'Session', side_effect=self.session):
            batch = reviews.FacultyBatch('http://testserver')
            self.addCleanup(batch.close)
            target = reviews.post_actions(context, batch.team(context, records[0]))[0]
            self.upload(self.pit, 'FINAL')
            with self.assertRaises(reviews.common.UploadError):
                batch.accept_post(context, records[0], target)
        self.assertEqual(sum(session.posts for session in self.sessions), 0)
        self.assertEqual(DeliverableSubmission.objects.get(team=self.pit).status, 'pending')

    def test_legacy_post_primary_file_is_accepted_through_existing_review_api(self):
        from django.core.files.base import ContentFile
        self.post_requirement(self.capstone)
        saved = DeliverableSubmission.objects.create(team=self.capstone, stage_label=self.stage.label,
            deliverable_id='FINAL', label='Approved final manuscript', deliverable_type='post', required=True,
            file_name='Legacy.pdf', file=ContentFile(b'%PDF-1.4 legacy final', name='Legacy.pdf'),
            uploaded_by=self.student, status='pending')
        self.assertEqual(self.run_script('--timing', 'post', scope='capstone'), 0)
        saved.refresh_from_db()
        self.assertEqual(saved.status, 'accepted')
        self.assertEqual(saved.reviewed_by_id, self.adviser.pk)

