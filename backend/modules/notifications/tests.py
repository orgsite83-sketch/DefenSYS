from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from .models import Notification

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


from unittest.mock import patch
from .email_service import (
    _send,
    send_password_reset_email,
    send_password_changed_email,
    send_admin_password_reset_email,
)


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
        with patch('notifications.email_service.send_mail'):
            self.assertTrue(send_password_reset_email(self.user, 'http://example.com/reset'))
            self.assertTrue(send_password_changed_email(self.user))
            self.assertTrue(send_admin_password_reset_email(self.user))

        with patch('notifications.email_service.send_mail', side_effect=Exception('SMTP error')):
            self.assertFalse(send_password_reset_email(self.user, 'http://example.com/reset'))
            self.assertFalse(send_password_changed_email(self.user))
            self.assertFalse(send_admin_password_reset_email(self.user))

    def test_send_password_reset_email_no_email_user(self):
        self.assertFalse(send_password_reset_email(self.user_no_email, 'http://example.com/reset'))


