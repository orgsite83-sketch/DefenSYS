from importlib import import_module
from tempfile import TemporaryDirectory
from unittest.mock import patch

from django.apps import apps
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from authentication_access_control.audit import filter_audit_logs
from authentication_access_control.models import SystemAuditLog
from defense.stages.models import DefenseStage, StageDeliverable, StageGradingConfig
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from repository.project_archive.models import ProjectArchiveLog
from student_teams.models import StudentTeam, TeamMembership, TeamStageProgress


class ApprovedFileReplacementTests(APITestCase):
    def test_preserved_file_history_keeps_its_original_upload_time(self):
        from datetime import timedelta
        from django.utils import timezone
        original_time = timezone.now() - timedelta(days=7)
        DeliverableSubmissionFile.objects.filter(pk=self.sub_file.pk).update(uploaded_at=original_time)
        self.assertEqual(self.unlock().status_code, 200)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload().status_code, 200)
        historical = self.submission.files.get(is_current=False)
        self.assertEqual(historical.uploaded_at, original_time)

    def setUp(self):
        media = TemporaryDirectory(prefix='defensys-replacement-test-')
        self.addCleanup(media.cleanup)
        settings = override_settings(MEDIA_ROOT=media.name)
        settings.enable()
        self.addCleanup(settings.disable)
        User = get_user_model()
        self.admin = User.objects.create_user(username='replacement-admin', role='admin')
        self.student = User.objects.create_user(username='replacement-student', role='student')
        self.outsider = User.objects.create_user(username='replacement-outsider', role='student')
        self.adviser = User.objects.create_user(username='replacement-adviser', role='faculty', is_adviser=True)
        school_year = SchoolYear.objects.create(label='2026-2027')
        self.semester = Semester.objects.create(school_year=school_year, label=Semester.FIRST, is_active=True)
        self.stage = DefenseStage.objects.get(label='Concept Proposal')
        StageDeliverable.objects.filter(defense_stage=self.stage).delete()
        for deliverable_id in ('D1', 'D2'):
            StageDeliverable.objects.create(
                defense_stage=self.stage, deliverable_id=deliverable_id,
                label=f'Acceptance {deliverable_id}', deliverable_type='pre', required=True,
            )
        StageGradingConfig.objects.create(
            defense_stage=self.stage, semester=self.semester, is_officially_complete=True,
        )
        self.team = StudentTeam.objects.create(
            name='Replacement Team', project_title='Approved Project', semester=self.semester,
            level=StudentTeam.LEVEL_3_CAPSTONE, year_level='3rd Year', leader=self.student,
            ready_for_stage=self.stage.label, adviser=self.adviser,
        )
        TeamMembership.objects.create(team=self.team, student=self.student, is_leader=True)
        self.submission = DeliverableSubmission.objects.create(
            team=self.team, stage_label=self.stage.label, deliverable_id='D1',
            label='Acceptance D1', deliverable_type='pre', required=True,
            status='accepted', feedback='Original review feedback', reviewed_by=self.admin,
            file_name='wrong.pdf', uploaded_by=self.student,
        )
        self.sub_file = DeliverableSubmissionFile.objects.create(submission=self.submission, file_name='wrong.pdf')
        self.other_submission = DeliverableSubmission.objects.create(
            team=self.team, stage_label=self.stage.label, deliverable_id='D2',
            label='Acceptance D2', deliverable_type='pre', status='accepted', file_name='other.pdf',
        )
        self.entry_id = f'capstone-{self.submission.pk}-{self.sub_file.pk}'
        self.reason = 'The team uploaded an unsigned form instead of the signed form.'

    def unlock(self, **overrides):
        self.client.force_authenticate(self.admin)
        payload = {'entry_id': self.entry_id, 'status': 'Approved', 'feedback': self.reason, **overrides}
        return self.client.post('/api/repository/audit/request-resubmission/', payload, format='json')

    def upload(self, deliverable_id='D1', filename='signed.pdf'):
        return self.client.post('/api/repository/deliverables/upload/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label,
            'deliverable_id': deliverable_id, 'file_name': filename,
            'file': SimpleUploadedFile(filename, b'%PDF-1.4\nreplacement', content_type='application/pdf'),
        }, format='multipart')

    def cancel(self, **overrides):
        return self.client.post('/api/repository/audit/cancel-file-replacement/', {
            'entry_id': self.entry_id, 'reason': 'The uploaded form is already correct.', **overrides,
        }, format='json')

    def test_cancel_replacement_preserves_approval_and_review_and_blocks_upload(self):
        self.assertEqual(self.unlock().status_code, 200)
        self.other_submission.file_replacement_unlocked = True
        self.other_submission.save(update_fields=['file_replacement_unlocked'])
        original_reviewed_at = self.submission.reviewed_at
        response = self.cancel()
        self.assertEqual(response.status_code, 200, response.data)
        self.submission.refresh_from_db()
        self.other_submission.refresh_from_db()
        self.sub_file.refresh_from_db()
        self.assertEqual(self.submission.status, 'accepted')
        self.assertEqual(self.submission.feedback, 'Original review feedback')
        self.assertEqual(self.submission.reviewed_by, self.admin)
        self.assertEqual(self.submission.reviewed_at, original_reviewed_at)
        self.assertEqual(self.submission.file_name, 'wrong.pdf')
        self.assertEqual(self.sub_file.file_name, 'wrong.pdf')
        self.assertFalse(self.submission.file_replacement_unlocked)
        self.assertEqual(self.submission.file_replacement_reason, '')
        self.assertTrue(self.other_submission.file_replacement_unlocked)
        entry = next(item for item in response.data['entries'] if item['id'] == self.entry_id)
        self.assertEqual(entry['status'], 'Approved')
        self.assertFalse(entry['file_replacement_unlocked'])
        event = filter_audit_logs(SystemAuditLog.objects.all(), {
            'track': 'capstone', 'action': 'repository.file_replacement_cancel',
        }).get()
        self.assertEqual(event.actor, self.admin)
        self.assertEqual(event.reason, 'The uploaded form is already correct.')
        self.assertTrue(event.old_values['file_replacement_unlocked'])
        self.assertFalse(event.new_values['file_replacement_unlocked'])
        self.assertEqual(event.new_values['status'], 'accepted')
        self.assertIn(event.reason, ProjectArchiveLog.objects.order_by('-id').first().message)
        self.client.force_authenticate(self.student)
        student = self.client.get('/api/repository/deliverables/', {'stage_label': self.stage.label})
        item = next(item for item in student.data['teams'][0]['selected_stage']['deliverables'] if item['id'] == 'D1')
        self.assertFalse(item['can_upload'])
        self.assertEqual(self.upload().status_code, 400)

    def test_cancel_needs_reason_and_active_unlock(self):
        self.assertEqual(self.unlock().status_code, 200)
        for reason in ('', '   ', None, ['invalid']):
            response = self.cancel(reason=reason)
            self.assertEqual(response.status_code, 400, response.data)
        self.submission.refresh_from_db()
        self.assertTrue(self.submission.file_replacement_unlocked)
        self.assertEqual(self.cancel().status_code, 200)
        self.assertEqual(self.cancel().status_code, 400)
        self.assertEqual(SystemAuditLog.objects.filter(action='repository.file_replacement_cancel').count(), 1)

    def test_cancel_after_upload_cannot_undo_student_replacement(self):
        self.assertEqual(self.unlock().status_code, 200)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload().status_code, 200)
        self.client.force_authenticate(self.admin)
        self.assertEqual(self.cancel().status_code, 400)
        self.submission.refresh_from_db()
        self.sub_file.refresh_from_db()
        self.assertEqual(self.submission.status, 'accepted')
        self.assertEqual(self.submission.file_name, 'signed.pdf')
        self.assertEqual(self.sub_file.file_name, 'signed.pdf')
        self.assertFalse(SystemAuditLog.objects.filter(action='repository.file_replacement_cancel').exists())

    def test_students_advisers_and_pit_leads_cannot_cancel_capstone_unlocks(self):
        self.assertEqual(self.unlock().status_code, 200)
        lead = get_user_model().objects.create_user(username='cancel-lead', role='faculty', is_pit_lead=True, pit_lead_year='3rd Year')
        for actor in (self.student, self.outsider, self.adviser, lead):
            self.client.force_authenticate(actor)
            response = self.cancel()
            self.assertEqual(response.status_code, 403, response.data)
        self.submission.refresh_from_db()
        self.assertTrue(self.submission.file_replacement_unlocked)

    def test_pit_lead_can_cancel_only_their_assigned_year(self):
        lead = get_user_model().objects.create_user(username='cancel-lead', role='faculty', is_pit_lead=True, pit_lead_year='3rd Year')
        self.team.level = StudentTeam.LEVEL_3_PIT
        self.team.save(update_fields=['level'])
        self.entry_id = f'pit-deliverable-{self.submission.pk}-{self.sub_file.pk}'
        self.assertEqual(self.unlock().status_code, 200)
        self.client.force_authenticate(lead)
        self.assertEqual(self.cancel().status_code, 200)
        event = filter_audit_logs(SystemAuditLog.objects.all(), {
            'track': 'pit', 'year_level': '3rd Year', 'action': 'repository.file_replacement_cancel',
        }).get()
        self.assertEqual(event.actor, lead)
        self.assertEqual(self.unlock().status_code, 200)
        for assigned_year in ('2nd Year', ''):
            lead.pit_lead_year = assigned_year
            lead.save(update_fields=['pit_lead_year'])
            self.client.force_authenticate(lead)
            self.assertEqual(self.cancel().status_code, 403)
        self.submission.refresh_from_db()
        self.assertTrue(self.submission.file_replacement_unlocked)

    def test_cancel_audit_failure_restores_permission(self):
        self.assertEqual(self.unlock().status_code, 200)
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('test audit unavailable')):
            with self.assertLogs('authentication_access_control.audit', level='ERROR'):
                response = self.cancel()
        self.assertEqual(response.status_code, 500)
        self.submission.refresh_from_db()
        self.assertTrue(self.submission.file_replacement_unlocked)
        self.assertEqual(self.submission.file_replacement_reason, self.reason)
        self.assertEqual(ProjectArchiveLog.objects.count(), 1)

    def test_cancel_does_not_change_choice_a_revision_or_post_file(self):
        self.assertEqual(self.unlock(status='Needs Revision').status_code, 200)
        self.assertEqual(self.cancel().status_code, 400)
        self.submission.refresh_from_db()
        self.assertEqual(self.submission.status, 'rejected')
        self.assertTrue(self.submission.revision_review_unlocked)
        self.submission.status = 'accepted'
        self.submission.deliverable_type = 'post'
        self.submission.save(update_fields=['status', 'deliverable_type'])
        self.assertEqual(self.cancel().status_code, 400)
        self.assertFalse(SystemAuditLog.objects.filter(action='repository.file_replacement_cancel').exists())

    def test_choice_b_unlocks_only_target_and_preserves_review(self):
        response = self.unlock()
        self.assertEqual(response.status_code, 200, response.data)
        self.submission.refresh_from_db()
        self.assertEqual(self.submission.status, 'accepted')
        self.assertTrue(self.submission.file_replacement_unlocked)
        self.assertEqual(self.submission.file_replacement_reason, self.reason)
        self.assertEqual(self.submission.feedback, 'Original review feedback')
        self.assertEqual(self.submission.reviewed_by, self.admin)
        self.other_submission.refresh_from_db()
        self.assertFalse(self.other_submission.file_replacement_unlocked)
        self.team.refresh_from_db()
        self.assertEqual(self.team.unlocked_stages, [])
        entry = next(item for item in response.data['entries'] if item['id'] == self.entry_id)
        self.assertTrue(entry['file_replacement_unlocked'])
        self.assertEqual(entry['status'], 'Approved')
        self.client.force_authenticate(self.student)
        student = self.client.get('/api/repository/deliverables/', {'stage_label': self.stage.label})
        item = next(item for item in student.data['teams'][0]['selected_stage']['deliverables'] if item['id'] == 'D1')
        self.assertTrue(item['submission']['file_replacement_unlocked'])
        self.assertEqual(item['submission']['file_replacement_reason'], self.reason)

    def test_replacement_in_completed_stage_keeps_approval_and_consumes_unlock(self):
        self.assertEqual(self.unlock().status_code, 200)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload(deliverable_id='D2').status_code, 400)
        removal = self.client.post('/api/repository/deliverables/remove/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label, 'deliverable_id': 'D1',
        })
        self.assertEqual(removal.status_code, 400)
        uploaded = self.upload()
        self.assertEqual(uploaded.status_code, 200, uploaded.data)
        self.submission.refresh_from_db()
        self.sub_file.refresh_from_db()
        self.assertEqual(self.submission.status, 'accepted')
        self.assertEqual(self.submission.file_name, 'signed.pdf')
        self.assertEqual(self.sub_file.file_name, 'signed.pdf')
        self.assertFalse(self.submission.file_replacement_unlocked)
        self.assertEqual(self.submission.feedback, 'Original review feedback')
        self.assertEqual(self.upload(filename='again.pdf').status_code, 400)
        event = SystemAuditLog.objects.get(action='repository.student_file_replace')
        self.assertEqual(event.actor, self.student)
        self.assertEqual(event.reason, self.reason)
        self.assertEqual(event.old_values['file_name'], 'wrong.pdf')
        self.assertEqual(event.new_values['file_name'], 'signed.pdf')
        self.assertEqual(event.new_values['status'], 'accepted')

    def test_unlock_audit_is_visible_with_capstone_filter_and_reason(self):
        self.assertEqual(self.unlock().status_code, 200)
        event = filter_audit_logs(SystemAuditLog.objects.all(), {
            'track': 'capstone', 'action': 'repository.file_replacement_unlock',
        }).get()
        self.assertEqual(event.actor, self.admin)
        self.assertEqual(event.reason, self.reason)
        self.assertFalse(event.old_values['file_replacement_unlocked'])
        self.assertTrue(event.new_values['file_replacement_unlocked'])
        self.assertEqual(event.new_values['status'], 'accepted')
        self.assertEqual(event.new_values['team_id'], self.team.pk)
        self.assertEqual(event.new_values['stage_label'], self.stage.label)
        self.assertIn(self.reason, ProjectArchiveLog.objects.get().message)
        register = self.client.get('/api/audit-logs/', {'track': 'capstone'})
        self.assertEqual(register.status_code, 200, register.data)
        self.assertEqual(register.data['count'], 1)
        self.assertEqual(register.data['audit_logs'][0]['reason'], self.reason)

    def test_blank_or_invalid_reason_cannot_unlock(self):
        for reason in ('', '   ', ['invalid']):
            response = self.unlock(feedback=reason)
            self.assertEqual(response.status_code, 400, response.data)
        self.submission.refresh_from_db()
        self.assertFalse(self.submission.file_replacement_unlocked)
        self.assertFalse(SystemAuditLog.objects.exists())

    def test_choice_a_requires_reason(self):
        self.assertEqual(self.unlock(status='Needs Revision', feedback='   ').status_code, 400)
        self.submission.refresh_from_db()
        self.assertEqual(self.submission.status, 'accepted')
        self.assertFalse(self.submission.revision_review_unlocked)
        self.assertFalse(SystemAuditLog.objects.exists())

    def test_unlock_cannot_approve_pending_or_post_defense_files(self):
        for status, deliverable_type in [('pending', 'pre'), ('accepted', 'post')]:
            self.submission.status = status
            self.submission.deliverable_type = deliverable_type
            self.submission.save(update_fields=['status', 'deliverable_type'])
            self.assertEqual(self.unlock().status_code, 400)
        self.assertFalse(SystemAuditLog.objects.exists())

    def test_nonmember_cannot_use_unlocked_slot(self):
        self.assertEqual(self.unlock().status_code, 200)
        self.client.force_authenticate(self.outsider)
        self.assertEqual(self.upload().status_code, 404)
        self.submission.refresh_from_db()
        self.assertTrue(self.submission.file_replacement_unlocked)

    def test_choice_a_reopens_completed_stage_for_revision_and_new_review(self):
        TeamStageProgress.objects.update_or_create(
            team=self.team, semester=self.semester, defense_stage=self.stage,
            defaults={'status': TeamStageProgress.STATUS_PASSED},
        )
        self.assertEqual(self.unlock(status='Needs Revision').status_code, 200)
        self.submission.refresh_from_db()
        self.assertEqual(self.submission.status, 'rejected')
        self.assertFalse(self.submission.file_replacement_unlocked)
        self.assertTrue(self.submission.revision_review_unlocked)
        self.client.force_authenticate(self.student)
        uploaded = self.upload()
        self.assertEqual(uploaded.status_code, 200, uploaded.data)
        self.submission.refresh_from_db()
        self.assertEqual(self.submission.status, 'pending')
        self.assertTrue(self.submission.revision_review_unlocked)
        event = SystemAuditLog.objects.get(action='repository.request_resubmission')
        self.assertEqual(event.reason, self.reason)
        self.client.force_authenticate(self.adviser)
        faculty_payload = self.client.get('/api/repository/deliverables/', {'stage_label': self.stage.label})
        items = {item['id']: item for item in faculty_payload.data['teams'][0]['selected_stage']['deliverables']}
        self.assertTrue(items['D1']['can_faculty_review'])
        self.assertFalse(items['D2']['can_faculty_review'])
        rejected = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label,
            'deliverable_id': 'D1', 'status': 'rejected', 'feedback': 'One correction still needed.',
        })
        self.assertEqual(rejected.status_code, 200, rejected.data)
        self.assertEqual(TeamStageProgress.objects.get(
            team=self.team, semester=self.semester, defense_stage=self.stage,
        ).status, TeamStageProgress.STATUS_PASSED)
        self.client.force_authenticate(self.student)
        self.assertEqual(self.upload(filename='signed-corrected.pdf').status_code, 200)
        self.client.force_authenticate(self.adviser)
        reviewed = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label,
            'deliverable_id': 'D1', 'status': 'accepted',
        }, format='json')
        self.assertEqual(reviewed.status_code, 200, reviewed.data)
        self.submission.refresh_from_db()
        self.assertEqual(self.submission.status, 'accepted')
        self.assertFalse(self.submission.revision_review_unlocked)
        self.assertEqual(self.submission.reviewed_by, self.adviser)
        blocked = self.client.post('/api/repository/deliverables/review/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label,
            'deliverable_id': 'D1', 'status': 'rejected', 'feedback': 'Another change',
        })
        self.assertEqual(blocked.status_code, 403)

    def test_audit_failure_rolls_back_unlock(self):
        with patch('authentication_access_control.audit.SystemAuditLog.objects.create', side_effect=RuntimeError('test audit unavailable')):
            with self.assertLogs('authentication_access_control.audit', level='ERROR'):
                response = self.unlock()
        self.assertEqual(response.status_code, 500)
        self.submission.refresh_from_db()
        self.assertFalse(self.submission.file_replacement_unlocked)
        self.assertFalse(ProjectArchiveLog.objects.exists())

    def test_legacy_remarks_unlock_and_filtered_audit_are_restored(self):
        self.submission.feedback = 'Remarks by admin (Admin): Unlocked for file replacement by Admin'
        self.submission.save(update_fields=['feedback'])
        event = SystemAuditLog.objects.create(
            category='repository', action='repository.request_resubmission',
            target_type='DeliverableSubmission', target_id=str(self.submission.pk),
            actor=self.admin, old_values={'status': 'accepted'},
            new_values={'status': 'Approved', 'feedback': self.submission.feedback}, reason='Original recorded reason',
        )
        migration = import_module('repository.migrations.0018_deliverable_file_replacement')
        migration.restore_legacy_requests(apps, type('SchemaEditor', (), {'connection': connection})())
        self.submission.refresh_from_db()
        self.assertTrue(self.submission.file_replacement_unlocked)
        self.assertEqual(filter_audit_logs(SystemAuditLog.objects.all(), {'track': 'capstone'}).get().pk, event.pk)
        event.refresh_from_db()
        self.assertEqual(event.reason, 'Original recorded reason')
