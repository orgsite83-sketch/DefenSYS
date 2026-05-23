import secrets

from django.conf import settings
from django.db import models


class GuestPanelistCode(models.Model):
    code = models.CharField(max_length=16, unique=True, db_index=True, editable=False)
    guest_name = models.CharField(max_length=150)
    email = models.EmailField(blank=True)
    defense_schedule = models.ForeignKey(
        'defense.DefenseSchedule',
        related_name='guest_panelist_codes',
        on_delete=models.CASCADE,
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='created_guest_panelist_codes',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    is_active = models.BooleanField(default=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    used_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['is_active', 'created_at']),
        ]

    @classmethod
    def generate_unique_code(cls):
        while True:
            code = f'DEF-{secrets.token_hex(3).upper()}'
            if not cls.objects.filter(code=code).exists():
                return code

    def save(self, *args, **kwargs):
        if not self.code:
            self.code = self.generate_unique_code()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.code} - {self.guest_name}'


class FacultyRoleAssignment(models.Model):
    ROLE_PANELIST = 'panelist'
    ROLE_PIT_LEAD = 'pit_lead'
    ROLE_ADVISER = 'adviser'
    ROLE_REPO_ASSISTANT = 'repo_assistant'

    ROLE_KEY_CHOICES = (
        (ROLE_PANELIST, 'Defense Panelist'),
        (ROLE_PIT_LEAD, 'PIT Lead'),
        (ROLE_ADVISER, 'Project Adviser'),
        (ROLE_REPO_ASSISTANT, 'Repository Assistant'),
    )

    ACTION_ASSIGNED = 'assigned'
    ACTION_REVOKED = 'revoked'
    ACTION_CHOICES = (
        (ACTION_ASSIGNED, 'Assigned'),
        (ACTION_REVOKED, 'Revoked'),
    )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='faculty_role_assignments',
        on_delete=models.CASCADE,
    )
    role_key = models.CharField(max_length=32, choices=ROLE_KEY_CHOICES)
    role_detail = models.CharField(max_length=100, blank=True, null=True)
    semester = models.ForeignKey(
        'academic_period_management.Semester',
        related_name='faculty_role_assignments',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    year_level = models.CharField(max_length=50, blank=True, null=True)
    action = models.CharField(max_length=16, choices=ACTION_CHOICES)
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='faculty_role_changes_made',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    changed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-changed_at', '-id']

    def __str__(self):
        return f'{self.user_id} {self.role_key} {self.action}'


from user_management.academic_records.models import StudentAcademicRecord  # noqa: E402,F401
