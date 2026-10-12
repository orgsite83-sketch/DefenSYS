from datetime import date, time, timedelta
from io import BytesIO
from tempfile import TemporaryDirectory

import pdfplumber
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import DefenseStage
from student_teams.models import StudentTeam
from user_management.models import ExternalEvaluator, GuestPanelistCode
from .models import DefenseMinutes, MinutesPanelistComment


class ExternalPanelistMinutesTests(APITestCase):
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
        cls.admin = User.objects.create_user(username='external-minutes-admin', role='admin')
        signature = SimpleUploadedFile('signature.gif',
            b'GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;',
            content_type='image/gif')
        cls.doc = User.objects.create_user(username='external-minutes-doc', role='faculty',
                                         is_documenter=True, e_signature=signature)
        cls.chair = User.objects.create_user(username='external-minutes-chair', role='faculty',
                                           is_panelist=True, first_name='Panel', last_name='Chair')
        cls.student = User.objects.create_user(username='external-minutes-student', role='student')
        year = SchoolYear.objects.create(label='2028-2029')
        cls.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        cls.stage = DefenseStage.objects.create(label='External minutes stage', minutes_required=True)
        cls.team = StudentTeam.objects.create(name='External minutes team', project_title='Soil sensors',
            semester=cls.semester, leader=cls.student, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        cls.schedule = DefenseSchedule.objects.create(scope='capstone', team=cls.team, semester=cls.semester,
            defense_stage=cls.stage, documenter=cls.doc, scheduled_date=date(2026, 10, 10),
            start_time=time(8), room='301', created_by=cls.admin)
        SchedulePanelist.objects.create(schedule=cls.schedule, panelist=cls.chair, is_chair=True)
        cls.evaluator = ExternalEvaluator.objects.create(name='Dr. Rivera & Santos', status='approved')
        cls.invitation = GuestPanelistCode.objects.create(evaluator=cls.evaluator,
            guest_name=cls.evaluator.name, defense_schedule=cls.schedule,
            expires_at=timezone.now() - timedelta(days=1))
        cls.invitation.schedules.add(cls.schedule)

    def setUp(self):
        self.client.force_authenticate(self.doc)
        self.url = f'/api/defense/minutes/{self.schedule.pk}/'

    def get_minutes(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def pdf_text(self, response):
        self.assertEqual(response.status_code, 200)
        with pdfplumber.open(BytesIO(response.content)) as pdf:
            return '\n'.join(page.extract_text() or '' for page in pdf.pages)

    def test_mixed_panel_creates_external_roster_and_comment_section_once(self):
        data = self.get_minutes()
        self.assertEqual([p['name'] for p in data['schedule']['panelists']],
                         ['Panel Chair', self.evaluator.name])
        self.assertTrue(data['schedule']['panelists'][1]['is_external'])
        self.assertFalse(data['schedule']['panelists'][1]['is_chair'])
        guest = data['panelist_comments'][1]
        self.assertIsNone(guest['panelist'])
        self.assertEqual(guest['guest_invitation'], self.invitation.pk)
        self.assertEqual(guest['panelist_role_snapshot'], 'External Panelist')
        self.assertEqual(self.get_minutes()['panelist_comments'], data['panelist_comments'])
        self.assertEqual(MinutesPanelistComment.objects.count(), 2)

    def test_existing_draft_is_backfilled_without_overwriting_recorded_comments(self):
        self.get_minutes()
        minutes = DefenseMinutes.objects.get(schedule=self.schedule)
        minutes.panelist_comments.filter(guest_invitation=self.invitation).delete()
        chair = minutes.panelist_comments.get(panelist=self.chair)
        chair.comments = 'Keep the calibration results.'
        chair.save()
        data = self.get_minutes()
        self.assertEqual(len(data['panelist_comments']), 2)
        chair.refresh_from_db()
        self.assertEqual(chair.comments, 'Keep the calibration results.')
        self.assertEqual(data['panelist_comments'][0]['id'], chair.pk)

    def test_legacy_code_and_expired_or_revoked_access_still_have_minutes_sections(self):
        self.invitation.is_active = False
        self.invitation.save(update_fields=['is_active'])
        legacy = GuestPanelistCode.objects.create(guest_name='Legacy Guest', defense_schedule=self.schedule)
        unrelated = GuestPanelistCode.objects.create(guest_name='Unassigned Guest')
        data = self.get_minutes()
        self.assertEqual({c['guest_invitation'] for c in data['panelist_comments'] if c['guest_invitation']},
                         {self.invitation.pk, legacy.pk})
        self.assertNotIn(unrelated.pk, [c['guest_invitation'] for c in data['panelist_comments']])

    def test_shared_invitation_records_comments_separately_for_each_defense(self):
        other = DefenseSchedule.objects.create(scope='capstone', team=self.team, semester=self.semester,
            defense_stage=self.stage, documenter=self.doc, scheduled_date=date(2026, 10, 10),
            start_time=time(9), room='301', created_by=self.admin)
        self.invitation.schedules.add(other)
        first = self.get_minutes()['panelist_comments'][1]
        response = self.client.get(f'/api/defense/minutes/{other.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        second = response.data['panelist_comments'][0]
        self.assertEqual(second['guest_invitation'], first['guest_invitation'])
        self.assertNotEqual(second['id'], first['id'])
        self.client.patch(self.url, {'comments': [{'id': first['id'], 'comments': 'Only for the first team.'}]}, format='json')
        self.assertEqual(MinutesPanelistComment.objects.get(pk=second['id']).comments, '')

    def test_repeated_invitation_for_same_evaluator_does_not_duplicate_sections(self):
        invitation = GuestPanelistCode.objects.create(evaluator=self.evaluator, guest_name=self.evaluator.name)
        invitation.schedules.add(self.schedule)
        data = self.get_minutes()
        self.assertEqual(len(data['panelist_comments']), 2)
        self.assertEqual(len(data['schedule']['panelists']), 2)

    def test_external_comment_is_required_and_saved_before_documenter_can_sign(self):
        data = self.get_minutes()
        chair, guest = data['panelist_comments']
        self.client.patch(self.url, {'comments': [{'id': chair['id'], 'comments': 'Chair comments.'}]}, format='json')
        response = self.client.post(self.url + 'submit/')
        self.assertEqual(response.status_code, 400)
        self.assertIn('All panelist comments', response.data['detail'])
        saved = self.client.patch(self.url, {'comments': [{'id': guest['id'], 'comments': 'Check soil calibration.'}]}, format='json')
        self.assertEqual(saved.status_code, 200, saved.data)
        response = self.client.post(self.url + 'submit/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], DefenseMinutes.STATUS_SUBMITTED)

    def test_removed_guest_is_hidden_but_retained_and_stale_edits_rejected(self):
        data = self.get_minutes()
        guest = data['panelist_comments'][1]
        self.invitation.schedules.clear()
        self.invitation.defense_schedule = None
        self.invitation.save(update_fields=['defense_schedule'])
        self.assertEqual(len(self.get_minutes()['panelist_comments']), 1)
        self.assertTrue(MinutesPanelistComment.objects.filter(pk=guest['id']).exists())
        response = self.client.patch(self.url, {'comments': [{'id': guest['id'], 'comments': 'Stale save.'}]}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertNotIn(self.evaluator.name, self.pdf_text(self.client.get(self.url + 'preview/')))

    def test_external_name_and_comments_appear_in_pdf(self):
        guest = self.get_minutes()['panelist_comments'][1]
        self.client.patch(self.url, {'comments': [{'id': guest['id'], 'comments': 'External: calibrate sensors < 10.'}]}, format='json')
        text = self.pdf_text(self.client.get(self.url + 'preview/'))
        self.assertIn(self.evaluator.name, text)
        self.assertIn('External Panelist', text)
        self.assertIn('External: calibrate sensors < 10.', text)

    def test_preview_includes_missing_external_section_without_writing_to_draft(self):
        self.get_minutes()
        MinutesPanelistComment.objects.filter(guest_invitation=self.invitation).delete()
        text = self.pdf_text(self.client.get(self.url + 'preview/'))
        self.assertIn(self.evaluator.name, text)
        self.assertEqual(MinutesPanelistComment.objects.count(), 1)

    def test_signed_minutes_are_not_backfilled(self):
        self.get_minutes()
        minutes = DefenseMinutes.objects.get(schedule=self.schedule)
        minutes.panelist_comments.filter(guest_invitation=self.invitation).delete()
        minutes.status = DefenseMinutes.STATUS_SUBMITTED
        minutes.documenter_signed_at = timezone.now()
        minutes.documenter_signed_by = self.doc
        minutes.save()
        self.assertEqual(len(self.get_minutes()['panelist_comments']), 1)
        self.assertNotIn(self.evaluator.name, self.pdf_text(self.client.get(self.url + 'preview/')))
        minutes.refresh_from_db()
        self.assertEqual(minutes.status, DefenseMinutes.STATUS_SUBMITTED)

    def test_external_replacement_preserves_signed_snapshot_and_adds_new_draft_section(self):
        data = self.get_minutes()
        guest = MinutesPanelistComment.objects.get(pk=data['panelist_comments'][1]['id'])
        guest.comments = 'Original external recommendations.'
        guest.save()
        minutes = DefenseMinutes.objects.get(schedule=self.schedule)
        minutes.status = DefenseMinutes.STATUS_SUBMITTED
        minutes.documenter_signed_at = timezone.now()
        minutes.documenter_signed_by = self.doc
        minutes.save()
        replacement = ExternalEvaluator.objects.create(name='Replacement external', status='approved')
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/board/operations/', {
            'action': 'update', 'anchor_id': self.schedule.pk,
            'expected_revisions': {str(self.schedule.pk): self.schedule.revision},
            'reason': 'Replace unavailable external panelist',
            'changes': {'external_evaluator_ids': [replacement.pk], 'acknowledge_minutes_amendment': True},
        }, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        minutes.refresh_from_db()
        self.assertEqual(minutes.status, DefenseMinutes.STATUS_DRAFT)
        self.assertIsNone(minutes.documenter_signed_at)
        revision = minutes.revisions.get()
        recorded_guest = next(c for c in revision.snapshot['comments'] if c['guest_invitation_id'])
        self.assertEqual(recorded_guest['guest_invitation_id'], self.invitation.pk)
        self.assertEqual(recorded_guest['comments'], 'Original external recommendations.')
        active_guests = [c for c in minutes.current_panelist_comments if c.guest_invitation_id]
        self.assertEqual(len(active_guests), 1)
        self.assertEqual(active_guests[0].panelist_name_snapshot, replacement.name)
        self.assertEqual(active_guests[0].comments, '')
        guest.refresh_from_db()
        self.assertEqual(guest.comments, 'Original external recommendations.')
