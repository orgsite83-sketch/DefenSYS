"""Optional configuration attachments, independent of student submissions."""
from pathlib import PurePath
from uuid import uuid4

from django.conf import settings
from django.db import models


def template_upload_to(instance, filename):
    return f'deliverable_templates/{uuid4().hex}{PurePath(filename).suffix.lower()}'


class DeliverableTemplate(models.Model):
    defense_stage = models.ForeignKey('defense.DefenseStage', null=True, blank=True,
        on_delete=models.CASCADE, related_name='template_attachments')
    pit_event_config = models.ForeignKey('defense.PitEventGradingConfig', null=True, blank=True,
        on_delete=models.CASCADE, related_name='template_attachments')
    requirement_scope = models.CharField(max_length=8, choices=[('team', 'Team'), ('shared', 'Shared')])
    deliverable_id = models.CharField(max_length=40)
    file = models.FileField(upload_to=template_upload_to, max_length=255)
    original_name = models.CharField(max_length=255)
    byte_size = models.PositiveBigIntegerField()
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='+')
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'defense'
        constraints = [
            models.CheckConstraint(condition=(
                models.Q(defense_stage__isnull=False, pit_event_config__isnull=True) |
                models.Q(defense_stage__isnull=True, pit_event_config__isnull=False)),
                name='template_exactly_one_context'),
            models.UniqueConstraint(fields=['defense_stage', 'requirement_scope', 'deliverable_id'],
                name='template_unique_stage_requirement'),
            models.UniqueConstraint(fields=['pit_event_config', 'requirement_scope', 'deliverable_id'],
                name='template_unique_pit_requirement'),
        ]
