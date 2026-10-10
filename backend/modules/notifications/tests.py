from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from notifications.models import Notification, NotificationCategory
from notifications.email_service import (
    _send,
    send_password_reset_email,
    send_password_changed_email,
    send_admin_password_reset_email,
)

User = get_user_model()


class NotificationAPITests(APITestCase):
    def setUp(self):
        self.user1 = User.objects.create_user(
            username='student1',
            email='student1@example.com',
            password='password123',
            role='student'
        )
        self.user2 = User.objects.create_user(
            username='student2',
            email='student2@example.com',
            password='password123',
            role='student'
        )
        self.notification1 = Notification.objects.create(
            recipient=self.user1,
            title='Test Title 1',
            message='Test Message 1',
            is_read=False
        )
        self.notification2 = Notification.objects.create(
            recipient=self.user1,
            title='Test Title 2',
            message='Test Message 2',
            is_read=True
        )
        self.notification_other = Notification.objects.create(
            recipient=self.user2,
            title='Other User Title',
            message='Other User Message',
            is_read=False
        )

    def test_list_notifications(self):
        self.client.force_authenticate(user=self.user1)
        url = reverse('notification_list')
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['notifications']), 2)
        self.assertEqual(response.data['unread_count'], 1)

    def test_mark_read(self):
        self.client.force_authenticate(user=self.user1)
        url = reverse('notification_read', kwargs={'pk': self.notification1.pk})
        response = self.client.post(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.notification1.refresh_from_db()
        self.assertTrue(self.notification1.is_read)

        # Marking an already read notification should be idempotent and return 200 OK
        response_repeat = self.client.post(url)
        self.assertEqual(response_repeat.status_code, status.HTTP_200_OK)

    def test_mark_read_denied_for_other_user(self):
        self.client.force_authenticate(user=self.user2)
        # Try to mark user1's notification as read
        url = reverse('notification_read', kwargs={'pk': self.notification1.pk})
        response = self.client.post(url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_mark_all_read(self):
        self.client.force_authenticate(user=self.user1)
        url = reverse('notification_read_all')
        response = self.client.post(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.notification1.refresh_from_db()
        self.notification2.refresh_from_db()
        self.assertTrue(self.notification1.is_read)
        self.assertTrue(self.notification2.is_read)
        # Other user's notification remains unread
        self.notification_other.refresh_from_db()
        self.assertFalse(self.notification_other.is_read)

    def test_list_notifications_pagination(self):
        # Create additional notifications to exceed default page_size of 20.
        # We already have 2 notifications from setUp.
        # Create 23 more notifications, so total is 25.
        for i in range(23):
            Notification.objects.create(
                recipient=self.user1,
                title=f'Test Title Extra {i}',
                message=f'Test Message Extra {i}',
                is_read=False
            )

        self.client.force_authenticate(user=self.user1)
        url = reverse('notification_list')
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # Verify paginated response structure keys
        self.assertIn('count', response.data)
        self.assertIn('next', response.data)
        self.assertIn('previous', response.data)
        self.assertIn('unread_count', response.data)
        self.assertIn('notifications', response.data)

        # Total count should be 25
        self.assertEqual(response.data['count'], 25)
        # First page should contain page_size (20) notifications
        self.assertEqual(len(response.data['notifications']), 20)
        # Next link should be present
        self.assertIsNotNone(response.data['next'])
        # Unread count should be 1 (from setup) + 23 = 24
        self.assertEqual(response.data['unread_count'], 24)

    def test_list_notifications_custom_page_size(self):
        self.client.force_authenticate(user=self.user1)
        url = reverse('notification_list')
        # Request with a custom page size of 1
        response = self.client.get(url, {'page_size': 1})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        # Should only return 1 notification on the page
        self.assertEqual(len(response.data['notifications']), 1)
        # But total count should still be 2 (from setup)
        self.assertEqual(response.data['count'], 2)


class NotificationWorkspaceTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='multi_role_notifications', role='faculty',
            is_adviser=True, is_panelist=True, is_documenter=True, is_pit_lead=True,
        )
        self.other = User.objects.create_user(username='other_notification_owner', role='faculty')
        self.alerts = {}
        for workspace in ('adviser', 'panelist', 'documenter', 'pit_lead', 'faculty', 'account'):
            self.alerts[workspace] = Notification.objects.create(
                recipient=self.user, title='Defense update', message='Same event, independent role inbox.',
                workspace=workspace,
            )
        self.client.force_authenticate(self.user)

    def test_list_and_badge_are_role_scoped(self):
        for workspace, alert in self.alerts.items():
            with self.subTest(workspace=workspace):
                response = self.client.get(reverse('notification_list'), {'workspace': workspace})
                self.assertEqual(response.status_code, 200)
                self.assertEqual([n['id'] for n in response.data['notifications']], [alert.pk])
                self.assertEqual(response.data['unread_count'], 1)
                self.assertEqual(response.data['total_count'], 1)
                self.assertEqual(response.data['notifications'][0]['workspace'], workspace)

    def test_mark_all_read_does_not_touch_other_roles_or_account(self):
        response = self.client.post(reverse('notification_read_all') + '?workspace=adviser')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['updated_count'], 1)
        for workspace, alert in self.alerts.items():
            alert.refresh_from_db()
            self.assertEqual(alert.is_read, workspace == 'adviser')

    def test_single_read_rejects_wrong_inbox_even_for_same_user(self):
        alert = self.alerts['panelist']
        url = reverse('notification_read', kwargs={'pk': alert.pk})
        self.assertEqual(self.client.post(url + '?workspace=adviser').status_code, 404)
        alert.refresh_from_db()
        self.assertFalse(alert.is_read)
        result = self.client.post(url + '?workspace=panelist')
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.data['unread_count'], 0)
        self.assertEqual(self.client.post(url + '?workspace=panelist').data['unread_count'], 0)
        self.alerts['adviser'].refresh_from_db()
        self.assertFalse(self.alerts['adviser'].is_read)

    def test_scope_does_not_bypass_recipient_boundary(self):
        self.client.force_authenticate(self.other)
        self.assertEqual(self.client.get(reverse('notification_list'), {'workspace': 'adviser'}).data['count'], 0)
        url = reverse('notification_read', kwargs={'pk': self.alerts['adviser'].pk})
        self.assertEqual(self.client.post(url + '?workspace=adviser').status_code, 404)
        self.client.post(reverse('notification_read_all') + '?workspace=adviser')
        self.alerts['adviser'].refresh_from_db()
        self.assertFalse(self.alerts['adviser'].is_read)

    def test_omitted_scope_defaults_to_base_workspace_never_all_inboxes(self):
        response = self.client.get(reverse('notification_list'))
        self.assertEqual([n['id'] for n in response.data['notifications']], [self.alerts['faculty'].pk])
        self.client.post(reverse('notification_read_all'))
        self.assertEqual(Notification.objects.filter(recipient=self.user, is_read=True).count(), 1)

    def test_invalid_scope_fails_without_reading_anything(self):
        self.assertEqual(self.client.get(reverse('notification_list'), {'workspace': 'unknown'}).status_code, 400)
        self.assertEqual(self.client.post(reverse('notification_read_all') + '?workspace=unknown').status_code, 400)
        self.assertFalse(Notification.objects.filter(recipient=self.user, is_read=True).exists())

    def test_unread_filter_uses_entire_inbox_and_pagination(self):
        Notification.objects.bulk_create([
            Notification(recipient=self.user, workspace='adviser', title=f'Older {i}', message='Review required.')
            for i in range(24)
        ])
        response = self.client.get(reverse('notification_list'), {'workspace': 'adviser', 'unread': 'true'})
        self.assertEqual(response.data['count'], 25)
        self.assertEqual(response.data['unread_count'], 25)
        self.assertEqual(response.data['total_count'], 25)
        self.assertEqual(len(response.data['notifications']), 20)
        self.assertIn('workspace=adviser', response.data['next'])
        second = self.client.get(reverse('notification_list'), {'workspace': 'adviser', 'unread': 'true', 'page': 2})
        self.assertEqual(len(second.data['notifications']), 5)

    def test_security_alerts_have_a_shared_account_inbox(self):
        alert = Notification.objects.create(recipient=self.user, title='Password changed', message='Account updated.', category='SECURITY')
        self.assertEqual(alert.workspace, 'account')
        self.client.post(reverse('notification_read_all') + '?workspace=account')
        self.assertFalse(Notification.objects.filter(recipient=self.user, workspace='account', is_read=False).exists())
        self.assertEqual(Notification.objects.filter(recipient=self.user, is_read=False).count(), 5)

    def test_legacy_backfill_preserves_read_state_and_assigns_known_roles(self):
        from importlib import import_module
        from django.apps import apps
        from django.db import connection

        examples = [
            ('Documenter Assignment', 'GENERAL', 'documenter'),
            ('Minutes Ready for Review', 'GENERAL', 'adviser'),
            ('Panelist eligibility approved', 'DEFENSE', 'pit_lead'),
            ('Password changed', 'SECURITY', 'account'),
        ]
        for title, category, expected in examples:
            with self.subTest(title=title):
                alert = Notification.objects.create(recipient=self.user, title=title, message='Legacy alert.', category=category, is_read=True)
                Notification.objects.filter(pk=alert.pk).update(workspace='')
                migration = import_module('notifications.migrations.0004_notification_workspace')
                with connection.schema_editor() as editor:
                    migration.backfill_workspaces(apps, editor)
                alert.refresh_from_db()
                self.assertEqual(alert.workspace, expected)
                self.assertTrue(alert.is_read)


from unittest.mock import patch


class EmailServiceTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='emailtestuser',
            email='testuser@example.com',
            password='password123',
        )
        self.user_no_email = User.objects.create_user(
            username='noemailuser',
            email='',
            password='password123',
        )

    def test_send_email_success(self):
        with patch('notifications.email_service.send_mail') as mock_send_mail:
            result = _send('Test Subject', '<p>Test</p>', 'recipient@example.com')
            self.assertTrue(result)
            mock_send_mail.assert_called_once()

    def test_send_email_no_recipient(self):
        result = _send('Test Subject', '<p>Test</p>', '')
        self.assertFalse(result)

    def test_send_email_exception_handling(self):
        with patch('notifications.email_service.send_mail', side_effect=Exception('SMTP connection failed')):
            result = _send('Test Subject', '<p>Test</p>', 'recipient@example.com')
            self.assertFalse(result)

    def test_send_password_reset_email_helpers(self):
        from notifications.email_service import send_password_reset_otp_email
        with patch('notifications.email_service.send_mail'):
            self.assertTrue(send_password_reset_email(self.user, 'http://example.com/reset'))
            self.assertTrue(send_password_reset_otp_email(self.user, '123456'))
            self.assertTrue(send_password_changed_email(self.user))
            self.assertTrue(send_admin_password_reset_email(self.user))

        with patch('notifications.email_service.send_mail', side_effect=Exception('SMTP error')):
            self.assertFalse(send_password_reset_email(self.user, 'http://example.com/reset'))
            self.assertFalse(send_password_reset_otp_email(self.user, '123456'))
            self.assertFalse(send_password_changed_email(self.user))
            self.assertFalse(send_admin_password_reset_email(self.user))

    def test_send_password_reset_email_no_email_user(self):
        from notifications.email_service import send_password_reset_otp_email
        self.assertFalse(send_password_reset_email(self.user_no_email, 'http://example.com/reset'))
        self.assertFalse(send_password_reset_otp_email(self.user_no_email, '123456'))



