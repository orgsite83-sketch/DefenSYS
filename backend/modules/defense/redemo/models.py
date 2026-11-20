"""Verification bookings are operational activities, never assessed defenses."""
from django.conf import settings
from django.db import models


class ReDemoAppointment(models.Model):
    source = models.ForeignKey('grading.DefenseOutcome', on_delete=models.PROTECT, related_name='re_demos')
    source_revision = models.PositiveIntegerField()
    requirements = models.JSONField(default=list)
    scheduled_date = models.DateField()
    start_time = models.TimeField()
    slot_duration = models.PositiveSmallIntegerField(default=30)
    room = models.CharField(max_length=120)
    chair = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='re_demo_chair_assignments')
    panelists = models.ManyToManyField(settings.AUTH_USER_MODEL, related_name='re_demo_assignments')
    external_ids = models.JSONField(default=list)
    status = models.CharField(max_length=20, default='scheduled', choices=[
        ('scheduled', 'Scheduled'), ('done', 'Done'), ('cancelled', 'Cancelled')])
    operation_state = models.CharField(max_length=20, default='normal', choices=[
        ('normal', 'Normal'), ('paused', 'Interrupted'), ('postponed', 'Postponed'), ('no_show', 'No-show')])
    operation_reason = models.TextField(blank=True)
    revision = models.PositiveIntegerField(default=1)
    results = models.JSONField(default=list)
    remarks = models.TextField(blank=True)
    verified_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.PROTECT,
                                    related_name='verified_re_demos')
    verified_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='created_re_demos')
    created_at = models.DateTimeField(auto_now_add=True)
    request_id = models.UUIDField(unique=True)
    request_digest = models.CharField(max_length=64)
    verification_request_id = models.UUIDField(null=True, blank=True, unique=True)
    verification_digest = models.CharField(max_length=64, blank=True)

    class Meta:
        app_label = 'defense'
        ordering = ['scheduled_date', 'start_time', 'pk']
        constraints = [models.UniqueConstraint(fields=['source'], condition=models.Q(status='scheduled'),
                                               name='one_active_re_demo_per_outcome')]
