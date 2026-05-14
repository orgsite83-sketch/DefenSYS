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
        ordering = ['stage_label', 'deliverable_id']
        constraints = [
            models.UniqueConstraint(
                fields=['team', 'stage_label', 'deliverable_id'],
                name='unique_deliverable_submission_per_team_stage',
            ),
        ]
        indexes = [
            models.Index(fields=['stage_label', 'deliverable_type']),
            models.Index(fields=['deliverable_id']),
        ]

    def clean(self):
        if self.team_id and not self.team.is_capstone:
            raise ValidationError({'team': 'Only Capstone teams can submit Capstone deliverables.'})
        if not self.file_name.strip():
            raise ValidationError({'file_name': 'File name is required.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        
        # Extract PDF content if file exists and hasn't been extracted yet
        if self.file and not self.extracted_text:
            from .pdf_processor import extract_pdf_content
            try:
                result = extract_pdf_content(self.file.path, classify=True)
                self.extracted_text = result.get('text', '')
                self.topics = result.get('topics', [])
                self.summary = result.get('summary', '')
                self.category = result.get('category', '')
                self.category_confidence = result.get('classification', {}).get('confidence_score')
            except Exception as e:
                print(f'⚠️ PDF extraction failed for {self.file_name}: {e}')
        
        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.team} - {self.deliverable_id}'
    
    @property
    def file_url(self):
        """Get the URL for the uploaded file"""
        if self.file:
            return self.file.url
        return None
