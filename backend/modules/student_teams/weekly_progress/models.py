from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models


class WeeklyReportingPeriod(models.Model):
    """A defense stage's reporting calendar and report identity for one term."""
    semester = models.ForeignKey('academic_period_management.Semester', on_delete=models.PROTECT,
        related_name='weekly_reporting_periods')
    defense_stage = models.ForeignKey('defense.DefenseStage', null=True, blank=True,
        on_delete=models.CASCADE, related_name='weekly_reporting_periods')
    starts_on = models.DateField()
    total_weeks = models.PositiveSmallIntegerField()
    due_weekday = models.PositiveSmallIntegerField(default=6)
    due_time = models.TimeField()

    class Meta:
        app_label = 'student_teams'
        constraints = [models.UniqueConstraint(fields=['defense_stage', 'semester'],
            name='unique_weekly_period_per_stage_term')]


class WeeklyProgressReport(models.Model):
    period = models.ForeignKey(WeeklyReportingPeriod, null=True, blank=True,
        on_delete=models.PROTECT, related_name='reports')
    semester = models.ForeignKey('academic_period_management.Semester', null=True, blank=True,
        on_delete=models.PROTECT, related_name='+')
    project_version = models.PositiveIntegerField(null=True, blank=True)
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
                condition=models.Q(period__isnull=True),
                name='unique_student_weekly_report',
            ),
            models.UniqueConstraint(fields=['team', 'period', 'project_version', 'week_number'],
                condition=models.Q(period__isnull=False), name='unique_managed_team_week'),
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


class WeeklyReportVersion(models.Model):
    report = models.ForeignKey(WeeklyProgressReport, on_delete=models.PROTECT, related_name='versions')
    revision = models.PositiveIntegerField()
    is_current = models.BooleanField(default=True)
    file = models.FileField(upload_to='weekly_reports/versions/%Y/%m/', max_length=255)
    file_name = models.CharField(max_length=255)
    byte_size = models.PositiveBigIntegerField()
    sha256 = models.CharField(max_length=64)
    request_id = models.UUIDField(null=True, blank=True, unique=True)
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='+')
    uploaded_at = models.DateTimeField(auto_now_add=True)
    status = models.CharField(max_length=12, default='pending',
        choices=[('pending', 'Awaiting review'), ('accepted', 'Accepted'), ('rejected', 'Needs correction')])
    feedback = models.TextField(blank=True)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.PROTECT, related_name='+')
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        app_label = 'student_teams'
        ordering = ['-revision']
        constraints = [
            models.UniqueConstraint(fields=['report', 'revision'], name='unique_weekly_report_revision'),
            models.UniqueConstraint(fields=['report'], condition=models.Q(is_current=True),
                name='unique_current_weekly_report_version'),
        ]
