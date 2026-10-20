from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from student_teams.project_versions import CurrentProjectManager
import logging

logger = logging.getLogger(__name__)


class DeliverableSubmission(models.Model):
    TYPE_PRE = 'pre'
    TYPE_POST = 'post'

    TYPE_CHOICES = (
        (TYPE_PRE, 'Pre-Defense'),
        (TYPE_POST, 'Post-Defense'),
    )

    STATUS_PENDING = 'pending'
    STATUS_ACCEPTED = 'accepted'
    STATUS_REJECTED = 'rejected'

    STATUS_CHOICES = (
        (STATUS_PENDING, 'Pending Review'),
        (STATUS_ACCEPTED, 'Accepted'),
        (STATUS_REJECTED, 'Rejected'),
    )

    team = models.ForeignKey(
        'student_teams.StudentTeam',
        related_name='deliverable_submissions',
        on_delete=models.CASCADE,
    )
    stage_label = models.CharField(max_length=80)
    project_version = models.PositiveIntegerField(default=1)
    archive_semester = models.ForeignKey(
        'academic_period_management.Semester', null=True, blank=True,
        on_delete=models.PROTECT, related_name='archive_deliverable_submissions',
    )
    archive_team_name = models.CharField(max_length=120, blank=True, default='')
    archive_project_title = models.CharField(max_length=255, blank=True, default='')
    archive_year_level = models.CharField(max_length=20, blank=True, default='')
    archive_team_level = models.CharField(max_length=30, blank=True, default='')
    pit_event_config = models.ForeignKey(
        'defense.PitEventGradingConfig', null=True, blank=True,
        on_delete=models.SET_NULL, related_name='archive_deliverable_submissions',
    )
    objects = CurrentProjectManager()
    all_objects = models.Manager()
    deliverable_id = models.CharField(max_length=20)
    label = models.CharField(max_length=180)
    deliverable_type = models.CharField(max_length=20, choices=TYPE_CHOICES)
    required = models.BooleanField(default=False)
    is_late = models.BooleanField(default=False, help_text='True if uploaded after defense start under an authorized late-upload window.')
    
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default=STATUS_PENDING,
        help_text='Review and approval status'
    )
    feedback = models.TextField(
        blank=True,
        default='',
        help_text='Rejection feedback or remarks'
    )
    file_replacement_unlocked = models.BooleanField(
        default=False,
        help_text='Allow one replacement of an approved pre-defense file without changing its approval.'
    )
    file_replacement_reason = models.TextField(blank=True, default='')
    revision_review_unlocked = models.BooleanField(
        default=False,
        help_text='Allow the requested pre-defense revision to be reviewed despite the stage lock.'
    )
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='reviewed_deliverables',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    reviewed_at = models.DateTimeField(
        null=True,
        blank=True
    )
    
    # Actual file storage
    file = models.FileField(
        upload_to='deliverables/%Y/%m/',
        null=True,
        blank=True,
        help_text='Actual uploaded file'
    )
    
    # Metadata (kept for backward compatibility and display)
    file_name = models.CharField(max_length=255, blank=True, default='')
    file_size = models.CharField(max_length=40, blank=True, default='')
    
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
    
    # Naive Bayes classification fields
    category = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='ML-predicted technology category'
    )
    category_confidence = models.FloatField(
        blank=True,
        null=True,
        help_text='Classification confidence score (0-100)'
    )
    classification = models.JSONField(blank=True, default=dict,
        help_text='Versioned model result, status and supporting document passages')
    
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='uploaded_capstone_deliverables',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    uploaded_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'repository'
        db_table = 'capstone_deliverables_deliverablesubmission'
        ordering = ['stage_label', 'deliverable_id']
        constraints = [
            models.UniqueConstraint(
                fields=['team', 'stage_label', 'deliverable_id', 'project_version'],
                name='unique_deliverable_submission_per_team_stage',
            ),
        ]
        indexes = [
            models.Index(fields=['stage_label', 'deliverable_type'], name='capstone_de_stage_l_d3e67b_idx'),
            models.Index(fields=['deliverable_id'], name='capstone_de_deliver_e79675_idx'),
            models.Index(fields=['team', 'stage_label'], name='capstone_de_team_st_idx'),
        ]

    def clean(self):
        if self.team_id and not (self.team.is_capstone or self.team.is_pit):
            raise ValidationError({'team': 'Only Capstone or PIT teams can submit deliverables.'})

    def save(self, *args, **kwargs):
        from .pdf_processor import invalidate_changed_pdf_cache
        invalidate_changed_pdf_cache(self, kwargs)
        if not self.pk:
            self.project_version = self.team.project_version
        if self.team_id:
            self.archive_semester = self.archive_semester or self.team.semester
            self.archive_team_name = self.archive_team_name or self.team.name
            self.archive_project_title = self.archive_project_title or self.team.project_title
            self.archive_year_level = self.archive_year_level or self.team.year_level
            self.archive_team_level = self.archive_team_level or self.team.level
            is_pit = getattr(self.team, 'is_pit', False) or 'PIT' in (self.archive_team_level or '')
            if is_pit and not self.pit_event_config_id:
                from defense.scheduler.models import PitEventGradingConfig
                self.pit_event_config = PitEventGradingConfig.objects.filter(
                    semester=self.archive_semester, year_level=self.archive_year_level,
                    event_name__iexact=self.stage_label.strip(),
                ).first()
        self.full_clean()
        
        # Metadata reviews must not reopen/reprocess a stored file (including
        # image-only PDFs and other formats that legitimately have no text).
        update_fields = kwargs.get('update_fields')
        process_file = update_fields is None or 'file' in update_fields
        if process_file and self.file and not self.extracted_text:
            from .pdf_processor import extract_pdf_from_file_object
            try:
                with self.file.open('rb') as stored:
                    result = extract_pdf_from_file_object(
                        stored,
                        self.file.name or self.file_name,
                        classify=True,
                    )
                    if hasattr(stored, 'seek'):
                        try:
                            stored.seek(0)
                        except Exception:
                            pass
                self.extracted_text = result.get('text', '')
                self.topics = result.get('topics', [])
                self.summary = result.get('summary', '')
                self.category = result.get('category', '') or ''
                classification = result.get('classification') or {}
                self.category_confidence = classification.get('confidence_score')
                self.classification = classification
            except Exception as e:
                logger.warning(f'PDF extraction failed for {self.file_name}: {e}')
        
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.team} - {self.deliverable_id}'
    
    @property
    def latest_file(self):
        """The current repository file; older uploads remain stored as history.

        Use the prefetched collection when available and break timestamp ties
        by ID so every consumer selects the same revision.
        """
        return max((f for f in self.files.all() if f.is_current), key=lambda f: (f.uploaded_at, f.pk), default=None)

    @property
    def file_url(self):
        """Get the URL for the uploaded file"""
        if self.file:
            return self.file.url
        return None


class DeliverableSubmissionFile(models.Model):
    slot_key = models.CharField(max_length=100, default='primary')
    revision = models.PositiveIntegerField(default=1)
    is_current = models.BooleanField(default=True)
    status = models.CharField(max_length=20, default='pending', choices=DeliverableSubmission.STATUS_CHOICES)
    feedback = models.TextField(blank=True, default='')
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='reviewed_deliverable_files')
    submission = models.ForeignKey(
        'DeliverableSubmission',
        related_name='files',
        on_delete=models.CASCADE,
    )
    # Actual file storage
    file = models.FileField(
        upload_to='deliverables/%Y/%m/',
        null=True,
        blank=True,
        help_text='Actual uploaded file'
    )
    
    # Metadata
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
    
    # Naive Bayes classification fields
    category = models.CharField(
        max_length=100,
        blank=True,
        default='',
        help_text='ML-predicted technology category'
    )
    category_confidence = models.FloatField(
        blank=True,
        null=True,
        help_text='Classification confidence score (0-100)'
    )
    classification = models.JSONField(blank=True, default=dict,
        help_text='Versioned model result, status and supporting document passages')
    
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'repository'
        db_table = 'capstone_deliverables_deliverablesubmissionfile'
        ordering = ['uploaded_at']
        constraints = [models.UniqueConstraint(fields=['submission', 'slot_key'],
            condition=models.Q(is_current=True), name='unique_current_document_slot')]

    def clean(self):
        if not self.file_name.strip():
            raise ValidationError({'file_name': 'File name is required.'})

    def save(self, *args, **kwargs):
        from .pdf_processor import invalidate_changed_pdf_cache
        invalidate_changed_pdf_cache(self, kwargs)
        self.full_clean()
        
        # Extract PDF content if file exists and hasn't been extracted yet
        if self.file and not self.extracted_text:
            from .pdf_processor import extract_pdf_from_file_object
            try:
                with self.file.open('rb') as stored:
                    result = extract_pdf_from_file_object(
                        stored,
                        self.file.name or self.file_name,
                        classify=True,
                    )
                    if hasattr(stored, 'seek'):
                        try:
                            stored.seek(0)
                        except Exception:
                            pass
                self.extracted_text = result.get('text', '')
                self.topics = result.get('topics', [])
                self.summary = result.get('summary', '')
                self.category = result.get('category', '') or ''
                classification = result.get('classification') or {}
                self.category_confidence = classification.get('confidence_score')
                self.classification = classification
            except Exception as e:
                logger.warning(f'PDF extraction failed for {self.file_name}: {e}')
        
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.submission} - {self.file_name}'


class ConceptRound(models.Model):
    """A concept set and the immutable evidence presented in one hearing."""
    team = models.ForeignKey('student_teams.StudentTeam', on_delete=models.CASCADE, related_name='concept_rounds')
    section_round = models.ForeignKey('repository.SectionConceptRound', null=True, blank=True,
        on_delete=models.PROTECT, related_name='module_rounds')
    defense_stage = models.ForeignKey('defense.DefenseStage', on_delete=models.PROTECT, null=True, blank=True)
    pit_event_config = models.ForeignKey('defense.PitEventGradingConfig', on_delete=models.PROTECT, null=True, blank=True)
    project_version = models.PositiveIntegerField(default=1)
    number = models.PositiveIntegerField(default=1)
    concepts = models.JSONField(default=list)
    policy_snapshot = models.JSONField(default=dict, blank=True)
    schedule = models.OneToOneField('defense.DefenseSchedule', null=True, blank=True,
        on_delete=models.PROTECT, related_name='concept_round')
    documents_snapshot = models.JSONField(default=list, blank=True)
    verdict = models.CharField(max_length=30, blank=True, default='')
    remarks = models.TextField(blank=True, default='')
    decided_at = models.DateTimeField(null=True, blank=True)
    decided_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='decided_concept_rounds')
    revisions_cleared_at = models.DateTimeField(null=True, blank=True)
    revisions_cleared_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='cleared_concept_rounds')
    replacement_required = models.BooleanField(default=False)
    review_required = models.BooleanField(default=True)
    endorsed_at = models.DateTimeField(null=True, blank=True)
    endorsed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name='endorsed_concept_rounds')
    endorsement_snapshot = models.JSONField(default=list, blank=True)
    override_reason = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = 'repository'
        constraints = [
            models.CheckConstraint(condition=(
                models.Q(defense_stage__isnull=False, pit_event_config__isnull=True) |
                models.Q(defense_stage__isnull=True, pit_event_config__isnull=False)), name='concept_round_one_context'),
            models.UniqueConstraint(fields=['team', 'defense_stage', 'project_version', 'number'],
                name='unique_team_concept_round'),
            models.UniqueConstraint(fields=['team', 'pit_event_config', 'project_version', 'number'],
                name='unique_team_pit_concept_round'),
        ]
        ordering = ['number', 'id']

