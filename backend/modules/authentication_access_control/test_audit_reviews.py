from datetime import timedelta
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from .models import SystemAuditLog, SystemAuditReview


class AuditReviewWorkflowTests(APITestCase):
    def setUp(self):
        users = get_user_model()
        self.admin = users.objects.create_user(username='audit-admin', role='admin', first_name='Admin')
        self.lead = users.objects.create_user(
            username='pit-reviewer', role='faculty', is_pit_lead=True,
            pit_lead_year='1st Year', first_name='Ricardo', last_name='Fontanilla',
        )
        self.log = self.make_log()

    def make_log(self, track='pit', year='1st Year', review_status='needs_review'):
        return SystemAuditLog.objects.create(
            actor=self.admin, action='repository.archive_upload',
            category=SystemAuditLog.CATEGORY_REPOSITORY, target_type='VaultEntry', target_id='1',
            new_values={'entry_type': track, 'year_level': year} if track else {},
            reason='Original action reason.', review_status=review_status,
        )

    def review(self, user=None, status='reviewed', reason=None, log=None):
        self.client.force_authenticate(user=user or self.lead)
        return self.client.patch(
            f'/api/audit-logs/{(log or self.log).pk}/review/',
            {'review_status': status, **({'reason': reason} if reason is not None else {})},
            format='json',
        )

    def test_lead_review_is_visible_to_admin_with_identity_and_history(self):
        response = self.review(reason='Evidence verified.')
        self.assertEqual(response.status_code, 200)
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/audit-logs/')
        record = response.data['audit_logs'][0]
        self.assertEqual(record['review_status'], 'reviewed')
        self.assertEqual(record['actor'], self.admin.pk)
        self.assertEqual(record['reason'], 'Original action reason.')
        self.assertEqual(record['reviewed_by'], self.lead.pk)
        self.assertEqual(record['reviewed_by_name'], 'Ricardo Fontanilla')
        self.assertEqual(record['reviewed_by_role'], 'pit_lead')
        self.assertEqual(record['reviewed_by_year'], '1st Year')
        self.assertIsNotNone(record['reviewed_at'])
        self.assertEqual(record['review_history'][0]['reason'], 'Evidence verified.')
        self.assertEqual(response.data['counts']['reviewed'], 1)

    def test_review_retry_preserves_original_reviewer(self):
        self.assertEqual(self.review().status_code, 200)
        reviewed_at = SystemAuditLog.objects.get(pk=self.log.pk).reviewed_at
        self.assertEqual(self.review(user=self.admin).status_code, 200)
        self.log.refresh_from_db()
        self.assertEqual(self.log.reviewed_by, self.lead)
        self.assertEqual(self.log.reviewed_at, reviewed_at)
        self.assertEqual(self.log.reviews.count(), 1)

    def test_reopen_requires_reason_and_retains_prior_review(self):
        self.review()
        self.assertEqual(self.review(user=self.admin, status='needs_review').status_code, 400)
        self.assertEqual(self.review(user=self.admin, status='needs_review', reason='  ').status_code, 400)
        self.log.refresh_from_db()
        self.assertEqual(self.log.review_status, 'reviewed')
        self.assertEqual(self.log.reviews.count(), 1)
        self.assertEqual(self.review(user=self.admin, status='needs_review', reason='Missing evidence.').status_code, 200)
        self.log.refresh_from_db()
        self.assertEqual(self.log.review_status, 'needs_review')
        self.assertEqual(self.log.reviewed_by, self.lead)
        self.assertEqual(self.log.reviews.first().reason, 'Missing evidence.')
        self.assertEqual(self.log.reviews.first().reviewer_role, 'admin')
        self.assertEqual(self.log.reason, 'Original action reason.')
        self.assertEqual(self.review(user=self.admin).status_code, 200)
        self.log.refresh_from_db()
        self.assertEqual(self.log.reviewed_by, self.admin)
        self.assertEqual(self.log.reviews.count(), 3)

    def test_pit_lead_cannot_review_other_years_capstone_or_mixed_changes(self):
        other_year = self.make_log(year='2nd Year')
        capstone = self.make_log(track='capstone')
        mixed = self.make_log()
        mixed.old_values = {'entry_type': 'pit', 'year_level': '2nd Year'}
        mixed.save(update_fields=['old_values'])
        for log in (other_year, capstone, mixed):
            with self.subTest(log=log.pk):
                self.assertEqual(self.review(log=log).status_code, 404)
                log.refresh_from_db()
                self.assertEqual(log.review_status, 'needs_review')
                self.assertEqual(log.reviews.count(), 0)

    def test_unassigned_lead_and_ordinary_faculty_cannot_review(self):
        self.lead.pit_lead_year = ''
        self.lead.save(update_fields=['pit_lead_year'])
        self.assertEqual(self.review().status_code, 403)
        self.lead.is_pit_lead = False
        self.lead.save(update_fields=['is_pit_lead'])
        self.assertEqual(self.review().status_code, 403)

    def test_invalid_status_and_non_text_inputs_do_not_write_history(self):
        for payload in ({'review_status': 'invalid'}, {'review_status': None}, {'reason': ['invalid']}):
            self.client.force_authenticate(self.lead)
            self.assertEqual(self.client.patch(
                f'/api/audit-logs/{self.log.pk}/review/', payload, format='json',
            ).status_code, 400)
        self.assertEqual(SystemAuditReview.objects.count(), 0)

    def test_identity_snapshots_survive_account_rename_and_deletion(self):
        self.review()
        self.lead.first_name = 'Changed'
        self.lead.save(update_fields=['first_name'])
        self.lead.delete()
        self.log.refresh_from_db()
        self.assertIsNone(self.log.reviewed_by)
        self.assertEqual(self.log.reviewed_by_name, 'Ricardo Fontanilla')
        self.assertEqual(self.log.reviews.first().reviewer_name, 'Ricardo Fontanilla')

    def test_pit_progress_in_capstone_view_tracks_pending_lead_admin_and_overdue(self):
        self.review()
        admin_review = self.make_log()
        self.review(user=self.admin, log=admin_review)
        pending = self.make_log(review_status='captured')
        SystemAuditLog.objects.filter(pk=pending.pk).update(created_at=timezone.now() - timedelta(days=8))
        capstone = self.make_log(track='capstone')
        self.make_log(year='2nd Year', review_status='requires_reason')
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/audit-logs/', {'track': 'capstone'})
        self.assertEqual([row['id'] for row in response.data['audit_logs']], [capstone.pk])
        self.assertEqual(response.data['capstone_progress']['total'], 1)
        self.assertEqual(response.data['capstone_progress']['pending'], 1)
        first_year = next(row for row in response.data['pit_progress'] if row['year_level'] == '1st Year')
        self.assertEqual(first_year['total'], 3)
        self.assertEqual(first_year['reviewed'], 2)
        self.assertEqual(first_year['reviewed_by_lead'], 1)
        self.assertEqual(first_year['pending'], 1)
        self.assertEqual(first_year['overdue'], 1)
        self.assertEqual(first_year['last_reviewed_role'], 'admin')
        self.assertEqual(first_year['leads'][0]['name'], 'Ricardo Fontanilla')
        self.client.force_authenticate(self.lead)
        response = self.client.get('/api/audit-logs/', {'track': 'capstone'})
        self.assertEqual([row['year_level'] for row in response.data['pit_progress']], ['1st Year'])
        self.assertIsNone(response.data['capstone_progress'])

    def test_capstone_progress_stays_visible_in_pit_view_and_obeys_shared_filters(self):
        capstone = self.make_log(track='capstone', review_status='reviewed')
        capstone.action = 'rubric.update'
        capstone.save(update_fields=['action'])
        excluded = self.make_log(track='capstone')
        excluded.action = 'rubric.create'
        excluded.save(update_fields=['action'])
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/audit-logs/', {
            'track': 'pit', 'action': 'rubric.update', 'review_status': 'needs_review',
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['audit_logs'], [])
        self.assertEqual(response.data['capstone_progress']['total'], 1)
        self.assertEqual(response.data['capstone_progress']['reviewed'], 1)
        self.assertEqual(response.data['capstone_progress']['pending'], 0)
        self.assertEqual(response.data['pit_progress'][0]['total'], 0)

    def test_reopening_restarts_overdue_clock(self):
        SystemAuditLog.objects.filter(pk=self.log.pk).update(created_at=timezone.now() - timedelta(days=30))
        self.review()
        self.review(user=self.admin, status='needs_review', reason='Recheck.')
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/audit-logs/')
        first_year = next(row for row in response.data['pit_progress'] if row['year_level'] == '1st Year')
        self.assertEqual(first_year['pending'], 1)
        self.assertEqual(first_year['overdue'], 0)

    def test_needs_review_includes_all_pending_states_and_counts_stay_stable(self):
        self.make_log(review_status='captured')
        self.make_log(review_status='requires_reason')
        self.make_log(review_status='reviewed')
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/audit-logs/', {'review_status': 'needs_review'})
        self.assertEqual(response.data['count'], 3)
        self.assertEqual(response.data['counts']['filtered'], 4)
        self.assertEqual(response.data['counts']['reviewed'], 1)
        self.assertEqual(response.data['counts']['needs_review'], 3)

    def test_capstone_filter_and_export_exclude_general_system_activity(self):
        capstone = self.make_log(track='capstone')
        general = self.make_log(track='')
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/audit-logs/', {'track': 'capstone'})
        self.assertEqual([row['id'] for row in response.data['audit_logs']], [capstone.pk])
        response = self.client.get('/api/audit-logs/', {'track': 'system'})
        self.assertEqual([row['id'] for row in response.data['audit_logs']], [general.pk])
        response = self.client.get('/api/reports/audit-trail/', {'track': 'capstone', 'export_format': 'json'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['rows']), 1)
        self.assertEqual(response.data['rows'][0]['target'], 'VaultEntry #1')

    def test_review_evidence_is_exported_in_preview_csv_and_pdf(self):
        self.lead.first_name = 'Ricardo & <Lead>'
        self.lead.save(update_fields=['first_name'])
        self.review(reason='Evidence & <notes> checked.')
        self.client.force_authenticate(self.admin)
        params = {'log_id': self.log.pk, 'export_format': 'json'}
        response = self.client.get('/api/reports/audit-trail/', params)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['rows'][0]['review_status'], 'Reviewed')
        self.assertIn('Ricardo & <Lead>', response.data['rows'][0]['reviewed_by'])
        self.assertIn('Evidence & <notes> checked.', response.data['rows'][0]['review_history'])
        response = self.client.get('/api/reports/audit-trail/', {**params, 'export_format': 'csv'})
        self.assertEqual(response.status_code, 200)
        self.assertIn(b'Reviewed By', response.content)
        self.assertIn(b'Ricardo & <Lead>', response.content)
        response = self.client.get('/api/reports/audit-trail/', {**params, 'export_format': 'pdf'})
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.content.startswith(b'%PDF'))

    def test_pdf_long_review_history_can_span_pages(self):
        note = 'Verified the evidence, attachment details and recorded PIT event. ' * 20
        for _ in range(8):
            self.assertEqual(self.review(reason=note).status_code, 200)
            self.assertEqual(self.review(user=self.admin, status='needs_review', reason=note).status_code, 200)
        self.client.force_authenticate(self.admin)
        response = self.client.get('/api/reports/audit-trail/', {'log_id': self.log.pk, 'export_format': 'pdf'})
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.content.startswith(b'%PDF'))
