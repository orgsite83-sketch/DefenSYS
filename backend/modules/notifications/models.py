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


class NotificationWorkspace(models.TextChoices):
    ADMIN = 'admin', 'Administrator'
    FACULTY = 'faculty', 'Faculty'
    STUDENT = 'student', 'Student'
    ADVISER = 'adviser', 'Project Adviser'
    PIT_LEAD = 'pit_lead', 'PIT Lead'
    PIT_INSTRUCTOR = 'pit_instructor', 'PIT Instructor'
    PANELIST = 'panelist', 'Panelist'
    DOCUMENTER = 'documenter', 'Minutes Documenter'
    UPLOADER = 'uploader', 'Uploader'
    ACCOUNT = 'account', 'Account & Security'


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
    workspace = models.CharField(
        max_length=24, choices=NotificationWorkspace.choices, blank=True,
        default='', help_text='Inbox that owns this notification and its read state.',
    )
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['recipient', 'is_read']),
            models.Index(fields=['recipient', '-created_at']),
            models.Index(fields=['recipient', 'category']),
            models.Index(fields=['recipient', 'workspace', 'is_read'], name='notif_recipient_workspace_read'),
        ]

    def save(self, *args, **kwargs):
        # Compatibility for integrations that have not supplied a workspace yet.
        # Operational producers should always set the role explicitly.
        if not self.workspace:
            if self.category in (NotificationCategory.SECURITY, NotificationCategory.ANNOUNCEMENT):
                self.workspace = NotificationWorkspace.ACCOUNT
            else:
                self.workspace = self.recipient.role
            if kwargs.get('update_fields') is not None:
                kwargs['update_fields'] = set(kwargs['update_fields']) | {'workspace'}
        return super().save(*args, **kwargs)

    def __str__(self):
        sender_username = self.sender.username if self.sender else "System"
        return f"To: {self.recipient.username} | From: {sender_username} | {self.title}"

