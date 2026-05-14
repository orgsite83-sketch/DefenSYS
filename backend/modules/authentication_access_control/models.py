from django.contrib.auth.models import AbstractUser
from django.db import models

class User(AbstractUser):
    ROLE_CHOICES = (
        ('admin', 'Admin'),
        ('faculty', 'Faculty'),
        ('student', 'Student'),
    )

    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='student')
    team_id = models.CharField(max_length=100, blank=True, null=True)

    # Faculty Specific Roles
    is_panelist = models.BooleanField(default=False)
    is_pit_lead = models.BooleanField(default=False)
    pit_lead_year = models.CharField(max_length=50, blank=True, null=True)
    is_adviser = models.BooleanField(default=False)
    adviser_phase = models.CharField(max_length=50, blank=True, null=True)
    is_repo_assistant = models.BooleanField(default=False)
    is_uploader = models.BooleanField(default=False)

    def __str__(self):
        return f"{self.first_name} {self.last_name} ({self.username})"
