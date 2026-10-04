from django.conf import settings
from django.db import models


class GradeCorrection(models.Model):
    """Permanent before/after evidence, including pending published amendments."""

    grade = models.ForeignKey('grading.TeamGrade', on_delete=models.PROTECT, related_name='corrections')
    requested_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name='requested_grade_corrections')
    approved_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name='approved_grade_corrections')
    reason = models.TextField()
    approval_reason = models.TextField(blank=True)
    changes = models.JSONField()
    before = models.JSONField()
    after = models.JSONField(default=dict)
    status = models.CharField(max_length=16, default='pending', choices=[('pending', 'Pending approval'), ('applied', 'Applied'), ('rejected', 'Rejected')])
    requires_approval = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    applied_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        app_label = 'grading'
        ordering = ['-created_at', '-pk']
