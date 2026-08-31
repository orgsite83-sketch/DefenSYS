from django.conf import settings
from django.db import models
from django.utils import timezone

from .upload_paths import archive_entry_upload_to


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


class ArchiveEntry(models.Model):
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
        upload_to=archive_entry_upload_to,
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
        related_name='archive_entries',
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
    defense_stage = models.ForeignKey(
        'defense.DefenseStage',
        related_name='archive_entries',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
    )
    pit_event_config = models.ForeignKey(
        'defense.PitEventGradingConfig',
        related_name='archive_entries',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
    )
    status = models.CharField(max_length=40, choices=STATUS_CHOICES, default=STATUS_APPROVED)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='uploaded_archive_entries',
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
        db_table = 'repository_archiveentry'
        ordering = ['-uploaded_at', 'file_name']
        constraints = [
            models.UniqueConstraint(
                fields=['entry_type', 'file_name', 'academic_year'],
                name='unique_archive_entry_per_academic_year',
            ),
        ]
        indexes = [
            models.Index(fields=['entry_type', 'team'], name='archive_entry_type_team_idx'),
        ]

    def save(self, *args, **kwargs):
        if self.entry_type == self.TYPE_PIT:
            self._hydrate_pit_metadata()
            self.defense_stage = None
        else:
            self.pit_event_config = None
            if self.defense_stage_id and not self.stage_label:
                self.stage_label = self.defense_stage.label
        if self.team and not self.team_name:
            self.team_name = self.team.name
        if self.uploaded_by and not self.uploaded_by_name:
            full_name = f'{self.uploaded_by.first_name} {self.uploaded_by.last_name}'.strip()
            self.uploaded_by_name = full_name or self.uploaded_by.username
        
        super().save(*args, **kwargs)

        if self.file and not self.extracted_text:
            from .ml_indexing import apply_ml_from_pdf
            if apply_ml_from_pdf(self):
                super().save(update_fields=['extracted_text', 'topics', 'summary', 'category', 'category_confidence'])

    def _hydrate_pit_metadata(self):
        # 1. Try to hydrate from database relations first if available
        if self.team:
            self.year_level = self.year_level or self.team.year_level
            if self.team.semester:
                self.semester_label = self.semester_label or self.team.semester.label
            from repository.project_archive.services import _default_course_for_year
            self.course_code = self.course_code or _default_course_for_year(self.team.year_level)

        if self.pit_event_config:
            self.stage_label = self.stage_label or self.pit_event_config.event_name

        # 2. Fall back to split file name parsing for backward compatibility (e.g. legacy/archived uploads)
        parts = (self.file_name or '').split('.')
        if len(parts) >= 4:
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


class RepositoryReview(models.Model):
    target_id = models.CharField(max_length=120, db_index=True, help_text='ID of the repository entry (e.g. capstone-1-2, pit-5, doc_3)')
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='repository_reviews',
        on_delete=models.CASCADE,
    )
    user_name = models.CharField(max_length=150, blank=True)
    user_role = models.CharField(max_length=50, blank=True, default='Student')
    rating = models.PositiveSmallIntegerField(default=5, help_text='Rating from 1 to 5 stars')
    remark = models.TextField(blank=True, default='', help_text='User review remarks or feedback')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'repository'
        db_table = 'repository_review'
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['target_id', 'user'],
                name='unique_user_repository_review',
            ),
        ]
        indexes = [
            models.Index(fields=['target_id'], name='repo_review_target_idx'),
        ]

    def save(self, *args, **kwargs):
        if self.user and not self.user_name:
            full_name = f'{self.user.first_name} {self.user.last_name}'.strip()
            self.user_name = full_name or self.user.username
        if self.user and hasattr(self.user, 'role') and not self.user_role:
            self.user_role = str(self.user.role).capitalize()
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.user_name} - {self.target_id} ({self.rating}★)'


class UserBookShelf(models.Model):
    STATUS_WANT_TO_READ = 'want_to_read'
    STATUS_READING = 'reading'
    STATUS_COMPLETED = 'completed'
    STATUS_FAVORITED = 'favorited'

    STATUS_CHOICES = (
        (STATUS_WANT_TO_READ, 'Want to Read'),
        (STATUS_READING, 'Currently Reading'),
        (STATUS_COMPLETED, 'Completed'),
        (STATUS_FAVORITED, 'Favorited'),
    )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='user_bookshelf',
        on_delete=models.CASCADE,
    )
    target_id = models.CharField(max_length=120, db_index=True)
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default=STATUS_READING)
    last_read_page = models.PositiveIntegerField(default=1)
    total_pages = models.PositiveIntegerField(default=1)
    progress_percent = models.FloatField(default=0.0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'repository'
        db_table = 'repository_bookshelf'
        ordering = ['-updated_at']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'target_id'],
                name='unique_user_bookshelf_target',
            ),
        ]
        indexes = [
            models.Index(fields=['user', 'status'], name='repo_shelf_user_status_idx'),
        ]

    def __str__(self):
        return f'{self.user.username} - {self.target_id} ({self.status})'

