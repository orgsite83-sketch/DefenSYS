from django.conf import settings
from django.db import models


class RepositoryAuditLog(models.Model):
    TYPE_PIT = 'pit'
    TYPE_CAPSTONE = 'capstone'

    TYPE_CHOICES = (
        (TYPE_PIT, 'PIT'),
        (TYPE_CAPSTONE, 'Capstone'),
    )

    ACTION_UPLOAD = 'upload'
    ACTION_CLASSIFY = 'classify'
    ACTION_OVERRIDE = 'override'
    ACTION_DEMO_FILL = 'demo_fill'

    ACTION_CHOICES = (
        (ACTION_UPLOAD, 'Upload'),
        (ACTION_CLASSIFY, 'Classify'),
        (ACTION_OVERRIDE, 'Override Status'),
        (ACTION_DEMO_FILL, 'Demo Fill'),
    )

    entry_type = models.CharField(max_length=20, choices=TYPE_CHOICES)
    source_id = models.PositiveIntegerField(null=True, blank=True)
    file_name = models.CharField(max_length=255)
    action = models.CharField(max_length=30, choices=ACTION_CHOICES)
    previous_status = models.CharField(max_length=60, blank=True)
    new_status = models.CharField(max_length=60, blank=True)
    message = models.CharField(max_length=255, blank=True)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='repository_audit_logs',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']

    def __str__(self):
        return f'{self.file_name} - {self.action}'
