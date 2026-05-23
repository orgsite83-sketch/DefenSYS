from django.conf import settings
from django.db import models
from django.utils import timezone

from .upload_paths import vault_entry_upload_to


PIT_YEAR_PREFIX_LABELS = {
    '1stYear': '1st Year',
    '2ndYear': '2nd Year',
    '3rdYear': '3rd Year',
    '4thYear': '4th Year',
}

PIT_SEMESTER_LABELS = {
    '1stSemester': '1st Semester',
    '2ndSemester': '2nd Semester',
    'Summer': 'Summer',
}


class VaultEntry(models.Model):
    TYPE_PIT = 'pit'
    TYPE_CAPSTONE = 'capstone'

    TYPE_CHOICES = (
        (TYPE_PIT, 'PIT'),
        (TYPE_CAPSTONE, 'Capstone'),
    )

    STATUS_PENDING = 'Pending AI Classification'
    STATUS_APPROVED = 'Approved'
    STATUS_NEEDS_REVISION = 'Needs Revision'

    STATUS_CHOICES = (
        (STATUS_PENDING, STATUS_PENDING),
        (STATUS_APPROVED, STATUS_APPROVED),
        (STATUS_NEEDS_REVISION, STATUS_NEEDS_REVISION),
    )

    entry_type = models.CharField(max_length=20, choices=TYPE_CHOICES, default=TYPE_PIT)
    
    # Actual file storage
    file = models.FileField(
        upload_to=vault_entry_upload_to,
        null=True,
        blank=True,
        help_text='Actual uploaded file',
    )
    
    # Metadata (kept for backward compatibility and display)
    file_name = models.CharField(max_length=255)
    file_size = models.CharField(max_length=40, blank=True)
    
    # ML-powered search fields
    extracted_text = models.TextField(
        blank=True,
        default='',
        help_text='Full text extracted from PDF for ML search'
    )
    topics = models.JSONField(
        blank=True,
        default=list,
        help_text='Auto-extracted keywords/topics from PDF content'
    )
    summary = models.TextField(
        blank=True,
        default='',
        help_text='Auto-generated summary of PDF content'
    )
    category = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='ML-predicted technology category',
    )
    category_confidence = models.FloatField(
        blank=True,
        null=True,
        help_text='Classification confidence score (0-100)',
    )

    team = models.ForeignKey(
        'student_teams.StudentTeam',
        related_name='vault_entries',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    team_name = models.CharField(max_length=120, blank=True)
    year_level = models.CharField(max_length=20, blank=True)
    course_code = models.CharField(max_length=30, blank=True)
    semester_label = models.CharField(max_length=30, blank=True)
    academic_year = models.CharField(max_length=9, blank=True)
    stage_label = models.CharField(max_length=80, blank=True)
    status = models.CharField(max_length=40, choices=STATUS_CHOICES, default=STATUS_APPROVED)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='uploaded_vault_entries',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    uploaded_by_name = models.CharField(max_length=150, blank=True)
    uploaded_at = models.DateTimeField(default=timezone.now)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'repository'
        db_table = 'digital_vault_vaultentry'
        ordering = ['-uploaded_at', 'file_name']
        constraints = [
            models.UniqueConstraint(
                fields=['entry_type', 'file_name', 'academic_year'],
                name='unique_vault_entry_per_academic_year',
            ),
        ]
        indexes = [
            models.Index(fields=['entry_type', 'team'], name='vault_entry_type_team_idx'),
        ]

    def save(self, *args, **kwargs):
        if self.entry_type == self.TYPE_PIT:
            self._hydrate_pit_metadata()
        if self.team and not self.team_name:
            self.team_name = self.team.name
        if self.uploaded_by and not self.uploaded_by_name:
            full_name = f'{self.uploaded_by.first_name} {self.uploaded_by.last_name}'.strip()
            self.uploaded_by_name = full_name or self.uploaded_by.username
        
        if self.file:
            from .ml_indexing import apply_ml_from_pdf

            apply_ml_from_pdf(self)

        super().save(*args, **kwargs)

    def _hydrate_pit_metadata(self):
        parts = (self.file_name or '').split('.')
        if len(parts) < 4:
            return
        self.year_level = self.year_level or PIT_YEAR_PREFIX_LABELS.get(parts[0], parts[0])
        self.course_code = self.course_code or parts[1]
        self.semester_label = self.semester_label or PIT_SEMESTER_LABELS.get(parts[3], parts[3])
        self.stage_label = self.stage_label or self.course_code

    def __str__(self):
        return self.file_name
    
    @property
    def file_url(self):
        """Get the URL for the uploaded file"""
        if self.file:
            return self.file.url
        return None
