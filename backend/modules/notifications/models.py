from django.conf import settings
from django.db import models


class NotificationCategory(models.TextChoices):
    GENERAL = 'GENERAL', 'General'
    SECURITY = 'SECURITY', 'Account & Security'
    MINUTES = 'MINUTES', 'Minutes & Signatures'
    DEFENSE = 'DEFENSE', 'Defense Schedule'
    PEER_EVAL = 'PEER_EVAL', 'Peer Evaluation'
    ANNOUNCEMENT = 'ANNOUNCEMENT', 'System Announcement'


class NotificationPriority(models.TextChoices):
    NORMAL = 'NORMAL', 'Normal'
    HIGH = 'HIGH', 'High'
    URGENT = 'URGENT', 'Urgent'


class Notification(models.Model):
    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='notifications',
        on_delete=models.CASCADE,
    )
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='sent_notifications',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    title = models.CharField(max_length=255)
    message = models.TextField()
    category = models.CharField(
        max_length=50,
        choices=NotificationCategory.choices,
        default=NotificationCategory.GENERAL,
    )
    priority = models.CharField(
        max_length=20,
        choices=NotificationPriority.choices,
        default=NotificationPriority.NORMAL,
    )
    action_route = models.CharField(max_length=255, blank=True, null=True)
    action_payload = models.JSONField(default=dict, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['recipient', 'is_read']),
            models.Index(fields=['recipient', '-created_at']),
            models.Index(fields=['recipient', 'category']),
        ]

    def __str__(self):
        sender_username = self.sender.username if self.sender else "System"
        return f"To: {self.recipient.username} | From: {sender_username} | {self.title}"

