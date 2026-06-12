from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class DeliverableSubmission(models.Model):
    TYPE_PRE = 'pre'
    TYPE_VAULT = 'vault'

    TYPE_CHOICES = (
        (TYPE_PRE, 'Pre-Defense'),
        (TYPE_VAULT, 'Vault'),
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
    deliverable_id = models.CharField(max_length=20)
    label = models.CharField(max_length=180)
    deliverable_type = models.CharField(max_length=20, choices=TYPE_CHOICES)
    required = models.BooleanField(default=False)
    
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
                fields=['team', 'stage_label', 'deliverable_id'],
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
        if not self.file_name.strip():
            raise ValidationError({'file_name': 'File name is required.'})

    def save(self, *args, **kwargs):
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
            except Exception as e:
                print(f'Warning: PDF extraction failed for {self.file_name}: {e}')
        
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.team} - {self.deliverable_id}'
    
    @property
    def file_url(self):
        """Get the URL for the uploaded file"""
        if self.file:
            return self.file.url
        return None
