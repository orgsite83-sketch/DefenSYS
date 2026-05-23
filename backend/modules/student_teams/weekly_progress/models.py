from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class WeeklyProgressReport(models.Model):
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
    accomplishments = models.JSONField(default=list, blank=True)
    contributions = models.JSONField(default=list, blank=True)
    issues = models.JSONField(default=list, blank=True)
    plans = models.JSONField(default=list, blank=True)
    report_file = models.FileField(upload_to='weekly_reports/%Y/%m/', blank=True, null=True)
    file_size = models.CharField(max_length=50, blank=True, null=True)
    extracted_text = models.TextField(
        blank=True,
        default='',
        help_text='Full text extracted from PDF for ML search',
    )
    topics = models.JSONField(
        blank=True,
        default=list,
        help_text='Auto-extracted keywords/topics from PDF content',
    )
    summary = models.TextField(
        blank=True,
        default='',
        help_text='Auto-generated summary of PDF content',
    )
    submitted_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'student_teams'
        db_table = 'student_weekly_progress_weeklyprogressreport'
        ordering = ['-report_date', '-week_number']
        constraints = [
            models.UniqueConstraint(
                fields=['student', 'team', 'week_number'],
                name='unique_student_weekly_report',
            ),
        ]
        indexes = [
            models.Index(fields=['student', 'report_date'], name='student_wee_student_059a10_idx'),
            models.Index(fields=['team', 'report_date'], name='student_wee_team_id_0cb02e_idx'),
        ]

    def clean(self):
        if self.student_id and getattr(self.student, 'role', None) != 'student':
            raise ValidationError({'student': 'Only students can submit progress reports.'})

    def save(self, *args, **kwargs):
        self.full_clean()

        if self.report_file and not self.extracted_text:
            from repository.deliverables.pdf_processor import extract_pdf_content

            try:
                result = extract_pdf_content(self.report_file.path)
                self.extracted_text = result.get('text', '')
                self.topics = result.get('topics', [])
                self.summary = result.get('summary', '')
            except Exception as e:
                print(f'PDF extraction failed for weekly report: {e}')

        super().save(*args, **kwargs)

    def __str__(self):
        return f'{self.student.username} - Week {self.week_number} ({self.report_date})'
