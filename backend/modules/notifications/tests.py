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
