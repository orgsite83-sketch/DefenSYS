"""Minutes automation exercises real JWT/API signing in the isolated test DB.

backend/venv/Scripts/python.exe backend/manage.py test execution.test_documenter_minutes --pythonpath . --keepdb --noinput
"""
from contextlib import redirect_stdout
from datetime import timedelta
from io import BytesIO, StringIO
from tempfile import TemporaryDirectory
from unittest.mock import patch
from urllib.parse import urlsplit

import pdfplumber
import requests
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase
from rest_framework_simplejwt.token_blacklist.models import OutstandingToken

from academic_period_management.models import SchoolYear, Semester
from defense.minutes.models import DefenseMinutes, MinutesPanelistComment
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import DefenseStage
from notifications.models import Notification
from student_teams.models import StudentTeam
from user_management.models import GuestPanelistCode
from execution import auto_documenter_minutes as automation


class _Response:
    def __init__(self, response):
        self.status_code = response.status_code
        self.content = response.content
        self.text = self.content.decode('utf-8', errors='replace')
        self.data = getattr(response, 'data', None)

    def json(self):
        return self.data


class _Session:
    def __init__(self, owner):
        self.headers = {}
        self.owner = owner

    def request(self, method, url, *, json=None, **kwargs):
        path = urlsplit(url).path
        if self.owner.fail_action and path.endswith(self.owner.fail_action):
            self.owner.attempted_failures += 1
            raise requests.Timeout('Simulated interruption')
        response = getattr(APIClient(), method.lower())(path, json or {}, format='json',
            HTTP_AUTHORIZATION=self.headers['Authorization'])
        self.owner.calls.append((method, path, response.wsgi_request.user.pk, response.status_code))
        if self.owner.after_request:
            self.owner.after_request(method, path)
        return _Response(response)

    def close(self):
        pass


class DocumenterMinutesAutomationTests(APITestCase):
    @classmethod
    def setUpClass(cls):
        media = TemporaryDirectory()
        cls.addClassCleanup(media.cleanup)
        settings_override = override_settings(MEDIA_ROOT=media.name)
        settings_override.enable()
        cls.addClassCleanup(settings_override.disable)
        super().setUpClass()

    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        gif = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        def signer(username, role, **kwargs):
            return User.objects.create_user(username=username, role=role,
                e_signature=SimpleUploadedFile(f'{username}.gif', gif, content_type='image/gif'), **kwargs)
        cls.admin = signer('minutes-auto-admin', 'admin')
        cls.doc = signer('minutes-auto-doc', 'faculty', is_documenter=True)
        cls.adviser = signer('minutes-auto-adviser', 'faculty')
        cls.panel = User.objects.create_user(username='minutes-auto-panel', role='faculty', is_panelist=True)
        cls.student = User.objects.create_user(username='minutes-auto-student', role='student')
        year = SchoolYear.objects.create(label='2097-2098')
        cls.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        cls.stage = DefenseStage.objects.create(label='Automation minutes stage', minutes_required=True)
        cls.team = StudentTeam.objects.create(name='Minutes automation team', project_title='Sensor prototype',
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year', semester=cls.semester,
            leader=cls.student, adviser=cls.adviser)
        cls.schedule = DefenseSchedule.objects.create(scope='capstone', team=cls.team,
            semester=cls.semester, defense_stage=cls.stage, documenter=cls.doc, created_by=cls.admin,
            scheduled_date=timezone.localdate() - timedelta(days=1), start_time='08:00', room='301', status='done')
        SchedulePanelist.objects.create(schedule=cls.schedule, panelist=cls.panel, is_chair=True)

    def setUp(self):
        self.calls = []
        self.fail_action = None
        self.attempted_failures = 0
        self.after_request = None

    def exercise(self, *extra):
        self.calls = []
        with patch.object(automation.requests, 'Session', side_effect=lambda: _Session(self)), redirect_stdout(StringIO()) as out:
            result = automation.run(['--schedule-id', str(self.schedule.pk), '--semester-id', str(self.semester.pk),
                '--base-url', 'http://testserver', '--delay', '0', *extra])
        self.output = out.getvalue()
        return result

    def writes(self):
        return [call for call in self.calls if call[0] != 'GET']

    def test_dry_run_does_not_initialize_drafts_tokens_notifications_or_credentials(self):
        before = (DefenseMinutes.objects.count(), MinutesPanelistComment.objects.count(),
            OutstandingToken.objects.count(), Notification.objects.count(),
            list(get_user_model().objects.values_list('pk', 'password', 'e_signature', 'last_login')))
        self.assertEqual(self.exercise('--sign-all', '--admin', self.admin.username, '--dry-run'), 0, self.output)
        self.assertEqual(self.calls, [])
        self.assertEqual(before, (DefenseMinutes.objects.count(), MinutesPanelistComment.objects.count(),
            OutstandingToken.objects.count(), Notification.objects.count(),
            list(get_user_model().objects.values_list('pk', 'password', 'e_signature', 'last_login'))))

    def test_complete_sequence_uses_actual_signers_and_stores_signed_pdf(self):
        token_count = OutstandingToken.objects.count()
        self.assertEqual(self.exercise('--sign-all', '--admin', self.admin.username), 0, self.output)
        minutes = DefenseMinutes.objects.get(schedule=self.schedule)
        self.assertEqual(minutes.status, 'completed')
        self.assertEqual((minutes.documenter_signed_by_id, minutes.adviser_signed_by_id, minutes.chairman_signed_by_id),
                         (self.doc.pk, self.adviser.pk, self.admin.pk))
        self.assertTrue(all((minutes.documenter_signed_at, minutes.adviser_signed_at, minutes.chairman_signed_at)))
        posts = [call for call in self.calls if call[0] == 'POST']
        self.assertEqual([(call[1].rsplit('/', 2)[1], call[2]) for call in posts],
            [('submit', self.doc.pk), ('sign-adviser', self.adviser.pk), ('sign-chairman', self.admin.pk)])
        self.assertEqual(OutstandingToken.objects.count(), token_count)
        with minutes.pdf_file.open('rb') as stream, pdfplumber.open(BytesIO(stream.read())) as pdf:
            text = '\n'.join(page.extract_text() or '' for page in pdf.pages)
            self.assertIn(self.team.name, text)
            self.assertNotIn('DRAFT PREVIEW', text)
            self.assertGreaterEqual(sum(len(page.images) for page in pdf.pages), 3)

    def test_rerun_preserves_signed_records_pdf_and_notifications(self):
        self.assertEqual(self.exercise('--sign-all'), 0, self.output)
        minutes = DefenseMinutes.objects.get(schedule=self.schedule)
        before = (minutes.updated_at, minutes.pdf_file.name, Notification.objects.count(),
                  list(minutes.panelist_comments.values_list('pk', 'comments', 'updated_at')))
        self.assertEqual(self.exercise('--sign-all', '--overwrite'), 0, self.output)
        minutes.refresh_from_db()
        self.assertEqual(self.calls, [])
        self.assertEqual(before, (minutes.updated_at, minutes.pdf_file.name, Notification.objects.count(),
            list(minutes.panelist_comments.values_list('pk', 'comments', 'updated_at'))))

    def test_comments_only_keeps_existing_feedback_and_does_not_sign(self):
        self.assertEqual(self.exercise(), 0, self.output)
        comment = MinutesPanelistComment.objects.get(minutes__schedule=self.schedule)
        comment.comments = 'Existing reviewed feedback.'
        comment.save()
        self.assertEqual(self.exercise(), 0, self.output)
        comment.refresh_from_db()
        self.assertEqual(comment.comments, 'Existing reviewed feedback.')
        self.assertEqual(DefenseMinutes.objects.get(schedule=self.schedule).status, 'draft')
        self.assertEqual(self.writes(), [])

    def test_interruption_is_not_retried_and_rerun_resumes_at_admin(self):
        self.fail_action = '/sign-chairman/'
        self.assertEqual(self.exercise('--sign-all'), 1, self.output)
        self.assertEqual(self.attempted_failures, 1)
        self.assertEqual(DefenseMinutes.objects.get(schedule=self.schedule).status, 'adviser_signed')
        self.fail_action = None
        self.assertEqual(self.exercise('--sign-all'), 0, self.output)
        self.assertEqual([call[1].rsplit('/', 2)[1] for call in self.writes()], ['sign-chairman'])

    def test_missing_signature_blocks_before_draft_creation(self):
        for user in [self.doc, self.adviser, self.admin]:
            with self.subTest(user=user.username):
                original = user.e_signature.name
                get_user_model().objects.filter(pk=user.pk).update(e_signature='')
                self.assertEqual(self.exercise('--sign-all'), 1, self.output)
                self.assertFalse(DefenseMinutes.objects.filter(schedule=self.schedule).exists())
                self.assertEqual(self.calls, [])
                get_user_model().objects.filter(pk=user.pk).update(e_signature=original)

    def test_future_or_paused_defense_is_blocked(self):
        for changes in [{'scheduled_date': timezone.localdate() + timedelta(days=1)}, {'operation_state': 'paused'}]:
            with self.subTest(changes=changes):
                original = {name: getattr(self.schedule, name) for name in changes}
                DefenseSchedule.objects.filter(pk=self.schedule.pk).update(**changes)
                self.assertEqual(self.exercise('--sign-all'), 1, self.output)
                self.assertEqual(self.calls, [])
                DefenseSchedule.objects.filter(pk=self.schedule.pk).update(**original)

    def test_stage_term_and_project_filters_exclude_other_contexts(self):
        self.assertEqual(self.exercise('--stage', 'Other stage'), 0)
        self.assertEqual(self.calls, [])
        DefenseSchedule.objects.filter(pk=self.schedule.pk).update(project_version=self.team.project_version + 1)
        self.assertEqual(self.exercise('--sign-all'), 0)
        self.assertEqual(self.calls, [])

    def test_external_panel_comments_are_filled_and_signed(self):
        guest = GuestPanelistCode.objects.create(guest_name='External Reviewer', defense_schedule=self.schedule,
                                                expires_at=timezone.now() - timedelta(days=1))
        self.assertEqual(self.exercise('--sign-all'), 0, self.output)
        comment = MinutesPanelistComment.objects.get(minutes__schedule=self.schedule, guest_invitation=guest)
        self.assertTrue(comment.comments.strip())
        self.assertEqual(DefenseMinutes.objects.get(schedule=self.schedule).status, 'completed')

    def test_changed_reviewed_comments_stop_signature(self):
        def change_comment(method, path):
            if path.endswith('/preview/'):
                MinutesPanelistComment.objects.filter(minutes__schedule=self.schedule).update(comments='Concurrent edit.')
        self.after_request = change_comment
        self.assertEqual(self.exercise('--sign-all'), 1, self.output)
        self.assertFalse(any(call[0] == 'POST' for call in self.calls))

    def test_ineligible_admin_cannot_sign_or_initialize_drafts(self):
        self.assertEqual(self.exercise('--sign-all', '--admin', self.student.username), 1, self.output)
        self.assertEqual(self.calls, [])
        self.assertFalse(DefenseMinutes.objects.filter(schedule=self.schedule).exists())
