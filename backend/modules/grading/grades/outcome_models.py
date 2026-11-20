"""Attempt-owned decisions; mutable grade rows are compatibility projections."""
from django.conf import settings
from django.db import models


class DefenseOutcome(models.Model):
    schedule = models.OneToOneField('defense.DefenseSchedule', on_delete=models.PROTECT,
                                   related_name='official_outcome')
    grade = models.ForeignKey('grading.TeamGrade', on_delete=models.PROTECT, related_name='official_outcomes')
    project_version = models.PositiveIntegerField()
    verdict = models.CharField(max_length=30)
    decision_source = models.CharField(max_length=24)
    selected_key = models.CharField(max_length=128, blank=True)
    reason = models.TextField(blank=True)
    instructions = models.TextField(blank=True)
    revision_entries = models.JSONField(default=list)
    demo_requirements = models.JSONField(default=list)
    assessment_snapshot = models.JSONField(default=dict)
    revision = models.PositiveIntegerField(default=1)
    history = models.JSONField(default=list)
    confirmed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
                                    related_name='confirmed_defense_outcomes')
    confirmed_at = models.DateTimeField(auto_now_add=True)
    request_id = models.UUIDField(unique=True)
    request_digest = models.CharField(max_length=64)

    class Meta:
        app_label = 'grading'

    @property
    def re_demo_required(self):
        return bool(self.demo_requirements)
