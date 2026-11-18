"""Explicit disclosure records, independent of mutable academic grade status."""
import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class OutcomeReleaseControl(models.Model):
    context_key = models.CharField(max_length=200, unique=True)
    schedule = models.OneToOneField('defense.DefenseSchedule', null=True, on_delete=models.SET_NULL,
                                   related_name='outcome_release_control')
    context = models.JSONField(default=dict)
    held = models.BooleanField(default=False)
    hold_reason = models.CharField(max_length=1000, blank=True)
    changed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name='+')
    changed_at = models.DateTimeField(auto_now=True)
    revision = models.PositiveIntegerField(default=0)

    class Meta:
        app_label = 'grading'


class OutcomeReleaseBatch(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name='+')
    actor_name = models.CharField(max_length=255)
    request_hash = models.CharField(max_length=64)
    context = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'grading'
        ordering = ['-created_at', '-pk']


class OutcomeRelease(models.Model):
    control = models.ForeignKey(OutcomeReleaseControl, on_delete=models.PROTECT, related_name='releases')
    batch = models.ForeignKey(OutcomeReleaseBatch, on_delete=models.PROTECT, related_name='releases')
    content_hash = models.CharField(max_length=64)
    version = models.PositiveIntegerField(default=1)
    snapshot = models.JSONField()
    recipient_ids = models.JSONField(default=list)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'grading'
        ordering = ['-created_at', '-pk']
        constraints = [models.UniqueConstraint(fields=['control', 'version'], name='unique_outcome_release_version')]

    def save(self, *args, **kwargs):
        if self.pk and not self._state.adding:
            raise ValidationError('Released outcome snapshots are immutable.')
        return super().save(*args, **kwargs)
