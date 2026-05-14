from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class WeeklyProgressReport(models.Model):
    """Individual student weekly progress report"""
    
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='weekly_progress_reports',
        on_delete=models.CASCADE,
    )
    team = models.ForeignKey(
        'student_teams.StudentTeam',
        related_name='student_progress_reports',
        on_delete=models.CASCADE,
    )
    week_number = models.PositiveSmallIntegerField()
    report_date = models.DateField()
    
    # Report content (legacy - kept for backward compatibility)
    accomplishments = models.JSONField(default=list, blank=True)  # List of tasks
    contributions = models.JSONField(default=list, blank=True)  # Individual contributions
    issues = models.JSONField(default=list, blank=True)  # Issues encountered
    plans = models.JSONField(default=list, blank=True)  # Plans for next week
    
    # File upload (new method)
    report_file = models.FileField(upload_to='weekly_reports/%Y/%m/', blank=True, null=True)  # Actual file
    file_size = models.CharField(max_length=50, blank=True, null=True)  # File size
    
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
    
    # Metadata
    submitted_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['-report_date', '-week_number']
        constraints = [
            models.UniqueConstraint(
                fields=['student', 'team', 'week_number'],
                name='unique_student_weekly_report',
            ),
        ]
        indexes = [
            models.Index(fields=['student', 'report_date']),
            models.Index(fields=['team', 'report_date']),
        ]
    
    def clean(self):
        if self.student_id and getattr(self.student, 'role', None) != 'student':
            raise ValidationError({'student': 'Only students can submit progress reports.'})
    
    def save(self, *args, **kwargs):
        self.full_clean()
        
        # Extract PDF content if file exists and hasn't been extracted yet
        if self.report_file and not self.extracted_text:
            from capstone_deliverables.pdf_processor import extract_pdf_content
            try:
                result = extract_pdf_content(self.report_file.path)
                self.extracted_text = result.get('text', '')
                self.topics = result.get('topics', [])
                self.summary = result.get('summary', '')
            except Exception as e:
                print(f'⚠️ PDF extraction failed for weekly report: {e}')
        
        super().save(*args, **kwargs)
    
    def __str__(self):
        return f'{self.student.username} - Week {self.week_number} ({self.report_date})'
