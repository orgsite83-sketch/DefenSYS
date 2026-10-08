from datetime import date, time
from io import BytesIO
from tempfile import TemporaryDirectory

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.files.base import ContentFile
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
import pdfplumber

from academic_period_management.models import SchoolYear, Semester
from defense.minutes.models import DefenseMinutes, DefenseMinutesRevision, MinutesPanelistComment
from defense.minutes.requirements import minutes_complete, signed_minutes_archive_entries, stage_minutes_requirement
from defense.scheduler.models import DefenseSchedule, SchedulePanelist
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission
from repository.deliverables.services import stage_payload, upsert_submission
from student_teams.models import StudentTeam


class SignedMinutesRequirementTests(APITestCase):
    def setUp(self):
        self.media = TemporaryDirectory()
        self.settings_override = override_settings(MEDIA_ROOT=self.media.name)
        self.settings_override.enable()
        self.addCleanup(self.settings_override.disable)
        self.addCleanup(self.media.cleanup)
        User = get_user_model()
        self.admin = User.objects.create_user(username='minutes-admin', role='admin', is_staff=True)
        self.doc = User.objects.create_user(username='minutes-documenter', role='faculty', is_documenter=True)
        self.adviser = User.objects.create_user(username='minutes-adviser', role='faculty')
        self.student = User.objects.create_user(username='minutes-student', role='student', first_name='Alex', last_name='Rivera')
        self.outsider = User.objects.create_user(username='minutes-outsider', role='student')
        year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(school_year=year, label=Semester.FIRST, is_active=True)
        self.stage, _ = DefenseStage.objects.update_or_create(label='Concept Proposal', defaults={'minutes_required': True, 'minutes_deliverable_id': '5', 'minutes_deliverable_label': 'Signed Minutes - Concept'})
        self.team = StudentTeam.objects.create(name='Minutes Team', project_title='Water & Soil', semester=self.semester, leader=self.student, adviser=self.adviser, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        self.schedule = self.make_schedule(self.stage)
        self.minutes = DefenseMinutes.objects.create(schedule=self.schedule, team_name=self.team.name, project_title=self.team.project_title, adviser_name='Adviser', documenter_name='Documenter', defense_stage_label=self.stage.label, defense_date=date(2026, 10, 8), defense_time=time(8), room='Room 301')
        self.comment = MinutesPanelistComment.objects.create(minutes=self.minutes, panelist=self.adviser, panelist_name_snapshot='Panel Member', comments='Review sensors < measurements & calibration.')

    def make_schedule(self, stage, **changes):
        values = dict(scope='capstone', team=self.team, semester=self.semester, defense_stage=stage, documenter=self.doc if stage.minutes_required else None, scheduled_date=date(2026, 10, 8), start_time=time(8), room='Room 301', created_by=self.admin)
        values.update(changes)
        return DefenseSchedule.objects.create(**values)

    def finalize(self):
        self.minutes.status = DefenseMinutes.STATUS_COMPLETED
        now = timezone.now()
        self.minutes.documenter_signed_at = self.minutes.adviser_signed_at = self.minutes.chairman_signed_at = now
        self.minutes.documenter_signed_by = self.doc
        self.minutes.adviser_signed_by = self.adviser
        self.minutes.chairman_signed_by = self.admin
        self.minutes.pdf_file.save('signed.pdf', ContentFile(b'%PDF-1.4 signed fixture'), save=False)
        self.minutes.save()

    def test_admin_configuration_adds_generated_deliverable_without_student_upload_definition(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/stages/', {'label': 'Proposal Defense', 'minutes_required': True, 'minutes_deliverable_id': '12', 'minutes_deliverable_label': 'Signed Minutes - Proposal', 'is_presentation_only': True}, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        stage = response.data['stage']
        self.assertEqual(stage['deliverables_count'], 1)
        self.assertEqual(stage['deliverables'], [])
        self.assertEqual(stage['system_deliverables'][0]['source'], 'defense_minutes')
        self.assertEqual(stage['system_deliverables'][0]['file_format'], 'pdf')

    def test_exhibit_has_no_signed_minutes_requirement(self):
        exhibit = DefenseStage.objects.create(label='Exhibit', is_presentation_only=True, minutes_required=False)
        self.make_schedule(exhibit)
        self.assertIsNone(stage_minutes_requirement(self.team, exhibit))

    def test_required_schedule_cannot_be_created_without_documenter(self):
        with self.assertRaises(ValidationError):
            self.make_schedule(self.stage, documenter=None)

    def test_moving_schedule_to_required_stage_resnapshots_requirement(self):
        exhibit = DefenseStage.objects.create(label='Move from exhibit', minutes_required=False)
        schedule = self.make_schedule(exhibit)
        schedule.defense_stage = self.stage
        with self.assertRaises(ValidationError):
            schedule.save()
        schedule.documenter = self.doc
        schedule.save()
        schedule.refresh_from_db()
        self.assertTrue(schedule.requires_minutes)
        self.assertEqual(schedule.minutes_deliverable_id, '5')

    def test_required_documenter_cannot_be_removed(self):
        self.schedule.documenter = None
        with self.assertRaises(ValidationError):
            self.schedule.save()

    def test_confirmed_requirement_and_identity_survive_stage_changes(self):
        self.stage.minutes_required = False
        self.stage.minutes_deliverable_id = 'new-number'
        self.stage.save()
        row = stage_minutes_requirement(self.team, self.stage)
        self.assertTrue(row['required'])
        self.assertEqual(row['id'], '5')

    def test_exempt_confirmed_schedule_does_not_become_required_after_stage_change(self):
        exhibit = DefenseStage.objects.create(label='Showcase', minutes_required=False)
        self.make_schedule(exhibit)
        exhibit.minutes_required = True
        exhibit.save()
        self.assertIsNone(stage_minutes_requirement(self.team, exhibit))

    def test_student_cannot_upload_file_to_complete_signed_minutes(self):
        with self.assertRaises(PermissionError):
            upsert_submission(self.team, self.stage.label, '5', 'fake.pdf', '1 KB', self.student)
        self.assertFalse(DeliverableSubmission.objects.filter(team=self.team, deliverable_id='5').exists())

    def test_draft_and_partial_signatures_do_not_complete_requirement(self):
        self.assertFalse(stage_minutes_requirement(self.team, self.stage)['completed'])
        self.minutes.status = DefenseMinutes.STATUS_COMPLETED
        self.minutes.pdf_file.save('unsigned.pdf', ContentFile(b'%PDF'), save=False)
        self.minutes.save()
        self.assertFalse(minutes_complete(self.minutes))

    def test_finalization_automatically_fulfills_stage_checklist(self):
        self.finalize()
        payload = stage_payload(self.team, self.stage.label, evaluator=self.student)
        self.assertTrue(payload['documentation_complete'])
        self.assertEqual(payload['system'][0]['id'], '5')
        self.assertEqual(payload['deliverables_completed'], 1)
        self.assertFalse(DeliverableSubmission.objects.filter(team=self.team).exists())

    def test_concept_minutes_do_not_fulfill_proposal_requirement(self):
        self.finalize()
        proposal = DefenseStage.objects.create(label='Proposal', minutes_required=True, minutes_deliverable_id='12')
        self.assertFalse(stage_minutes_requirement(self.team, proposal)['completed'])

    def test_previous_attempt_does_not_fulfill_latest_attempt(self):
        self.finalize()
        self.make_schedule(self.stage, scheduled_date=date(2026, 10, 9))
        row = stage_minutes_requirement(self.team, self.stage)
        self.assertFalse(row['completed'])
        self.assertTrue(any(r['completed'] for r in row['records']))

    def test_preview_is_read_only_and_uses_stage_and_individual_proponents(self):
        self.client.force_authenticate(self.doc)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.pk}/preview/')
        self.assertEqual(response.status_code, 200)
        text = '\n'.join(page.extract_text() for page in pdfplumber.open(BytesIO(response.content)).pages)
        self.assertIn('DRAFT PREVIEW', text)
        self.assertIn('CONCEPT PROPOSAL', text)
        self.assertIn('Alex Rivera', text)
        self.assertNotIn('All panelists endorsed', text)
        self.minutes.refresh_from_db()
        self.assertEqual(self.minutes.status, 'draft')
        self.assertFalse(self.minutes.pdf_file)

    def test_long_comments_paginate(self):
        self.comment.comments = 'Detailed sensor calibration recommendation. ' * 900
        self.comment.save()
        self.client.force_authenticate(self.doc)
        response = self.client.get(f'/api/defense/minutes/{self.schedule.pk}/preview/')
        self.assertEqual(response.status_code, 200)
        document = pdfplumber.open(BytesIO(response.content))
        self.assertGreater(len(document.pages), 1)
        for page in document.pages:
            self.assertLessEqual(page.extract_text().count('PANELIST COMMENTS / SUGGESTIONS'), 1)
        text = '\n'.join(page.extract_text() for page in document.pages)
        self.assertEqual(text.count('Detailed sensor calibration recommendation.'), 900)

    def test_students_can_only_access_own_final_pdf(self):
        self.client.force_authenticate(self.student)
        self.assertEqual(self.client.get(f'/api/defense/minutes/{self.schedule.pk}/preview/').status_code, 403)
        self.assertEqual(self.client.get(f'/api/defense/minutes/{self.schedule.pk}/pdf/').status_code, 400)
        self.finalize()
        self.assertEqual(self.client.get(f'/api/defense/minutes/{self.schedule.pk}/pdf/').status_code, 200)
        self.client.force_authenticate(self.outsider)
        self.assertEqual(self.client.get(f'/api/defense/minutes/{self.schedule.pk}/pdf/').status_code, 403)

    def test_duplicate_deliverable_number_is_rejected(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post('/api/defense/stages/', {'label': 'Duplicate stage', 'minutes_required': True, 'minutes_deliverable_id': '5', 'deliverables': [{'deliverable_id': '5', 'label': 'Student document'}]}, format='json')
        self.assertEqual(response.status_code, 400)

    def test_final_minutes_are_visible_in_admin_archive_and_team_stage_view(self):
        self.finalize()
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/repository/audit/', {'type': 'capstone'})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(any(entry.get('source') == 'defense_minutes' for entry in response.data['entries']))
        response = self.client.get('/api/repository/audit/', {'type': 'capstone', 'team_id': self.team.pk, 'stage': self.stage.label, 'view': 'team'})
        self.assertEqual(response.status_code, 200, response.data)
        rows = [entry for group in response.data['grouped_by_stage'] for entry in group['post']]
        self.assertTrue(any(entry.get('source') == 'defense_minutes' for entry in rows))

    def test_archive_links_original_pdf_and_preserves_amended_signed_version(self):
        self.finalize()
        entries = signed_minutes_archive_entries()
        self.assertEqual(len(entries), 1)
        self.assertTrue(entries[0]['is_restricted_archive'])
        self.assertFalse(entries[0]['can_override'])
        self.assertEqual(entries[0]['file_url'], f'/api/defense/minutes/{self.schedule.pk}/pdf/')
        revision = DefenseMinutesRevision.objects.create(minutes=self.minutes, snapshot={'project_title': self.minutes.project_title}, pdf_file=self.minutes.pdf_file.name, reason='Correction', actor=self.admin)
        self.minutes.status = 'draft'
        self.minutes.pdf_file = None
        self.minutes.save()
        self.assertFalse(stage_minutes_requirement(self.team, self.stage)['completed'])
        entries = signed_minutes_archive_entries()
        self.assertEqual(len(entries), 1)
        self.assertIn(f'revision_id={revision.pk}', entries[0]['file_url'])
