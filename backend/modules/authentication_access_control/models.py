from django.conf import settings
from django.contrib.auth.models import AbstractUser, UserManager
from django.db import models


class DefenSysUserManager(UserManager):
    def create_superuser(self, username, email=None, password=None, **extra_fields):
        extra_fields.setdefault('role', 'admin')
        return super().create_superuser(username, email, password, **extra_fields)


class User(AbstractUser):
    ROLE_CHOICES = (
        ('admin', 'Admin'),
        ('faculty', 'Faculty'),
        ('student', 'Student'),
    )

    objects = DefenSysUserManager()

    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='student')
    team_id = models.CharField(max_length=100, blank=True, null=True)

    # Faculty Specific Roles
    is_panelist = models.BooleanField(default=False)
    is_pit_lead = models.BooleanField(default=False)
    pit_lead_year = models.CharField(max_length=50, blank=True, null=True)
    is_adviser = models.BooleanField(default=False)
    adviser_phase = models.CharField(max_length=50, blank=True, null=True)
    is_documenter = models.BooleanField(default=False)
    is_uploader = models.BooleanField(default=False)
    e_signature = models.ImageField(
        upload_to='e_signatures/',
        null=True,
        blank=True,
        help_text='Uploaded e-signature image (PNG/JPG) for document signing.',
    )

    def __str__(self):
        return f"{self.first_name} {self.last_name} ({self.username})"


class SystemAuditLog(models.Model):
    CATEGORY_ACADEMIC_PERIOD = 'academic_period'
    CATEGORY_GRADE_CENTER = 'grade_center'
    CATEGORY_SCHEDULING = 'scheduling'
    CATEGORY_STUDENT_TEAMS = 'student_teams'
    CATEGORY_REPOSITORY = 'repository'
    CATEGORY_GUEST_ACCESS = 'guest_access'

    CATEGORY_CHOICES = (
        (CATEGORY_ACADEMIC_PERIOD, 'Academic Periods'),
        (CATEGORY_GRADE_CENTER, 'Grade Center'),
        (CATEGORY_SCHEDULING, 'Scheduling'),
        (CATEGORY_STUDENT_TEAMS, 'Student Teams'),
        (CATEGORY_REPOSITORY, 'Repository'),
        (CATEGORY_GUEST_ACCESS, 'Guest Access'),
    )

    REVIEW_CAPTURED = 'captured'
    REVIEW_NEEDS_REVIEW = 'needs_review'
    REVIEW_REVIEWED = 'reviewed'
    REVIEW_REQUIRES_REASON = 'requires_reason'

    REVIEW_STATUS_CHOICES = (
        (REVIEW_CAPTURED, 'Evidence Captured'),
        (REVIEW_NEEDS_REVIEW, 'Needs Review'),
        (REVIEW_REVIEWED, 'Reviewed'),
        (REVIEW_REQUIRES_REASON, 'Requires Reason'),
    )

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='system_audit_logs',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    action = models.CharField(max_length=80)
    category = models.CharField(max_length=40, choices=CATEGORY_CHOICES)
    target_type = models.CharField(max_length=80)
    target_id = models.CharField(max_length=80, blank=True)
    old_values = models.JSONField(default=dict, blank=True)
    new_values = models.JSONField(default=dict, blank=True)
    reason = models.TextField(blank=True)
    review_status = models.CharField(
        max_length=30,
        choices=REVIEW_STATUS_CHOICES,
        default=REVIEW_CAPTURED,
    )
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(fields=['created_at']),
            models.Index(fields=['category', 'created_at']),
            models.Index(fields=['actor', 'created_at']),
            models.Index(fields=['target_type', 'target_id', 'created_at']),
        ]

    def __str__(self):
        return f'{self.category}:{self.action} -> {self.target_type}#{self.target_id}'
