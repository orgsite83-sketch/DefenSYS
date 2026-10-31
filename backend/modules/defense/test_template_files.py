"""Optional templates use isolated DB fixtures and disposable file storage."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.conf import settings as django_settings
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from defense.scheduler.models import PitEventGradingConfig, PitEventDeliverable
from defense.template_models import DeliverableTemplate
from defense.template_files import MAX_TEMPLATE_SIZE, template_map, template_metadata, validate_template_file
from repository.deliverables.models import DeliverableSubmission
from student_teams.models import StudentTeam, TeamMembership


class DeliverableTemplateTests(APITestCase):
    def setUp(self):
        media = TemporaryDirectory(prefix='defensys-template-test-')
        self.addCleanup(media.cleanup)
        self.media = Path(media.name)
        settings = override_settings(MEDIA_ROOT=media.name, STORAGES={
            **django_settings.STORAGES,
            'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage',
                        'OPTIONS': {'location': media.name}},
        })
        settings.enable()
        self.addCleanup(settings.disable)
        User = get_user_model()
        self.admin = User.objects.create_user(username='template-admin', role='admin')
        self.student = User.objects.create_user(username='template-student', role='student')
        self.member = User.objects.create_user(username='template-member', role='student')
        self.other = User.objects.create_user(username='template-other', role='student')
        self.first_lead = User.objects.create_user(username='template-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='1st Year')
        self.second_lead = User.objects.create_user(username='template-other-lead', role='faculty',
            is_pit_lead=True, pit_lead_year='2nd Year')
        self.semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2098-2099'),
            label=Semester.FIRST, is_active=True, starts_on='2000-01-01', ends_on='2199-12-31')
        self.client.force_authenticate(self.admin)
        self.stage = DefenseStage.objects.create(label='Template stage', setup_semester=self.semester)
        self.definition = StageDeliverable.objects.create(defense_stage=self.stage, deliverable_id='D1',
            label='Concept Paper', required=True, file_format='pdf')
        self.url = f'/api/defense/stages/{self.stage.pk}/'
        self.team = StudentTeam.objects.create(name='Template team', project_title='Template project',
            semester=self.semester, leader=self.student, level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year')
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        TeamMembership.objects.create(team=self.team, student=self.member)

    def change(self, number='D1', action='replace', scope='team', **extra):
        return {'scope': scope, 'deliverable_id': number, 'action': action,
            **({'upload_key': 'selected'} if action == 'replace' else {}), **extra}

    def save(self, payload=None, name='template.docx', data=b'editable original', url=None, method='patch'):
        body = {'configuration': json.dumps(payload or {'template_changes': [self.change()]})}
        if name is not None:
            body['selected'] = SimpleUploadedFile(name, data)
        return getattr(self.client, method)(url or self.url, body, format='multipart')

    def file_url(self, attachment=None):
        attachment = attachment or DeliverableTemplate.objects.get()
        return reverse('media_file_serve', kwargs={'file_path': attachment.file.name})

    def test_docx_template_for_pdf_requirement_and_json_edits_preserve_file(self):
        response = self.save()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['stage']['deliverables'][0]['template']['original_name'], 'template.docx')
        attachment = DeliverableTemplate.objects.get()
        self.definition.refresh_from_db()
        self.assertEqual(self.definition.file_format, 'pdf')
        self.assertFalse(DeliverableSubmission.objects.exists())
        response = self.client.patch(self.url, {'description': 'Ordinary edit'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(DeliverableTemplate.objects.get().file.name, attachment.file.name)

    def test_new_stage_saves_template_and_configuration_together(self):
        response = self.save({'label': 'New template stage', 'deliverables': [
            {'deliverable_id': 'D1', 'label': 'New paper', 'file_format': 'pdf'}],
            'template_changes': [self.change()]}, url='/api/defense/stages/', method='post')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(DeliverableTemplate.objects.get().defense_stage_id, response.data['stage']['id'])

    def test_image_template_and_read_access_for_non_leader_member(self):
        self.assertEqual(self.save(name='Poster.PNG', data=b'poster example').status_code, 200)
        self.client.force_authenticate(self.member)
        response = self.client.get(self.file_url())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b''.join(response.streaming_content), b'poster example')
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(self.file_url()).status_code, 404)

    def test_student_cannot_change_templates(self):
        self.client.force_authenticate(self.student)
        self.assertEqual(self.save().status_code, 403)
        self.assertFalse(DeliverableTemplate.objects.exists())

    def test_download_remains_readable_after_submission_acceptance(self):
        self.assertEqual(self.save().status_code, 200)
        submission = DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id='D1', label='Concept Paper', deliverable_type='pre', status='accepted')
        self.client.force_authenticate(self.student)
        before = list(DeliverableSubmission.objects.values())
        response = self.client.get(self.file_url())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b''.join(response.streaming_content), b'editable original')
        self.assertEqual(list(DeliverableSubmission.objects.values()), before)
        submission.refresh_from_db()
        self.assertEqual(submission.status, 'accepted')

    def test_used_requirement_cannot_replace_or_remove_template(self):
        self.assertEqual(self.save().status_code, 200)
        old = DeliverableTemplate.objects.get().file.name
        DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id='D1', label='Concept Paper', deliverable_type='pre')
        self.assertEqual(self.save(name='replacement.png').status_code, 400)
        response = self.client.patch(self.url, {'template_changes': [self.change(action='remove')]}, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(DeliverableTemplate.objects.get().file.name, old)

    def test_whole_configuration_lock_protects_templates(self):
        self.assertEqual(self.save().status_code, 200)
        StageGradingConfig.objects.create(defense_stage=self.stage, semester=self.semester, is_officially_complete=True)
        self.assertEqual(self.save(name='replacement.docx').status_code, 400)

    def test_replace_and_remove_cleanup_only_after_commit(self):
        self.assertEqual(self.save().status_code, 200)
        old = DeliverableTemplate.objects.get().file.name
        with self.captureOnCommitCallbacks(execute=True):
            self.assertEqual(self.save(name='replacement.mp4', data=b'video example').status_code, 200)
        self.assertFalse((self.media / old).exists())
        current = DeliverableTemplate.objects.get().file.name
        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.patch(self.url, {'template_changes': [self.change(action='remove')]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNone(response.data['stage']['deliverables'][0]['template'])
        self.assertFalse(DeliverableTemplate.objects.exists())
        self.assertFalse((self.media / current).exists())

    def test_invalid_second_file_rolls_back_configuration_and_all_files(self):
        before = self.stage.description
        changes = [self.change(), self.change(number='UNKNOWN')]
        response = self.save({'description': 'Must roll back', 'template_changes': changes})
        self.assertEqual(response.status_code, 400)
        self.stage.refresh_from_db()
        self.assertEqual(self.stage.description, before)
        self.assertFalse(DeliverableTemplate.objects.exists())
        self.assertEqual(list(self.media.rglob('*')), [])

    def test_late_failure_removes_new_file_and_preserves_old_file(self):
        self.assertEqual(self.save().status_code, 200)
        old = DeliverableTemplate.objects.get().file.name
        self.client.raise_request_exception = False
        with patch('authentication_access_control.audit.log_high_impact_action', side_effect=RuntimeError('audit failed')):
            response = self.save({'description': 'Must roll back', 'template_changes': [self.change()]}, name='new.docx')
        self.assertEqual(response.status_code, 500)
        self.assertEqual(DeliverableTemplate.objects.get().file.name, old)
        self.assertEqual([p.name for p in (self.media / 'deliverable_templates').iterdir()], [Path(old).name])

    def test_unknown_format_empty_and_oversized_are_rejected(self):
        for name, data in [('bad.exe', b'bad'), ('empty.pdf', b'')]:
            self.assertEqual(self.save(name=name, data=data).status_code, 400)
        file = SimpleUploadedFile('large.jpg', b'x')
        file.size = MAX_TEMPLATE_SIZE + 1
        from rest_framework.exceptions import ValidationError
        with self.assertRaises(ValidationError):
            validate_template_file(file)
        self.assertFalse(DeliverableTemplate.objects.exists())

    def test_renumber_and_reorder_keep_same_attachment(self):
        self.assertEqual(self.save().status_code, 200)
        attachment = DeliverableTemplate.objects.get()
        response = self.client.patch(self.url, {'deliverables': [{'id': self.definition.pk,
            'deliverable_id': 'D7', 'label': self.definition.label, 'file_format': 'pdf',
            'display_order': 2}]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        attachment.refresh_from_db()
        self.assertEqual(attachment.deliverable_id, 'D7')

    def test_foreign_context_attachment_cannot_be_rebound(self):
        self.assertEqual(self.save().status_code, 200)
        other = DefenseStage.objects.create(label='Other stage', setup_semester=self.semester)
        StageDeliverable.objects.create(defense_stage=other, deliverable_id='D1', label='Other')
        response = self.client.patch(f'/api/defense/stages/{other.pk}/', {'template_changes': [
            self.change(action='keep', source_id=DeliverableTemplate.objects.get().pk)]}, format='json')
        self.assertEqual(response.status_code, 400)

    def test_pm_only_and_linked_templates_use_correct_canonical_owner(self):
        self.stage.shared_deliverables = [{'deliverable_id': 'PM1', 'label': 'Shared paper', 'deliverable_type': 'pre'},
            {'deliverable_id': 'PM2', 'label': 'Concept Paper', 'deliverable_type': 'pre', 'team_deliverable_id': 'D1'}]
        self.stage.save()
        self.assertEqual(self.save({'template_changes': [self.change(number='PM1', scope='shared')]}).status_code, 200)
        self.assertEqual(self.save({'template_changes': [self.change(number='PM2', scope='shared')]}).status_code, 200)
        self.assertEqual(DeliverableTemplate.objects.count(), 2)
        self.assertEqual(template_metadata(self.stage, 'PM2', shared=True), template_metadata(self.stage, 'D1'))
        self.assertIsNotNone(template_metadata(self.stage, 'PM1', shared=True))

    def test_pit_save_and_year_permissions(self):
        self.client.force_authenticate(self.first_lead)
        data = {'event_name': 'Template PIT', 'year_level': '1st Year', 'semester_id': self.semester.pk,
            'panel_weight': 80, 'peer_weight': 20, 'deliverables': [{'deliverable_id': 'D1',
                'label': 'Poster', 'file_format': 'pdf'}], 'template_changes': [self.change()]}
        url = '/api/defense/schedules/pit-event-config/'
        response = self.save(data, url=url, method='post', name='Poster.jpg')
        self.assertEqual(response.status_code, 200, response.data)
        config = PitEventGradingConfig.objects.get(pk=response.data['config']['id'])
        self.assertEqual(response.data['config']['deliverables'][0]['template']['original_name'], 'Poster.jpg')
        self.assertEqual(PitEventDeliverable.objects.get(pit_event_config=config).file_format, 'pdf')
        self.client.force_authenticate(self.second_lead)
        data['config_id'] = config.pk
        self.assertEqual(self.save(data, url=url, method='post').status_code, 403)
        self.assertEqual(self.client.get(self.file_url()).status_code, 404)

    def test_projection_batches_attachment_queries(self):
        self.assertEqual(self.save().status_code, 200)
        from defensys_backend.read_projection import read_projection
        with read_projection(), self.assertNumQueries(1):
            for _ in range(10):
                self.assertIsNotNone(template_metadata(self.stage, 'D1'))
        self.assertEqual(len(template_map(self.stage)), 1)

    def test_shared_template_readable_to_linked_students_only(self):
        from student_teams.models import SectionAssignment
        self.team.section = '3A'
        self.team.save(update_fields=['section'])
        SectionAssignment.objects.create(semester=self.semester, section='3A', year_level='3rd Year',
            system_name='Shared Platform', project_manager=self.student)
        self.stage.shared_deliverables = [{'deliverable_id': 'PM1', 'label': 'Poster', 'deliverable_type': 'pre'}]
        self.stage.save()
        self.assertEqual(self.save({'template_changes': [self.change(number='PM1', scope='shared')]}).status_code, 200)
        self.client.force_authenticate(self.member)
        response = self.client.get(self.file_url())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(b''.join(response.streaming_content), b'editable original')
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(self.file_url()).status_code, 404)

    def test_other_semester_template_is_not_visible_by_matching_label(self):
        old_term = Semester.objects.create(school_year=self.semester.school_year, label=Semester.SECOND)
        old_stage = DefenseStage.objects.create(label=self.stage.label, setup_semester=old_term)
        StageDeliverable.objects.create(defense_stage=old_stage, deliverable_id='D1', label='Old paper')
        attachment = DeliverableTemplate.objects.create(defense_stage=old_stage, requirement_scope='team',
            deliverable_id='D1', file=SimpleUploadedFile('old.png', b'old template'),
            original_name='old.png', byte_size=12, uploaded_by=self.admin)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.client.get(self.file_url(attachment)).status_code, 404)

    def test_switching_submission_audience_preserves_template_file(self):
        self.assertEqual(self.save().status_code, 200)
        attachment = DeliverableTemplate.objects.get()
        original_file = attachment.file.name
        response = self.client.patch(self.url, {'deliverables': [], 'shared_deliverables': [
            {'deliverable_id': 'PM1', 'label': 'Concept Paper', 'deliverable_type': 'pre'}],
            'template_changes': [self.change(number='PM1', action='keep', scope='shared', source_id=attachment.pk)]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        attachment.refresh_from_db()
        self.assertEqual((attachment.requirement_scope, attachment.deliverable_id), ('shared', 'PM1'))
        self.assertEqual(attachment.file.name, original_file)

    def test_legacy_requirement_delete_cleans_up_its_attachment(self):
        self.assertEqual(self.save().status_code, 200)
        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.delete(f'{self.url}deliverables/{self.definition.pk}/')
        self.assertEqual(response.status_code, 204, response.data)
        self.assertFalse(DeliverableTemplate.objects.exists())

    def test_student_payload_exposes_template_without_polluting_definitions(self):
        self.assertEqual(self.save(name='Poster.png').status_code, 200)
        from repository.deliverables.services import stage_payload, get_deliverable_definitions_for_team
        self.assertNotIn('template', get_deliverable_definitions_for_team(self.team, self.stage.label)[0])
        payload = stage_payload(self.team, self.stage.label, evaluator=self.student)
        row = next(row for row in payload['deliverables'] if row['id'] == 'D1')
        self.assertEqual(row['template']['original_name'], 'Poster.png')

    def test_malformed_upload_key_is_a_validation_error(self):
        response = self.save({'template_changes': [self.change(upload_key=['selected'])]})
        self.assertEqual(response.status_code, 400)
        self.assertFalse(DeliverableTemplate.objects.exists())

    def test_keep_operation_does_not_report_a_template_change(self):
        self.assertEqual(self.save().status_code, 200)
        with patch('authentication_access_control.audit.log_high_impact_action') as audit:
            response = self.client.patch(self.url, {'template_changes': [self.change(
                action='keep', source_id=DeliverableTemplate.objects.get().pk)]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        audit.assert_not_called()
