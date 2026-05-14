import secrets

from django.conf import settings
from django.db import models


class GuestPanelistCode(models.Model):
    code = models.CharField(max_length=16, unique=True, db_index=True, editable=False)
    guest_name = models.CharField(max_length=150)
    email = models.EmailField(blank=True)
    defense_schedule = models.ForeignKey(
        'defense_scheduler.DefenseSchedule',
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
