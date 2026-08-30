from django.conf import settings
from django.contrib.auth.models import AbstractUser, UserManager
from django.db import models


class DefenSysUserManager(UserManager):
    def create_superuser(self, username, email=None, password=None, phone_number='', **extra_fields):
        extra_fields.setdefault('role', 'admin')
        if phone_number:
            extra_fields['phone_number'] = phone_number
        return super().create_superuser(username, email, password, **extra_fields)


class User(AbstractUser):
    ROLE_CHOICES = (
        ('admin', 'Admin'),
        ('faculty', 'Faculty'),
        ('student', 'Student'),
    )

    REQUIRED_FIELDS = ['email', 'phone_number']

    objects = DefenSysUserManager()

    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='student')

    # Faculty Specific Roles
    is_panelist = models.BooleanField(default=False)
    is_pit_lead = models.BooleanField(default=False)
    pit_lead_year = models.CharField(max_length=50, blank=True, null=True)
    is_adviser = models.BooleanField(default=False)
    is_documenter = models.BooleanField(default=False)
    is_uploader = models.BooleanField(default=False)
    e_signature = models.ImageField(
        upload_to='e_signatures/',
        null=True,
        blank=True,
        help_text='Uploaded e-signature image (PNG/JPG) for document signing.',
    )
    avatar = models.ImageField(
        upload_to='avatars/',
        null=True,
        blank=True,
        help_text='User profile picture.',
    )
    phone_number = models.CharField(
        max_length=32,
        blank=True,
        default='',
        help_text="User's mobile phone number for SMS notifications.",
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
    CATEGORY_USER_MANAGEMENT = 'user_management'

    CATEGORY_CHOICES = (
        (CATEGORY_ACADEMIC_PERIOD, 'Academic Periods'),
        (CATEGORY_GRADE_CENTER, 'Grade Center'),
        (CATEGORY_SCHEDULING, 'Scheduling'),
        (CATEGORY_STUDENT_TEAMS, 'Student Teams'),
        (CATEGORY_REPOSITORY, 'Repository'),
        (CATEGORY_GUEST_ACCESS, 'Guest Access'),
        (CATEGORY_USER_MANAGEMENT, 'User Management'),
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


class PasswordResetOTP(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='password_reset_otps',
    )
    otp_code_hash = models.CharField(max_length=128)
    reset_token = models.CharField(max_length=128, blank=True, default='', db_index=True)
    attempts = models.PositiveIntegerField(default=0)
    is_verified = models.BooleanField(default=False)
    is_used = models.BooleanField(default=False)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'created_at']),
            models.Index(fields=['reset_token']),
        ]

    def __str__(self):
        return f'PasswordResetOTP(user={self.user.username}, verified={self.is_verified}, used={self.is_used})'

