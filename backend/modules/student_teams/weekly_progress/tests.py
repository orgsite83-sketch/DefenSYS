"""Managed weekly reports use the isolated test DB and disposable PDF storage."""
from datetime import datetime, timedelta
from io import BytesIO
import json
from tempfile import TemporaryDirectory
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from reportlab.pdfgen.canvas import Canvas
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage
from defense.template_models import DeliverableTemplate
from defense.weekly_reporting import definition, policy_payload, validate_configuration, save_configuration
from repository.deliverables.endorsement import endorsement_review, review_and_endorse
from repository.deliverables.services import required_complete, team_stage_status, upsert_submission, review_submission
from student_teams.models import StudentTeam, TeamMembership
from .models import WeeklyReportingPeriod, WeeklyProgressReport, WeeklyReportVersion
from .services import MANILA, collection_state, upload_report, review_report, week_dates


def pdf_file(name='week.pdf', text='Physically signed weekly report'):
    buffer = BytesIO()
    canvas = Canvas(buffer)
    canvas.drawString(30, 700, text)
    canvas.save()
    return SimpleUploadedFile(name, buffer.getvalue(), content_type='application/pdf')


class WeeklyReportCollectionTests(APITestCase):
    def setUp(self):
        media = TemporaryDirectory(prefix='defensys-weekly-test-')
        self.addCleanup(media.cleanup)
        settings = override_settings(MEDIA_ROOT=media.name, STORAGES={
            'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage', 'OPTIONS': {'location': media.name}},
            'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'}})
        settings.enable()
        self.addCleanup(settings.disable)
        User = get_user_model()
        self.admin = User.objects.create_user(username='weekly-admin', role='admin')
        self.student = User.objects.create_user(username='weekly-leader', role='student')
        self.other = User.objects.create_user(username='weekly-other', role='student')
        self.adviser = User.objects.create_user(username='weekly-adviser', role='faculty', is_adviser=True)
        self.unassigned = User.objects.create_user(username='weekly-unassigned', role='faculty', is_adviser=True,
            is_pit_lead=True, pit_lead_year='3rd Year')
        self.semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2098-2099'),
            label=Semester.SECOND, is_active=True, starts_on='2000-01-01', ends_on='2199-12-31')
        self.period = WeeklyReportingPeriod.objects.create(semester=self.semester, starts_on='2026-01-05',
            total_weeks=4, due_weekday=6, due_time='23:59')
        DefenseStage.objects.filter(setup_semester__isnull=True).update(is_active=False)
        self.stage = DefenseStage.objects.create(label='Weekly proposal', setup_semester=self.semester,
            weekly_reporting={'enabled': True, 'period_id': self.period.pk, 'required_start': 1, 'required_end': 2})
        self.team = StudentTeam.objects.create(name='Weekly team', semester=self.semester,
            intake_semester=self.semester, leader=self.student, adviser=self.adviser,
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        self.url = '/api/teams/weekly-progress/collection/'

    def upload(self, week=1, **kwargs):
        return upload_report(self.team, self.stage.label, actor=self.student, week=week,
            file=pdf_file(**kwargs))

    def review(self, version, decision='accepted', feedback='', actor=None):
        return review_report(self.team, self.stage.label, actor=actor or self.adviser,
            version_id=version.pk, decision=decision, feedback=feedback)

    def test_empty_slots_do_not_create_reports_or_increment_requirement_count(self):
        self.client.force_authenticate(self.student)
        response = self.client.get(self.url, {'team_id': self.team.pk, 'stage_label': self.stage.label})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([week['week_number'] for week in response.data['weeks']], [1, 2])
        self.assertEqual(response.data['weekly_summary']['required'], 2)
        self.assertEqual(response.data['current_week'], 2)
        self.assertTrue(response.data['period_ended'])
        self.assertFalse(WeeklyProgressReport.objects.exists())

    def test_new_calendar_length_comes_from_required_reports_not_legacy_default(self):
        semester = Semester.objects.create(school_year=self.semester.school_year,
            label=Semester.FIRST, is_active=False)
        raw = {'enabled': True, 'starts_on': '2026-10-25', 'due_weekday': 6,
            'due_time': '23:59', 'required_start': 1, 'required_end': 2, 'total_weeks': 16}
        for count in (1, 2, 20):
            clean = validate_configuration({**raw, 'required_end': count}, semester=semester)
            self.assertEqual(clean['total_weeks'], count)
        stage = DefenseStage.objects.create(label='Admin count only', setup_semester=semester, is_active=False)
        saved = save_configuration(stage, raw)
        period = WeeklyReportingPeriod.objects.get(pk=saved['period_id'])
        self.assertEqual(period.total_weeks, 2)
        self.assertEqual(saved['required_end'], 2)

    def test_upload_requires_the_selected_stages_configured_week(self):
        for week in (0, 3, 16):
            with self.assertRaisesMessage(Exception, 'valid configured week'):
                self.upload(week)
        self.assertFalse(WeeklyProgressReport.objects.exists())
        self.assertFalse(WeeklyReportVersion.objects.exists())

    def test_late_reports_remain_uploadable_and_accepted_late_satisfies_gate(self):
        first = self.upload(2)
        self.review(first)
        self.assertFalse(required_complete(self.team, self.stage.label))
        last = self.upload(1)
        self.assertEqual(team_stage_status(self.team, self.stage.label), 'pending_review')
        review = endorsement_review(self.team, self.stage.label)
        self.assertFalse(review['can_review_and_endorse'])
        self.assertIn('awaiting adviser acceptance', review['reason'])
        self.review(last)
        state = collection_state(self.team, definition(self.stage), actor=self.adviser, details=True)
        self.assertTrue(state['completed'])
        self.assertEqual(state['weekly_summary']['late'], 2)
        self.assertTrue(required_complete(self.team, self.stage.label))
        review = endorsement_review(self.team, self.stage.label)
        self.assertTrue(review['can_review_and_endorse'], review)
        review_and_endorse(self.team, self.stage.label, actor=self.adviser, review_token=review['review_token'])

    def test_week_boundary_and_future_slots(self):
        config = definition(self.stage)['weekly_reporting']
        start, end, due = week_dates(config, 1)
        self.assertEqual(str(start), '2026-01-05')
        self.assertEqual(str(end), '2026-01-11')
        self.assertEqual(due, datetime(2026, 1, 11, 23, 59, tzinfo=MANILA))
        with patch('django.utils.timezone.now', return_value=due):
            self.upload()
        state = collection_state(self.team, definition(self.stage), actor=self.adviser, details=True, now=due)
        self.assertEqual(state['weeks'][0]['timing'], 'on_time')
        self.assertEqual(state['weeks'][1]['timing'], 'upcoming')
        self.assertEqual(state['weekly_summary']['overdue'], 0)

    def test_correction_preserves_original_time_and_requires_new_current_version(self):
        first = self.upload()
        original_time = first.report.submitted_at
        self.review(first, 'rejected', 'Please include the physical adviser signature.')
        with self.assertRaisesMessage(Exception, 'corrected version'):
            self.review(first)
        second = self.upload(text='Corrected physically signed weekly report')
        self.assertEqual(second.revision, 2)
        self.assertEqual(second.report.submitted_at, original_time)
        self.assertEqual(WeeklyReportVersion.objects.count(), 2)
        with self.assertRaisesMessage(Exception, 'changed'):
            self.review(first)
        self.review(second)
        with self.assertRaises(PermissionError):
            self.upload(text='Attempt to replace an accepted report')

    def test_generic_review_and_upload_cannot_bypass_per_week_acceptance(self):
        self.upload()
        with self.assertRaises(PermissionError):
            upsert_submission(self.team, self.stage.label, 'WPR', 'compiled.pdf', '2 KB', self.student, file=pdf_file())
        with self.assertRaises(PermissionError):
            review_submission(self.team, self.stage.label, 'WPR', 'accepted', '', self.adviser)

    def test_same_calendar_reuses_accepted_reports_with_stage_specific_range(self):
        self.review(self.upload())
        later = DefenseStage.objects.create(label='Weekly final', setup_semester=self.semester,
            weekly_reporting={'enabled': True, 'period_id': self.period.pk, 'required_start': 1, 'required_end': 4})
        state = collection_state(self.team, definition(later))
        self.assertEqual(state['weekly_summary']['accepted'], 1)
        self.assertEqual(state['weekly_summary']['required'], 4)
        self.assertFalse(state['completed'])
        self.assertEqual(WeeklyProgressReport.objects.count(), 1)
        third = upload_report(self.team, later.label, actor=self.student, week=3, file=pdf_file())
        with self.assertRaisesMessage(Exception, 'changed'):
            self.review(third)
        review_report(self.team, later.label, actor=self.adviser,
            version_id=third.pk, decision='accepted')
        original = collection_state(self.team, definition(self.stage), actor=self.adviser, details=True)
        self.assertEqual([week['week_number'] for week in original['weeks']], [1, 2])
        self.assertEqual(original['weekly_summary']['accepted'], 1)
        self.assertTrue(WeeklyReportVersion.objects.filter(pk=third.pk, status='accepted').exists())

    def test_configuration_and_disable_protected_after_report_upload(self):
        self.upload()
        with self.assertRaisesMessage(Exception, 'cannot be disabled'):
            validate_configuration({'enabled': False}, stage=self.stage, semester=self.semester)
        config = policy_payload(self.stage)
        config['required_end'] = 3
        with self.assertRaisesMessage(Exception, 'protected'):
            validate_configuration(config, stage=self.stage, semester=self.semester)

    def test_unassigned_adviser_admin_and_student_cannot_accept(self):
        version = self.upload()
        for actor in (self.unassigned, self.admin, self.student):
            with self.assertRaises(PermissionError):
                self.review(version, actor=actor)

    def test_private_version_history_and_media_have_same_scope(self):
        version = self.upload()
        for actor, expected in ((self.student, 200), (self.adviser, 200), (self.admin, 200), (self.unassigned, 404), (self.other, 404)):
            self.client.force_authenticate(actor)
            response = self.client.get(f'/api/teams/weekly-progress/{version.report_id}/file/?version_id={version.pk}')
            self.assertEqual(response.status_code, expected)
            if expected == 200:
                self.assertTrue(b''.join(response.streaming_content).startswith(b'%PDF'))
            response = self.client.get(f'/api/teams/weekly-progress/{version.report_id}/versions/')
            self.assertEqual(response.status_code, expected)

    def test_published_stage_and_docx_template_save_together(self):
        self.client.force_authenticate(self.admin)
        config = policy_payload(self.stage)
        body = {'label': 'Weekly configured stage', 'weekly_reporting': config,
            'template_changes': [{'scope': 'team', 'deliverable_id': 'WPR', 'action': 'replace', 'upload_key': 'template'}]}
        response = self.client.post('/api/defense/stages/', {'configuration': json.dumps(body),
            'template': SimpleUploadedFile('weekly.docx', b'editable Word template')}, format='multipart')
        self.assertEqual(response.status_code, 201, response.data)
        stage = response.data['stage']
        self.assertEqual(stage['deliverables_count'], 1)
        weekly = next(d for d in stage['system_deliverables'] if d['source'] == 'weekly_reports')
        self.assertEqual(weekly['template']['original_name'], 'weekly.docx')

    def test_published_setup_without_template_rolls_back(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/stages/', {'label': 'Missing weekly template',
            'weekly_reporting': policy_payload(self.stage)}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertFalse(DefenseStage.objects.filter(label='Missing weekly template').exists())

    def test_published_weekly_templates_accept_shared_formats_and_preserve_downloads(self):
        self.client.force_authenticate(self.admin)
        for extension in ('PDF', 'png', 'xlsx', 'mp4', 'mp3', 'txt', 'zip'):
            with self.subTest(extension=extension):
                name = f'weekly.{extension}'
                file = pdf_file(name) if extension == 'PDF' else SimpleUploadedFile(name, b'Original template bytes')
                original = file.read()
                file.seek(0)
                body = {'label': f'Weekly {extension} template', 'weekly_reporting': policy_payload(self.stage),
                    'template_changes': [{'scope': 'team', 'deliverable_id': 'WPR',
                        'action': 'replace', 'upload_key': 'template'}]}
                response = self.client.post('/api/defense/stages/', {
                    'configuration': json.dumps(body), 'template': file}, format='multipart')
                self.assertEqual(response.status_code, 201, response.data)
                weekly = next(d for d in response.data['stage']['system_deliverables'] if d['source'] == 'weekly_reports')
                self.assertEqual(weekly['file_format'], 'pdf')
                self.assertEqual(weekly['template']['original_name'], name)
                download = self.client.get(weekly['template']['file_url'])
                self.assertEqual(download.status_code, 200)
                self.assertEqual(b''.join(download.streaming_content), original)

    def test_saved_pdf_template_survives_edits_and_rejects_missing_or_unsupported_replacements(self):
        self.client.force_authenticate(self.admin)
        url = f'/api/defense/stages/{self.stage.pk}/'
        change = {'scope': 'team', 'deliverable_id': 'WPR', 'action': 'replace', 'upload_key': 'template'}
        response = self.client.patch(url, {'configuration': json.dumps({'template_changes': [change]}),
            'template': pdf_file('weekly.pdf')}, format='multipart')
        self.assertEqual(response.status_code, 200, response.data)
        attachment = DeliverableTemplate.objects.get(defense_stage=self.stage, deliverable_id='WPR')
        original_file = attachment.file.name
        # Reopening setup uses GET rather than the attachment-enriched save response.
        for endpoint in (url, '/api/defense/stages/'):
            response = self.client.get(endpoint)
            self.assertEqual(response.status_code, 200, response.data)
            stage = (response.data['stage'] if endpoint == url else
                next(stage for stage in response.data['stages'] if stage['id'] == self.stage.pk))
            weekly = next(row for row in stage['system_deliverables'] if row['source'] == 'weekly_reports')
            self.assertEqual(weekly['template']['id'], attachment.pk)
            self.assertEqual(weekly['template']['original_name'], 'weekly.pdf')
            self.assertEqual(weekly['weekly_reporting']['required_end'], 2)
        response = self.client.patch(url, {'description': 'Preserve the PDF template'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200, response.data)
        weekly = next(row for row in response.data['stage']['system_deliverables'] if row['source'] == 'weekly_reports')
        self.assertEqual(weekly['template']['id'], attachment.pk)
        response = self.client.patch(url, {'configuration': json.dumps({'template_changes': [change]}),
            'template': SimpleUploadedFile('weekly.exe', b'unsupported')}, format='multipart')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('not supported', str(response.data))
        response = self.client.patch(url, {'template_changes': [
            {'scope': 'team', 'deliverable_id': 'WPR', 'action': 'remove'}]}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        attachment.refresh_from_db()
        self.assertEqual(attachment.file.name, original_file)
        self.assertEqual(attachment.original_name, 'weekly.pdf')

    def test_flexible_templates_do_not_allow_non_pdf_report_submissions(self):
        for extension in ('docx', 'png', 'zip'):
            with self.subTest(extension=extension), self.assertRaises(Exception):
                upload_report(self.team, self.stage.label, actor=self.student, week=1,
                    file=SimpleUploadedFile(f'week.{extension}', b'not a signed PDF'))
        self.assertFalse(WeeklyProgressReport.objects.exists())

    def test_invalid_or_duplicate_upload_does_not_create_extra_week(self):
        with self.assertRaises(Exception):
            upload_report(self.team, self.stage.label, actor=self.student, week=1,
                file=SimpleUploadedFile('invalid.pdf', b'not a PDF'))
        self.assertFalse(WeeklyProgressReport.objects.exists())
        version = self.upload()
        # Same file bytes are an idempotent pending retry.
        with version.file.open('rb') as source:
            retry = upload_report(self.team, self.stage.label, actor=self.student, week=1,
                file=SimpleUploadedFile('week.pdf', source.read()))
        self.assertEqual(retry.pk, version.pk)
        self.assertEqual(WeeklyReportVersion.objects.count(), 1)

    def test_upload_and_review_api_refresh_the_real_deliverable_team_row(self):
        self.client.force_authenticate(self.student)
        url = self.url + '?response_mode=team&scope=capstone&stage_label=Weekly%20proposal'
        response = self.client.post(url, {'team_id': self.team.pk, 'stage_label': self.stage.label,
            'semester_id': self.semester.pk, 'project_version': self.team.project_version,
            'week_number': 1, 'report_file': pdf_file()}, format='multipart')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['team']['id'], self.team.pk)
        self.assertEqual(response.data['team']['selected_stage']['required_total'], 1)
        weekly = next(d for d in response.data['team']['selected_stage']['pre'] if d['source'] == 'weekly_reports')
        self.assertEqual(weekly['weekly_summary']['uploaded'], 1)
        self.assertEqual(weekly['weekly_summary']['accepted'], 0)
        self.client.force_authenticate(self.adviser)
        response = self.client.post('/api/teams/weekly-progress/collection/review/?response_mode=team&scope=capstone',
            {'team_id': self.team.pk, 'stage_label': self.stage.label,
             'version_id': response.data['version']['id'], 'status': 'accepted'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['collection']['weekly_summary']['accepted'], 1)
        self.assertFalse(response.data['team']['selected_stage']['required_complete'])

    def test_new_stage_can_attach_its_initial_template_to_an_already_used_period(self):
        self.review(self.upload())
        self.client.force_authenticate(self.admin)
        config = {**policy_payload(self.stage), 'required_end': 8}
        body = {'label': 'Later weekly stage', 'weekly_reporting': config,
            'template_changes': [{'scope': 'team', 'deliverable_id': 'WPR', 'action': 'replace', 'upload_key': 'template'}]}
        response = self.client.post('/api/defense/stages/', {'configuration': json.dumps(body),
            'template': SimpleUploadedFile('weekly.docx', b'editable Word template')}, format='multipart')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['stage']['weekly_reporting']['period_id'], self.period.pk)
        self.assertEqual(response.data['stage']['weekly_reporting']['required_end'], 8)
        self.period.refresh_from_db()
        self.assertEqual(self.period.total_weeks, 8)
        self.assertEqual(str(self.period.starts_on), '2026-01-05')
        self.assertEqual(self.stage.weekly_reporting['required_end'], 2)
        self.assertEqual(WeeklyProgressReport.objects.count(), 1)

    def test_stage_deletion_and_old_compilation_cannot_remove_or_replace_weekly_evidence(self):
        self.upload()
        self.client.force_authenticate(self.admin)
        response = self.client.delete(f'/api/defense/stages/{self.stage.pk}/')
        self.assertEqual(response.status_code, 409, response.data)
        response = self.client.post('/api/repository/deliverables/compile-weekly-reports/',
            {'team_id': self.team.pk, 'stage_label': self.stage.label}, format='json')
        self.assertEqual(response.status_code, 410, response.data)
        self.assertEqual(WeeklyReportVersion.objects.count(), 1)

    def test_context_change_or_unpublished_stage_cannot_receive_a_submission(self):
        from rest_framework.exceptions import ValidationError
        self.team.project_version += 1
        with self.assertRaisesMessage(ValidationError, 'changed'):
            self.upload()
        self.team.refresh_from_db()
        self.stage.is_active = False
        self.stage.save(update_fields=['is_active'])
        with self.assertRaisesMessage(ValidationError, 'not configured'):
            self.upload()
        self.assertFalse(WeeklyProgressReport.objects.exists())

    def test_request_id_retry_does_not_create_a_version_or_change_original_pdf(self):
        from uuid import uuid4
        key = uuid4()
        source = pdf_file()
        data = source.read()
        source.seek(0)
        first = upload_report(self.team, self.stage.label, actor=self.student, week=1, file=source, request_id=key)
        self.review(first)
        retry = upload_report(self.team, self.stage.label, actor=self.student, week=1,
            file=SimpleUploadedFile('week.pdf', data), request_id=key)
        self.assertEqual(first.pk, retry.pk)
        self.assertEqual(WeeklyReportVersion.objects.count(), 1)
        with first.file.open('rb') as saved:
            self.assertEqual(saved.read(), data)

    def test_accepted_week_reopened_before_scheduling_invalidates_endorsement(self):
        first = self.upload()
        self.review(first)
        self.review(self.upload(2))
        state = endorsement_review(self.team, self.stage.label)
        review_and_endorse(self.team, self.stage.label, actor=self.adviser, review_token=state['review_token'])
        self.review(first, 'rejected', 'Please correct the signed report.')
        self.client.force_authenticate(self.adviser)
        response = self.client.get(f'/api/teams/weekly-progress/{first.report_id}/versions/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([r['status'] for r in response.data['versions'][0]['reviews']], ['accepted', 'rejected'])
        self.assertFalse(required_complete(self.team, self.stage.label))
        with self.assertRaises(Exception):
            review_and_endorse(self.team, self.stage.label, actor=self.adviser, review_token=state['review_token'])

    def test_one_team_weekly_review_response_does_not_load_the_whole_cohort(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext
        version = self.upload()
        self.review(version)
        self.client.force_authenticate(self.adviser)
        url = '/api/teams/weekly-progress/collection/review/?response_mode=team&scope=capstone'
        body = {'team_id': self.team.pk, 'stage_label': self.stage.label, 'version_id': version.pk, 'status': 'accepted'}
        with CaptureQueriesContext(connection) as queries:
            response = self.client.post(url, body, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        single = len(queries)
        for number in range(7):
            # Keep the cohort realistic under the four-active-team adviser cap.
            StudentTeam.objects.create(name=f'Other weekly team {number}', semester=self.semester,
                intake_semester=self.semester, leader=self.student,
                adviser=self.adviser if number < 3 else self.unassigned,
                level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        with CaptureQueriesContext(connection) as queries:
            response = self.client.post(url, body, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertLessEqual(len(queries), single + 2)

    def test_new_leader_can_continue_current_team_reports_without_transferring_uploader_identity(self):
        version = self.upload()
        self.team.leader = self.other
        self.team.save(update_fields=['leader'])
        TeamMembership.objects.filter(team=self.team).update(is_leader=False)
        TeamMembership.objects.create(team=self.team, student=self.other, is_leader=True)
        self.client.force_authenticate(self.other)
        response = self.client.get(f'/api/teams/weekly-progress/{version.report_id}/versions/')
        self.assertEqual(response.status_code, 200, response.data)
        self.review(version, 'rejected', 'Please upload the physically signed correction.')
        corrected = upload_report(self.team, self.stage.label, actor=self.other, week=1,
            file=pdf_file(text='Correction uploaded by the new team leader'))
        self.assertEqual(corrected.report_id, version.report_id)
        self.assertEqual(corrected.revision, 2)
        self.assertEqual(corrected.report.student_id, self.student.pk)
        self.assertEqual(corrected.uploaded_by_id, self.other.pk)
        with self.assertRaises(PermissionError):
            self.upload(text='Former leader is no longer the authorized uploader')

    def test_current_leader_access_does_not_extend_to_another_project_or_ordinary_member(self):
        version = self.upload()
        member = get_user_model().objects.create_user(username='weekly-ordinary-member', role='student')
        TeamMembership.objects.create(team=self.team, student=member)
        self.client.force_authenticate(member)
        response = self.client.get(f'/api/teams/weekly-progress/{version.report_id}/versions/')
        self.assertEqual(response.status_code, 404)
        self.team.leader = self.other
        self.team.project_version += 1
        self.team.save(update_fields=['leader', 'project_version'])
        TeamMembership.objects.create(team=self.team, student=self.other, is_leader=True)
        self.client.force_authenticate(self.other)
        response = self.client.get(f'/api/teams/weekly-progress/{version.report_id}/versions/')
        self.assertEqual(response.status_code, 404)
