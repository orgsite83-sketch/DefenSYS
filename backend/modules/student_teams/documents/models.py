from django.conf import settings
from django.db import models

from student_teams.models import StudentTeam


class TeamDocument(models.Model):
    DOCUMENT_TYPES = (
        ('proposal', 'Project Proposal'),
        ('documentation', 'Documentation'),
        ('presentation', 'Presentation'),
        ('report', 'Report'),
        ('other', 'Other'),
    )

    team = models.ForeignKey(StudentTeam, on_delete=models.CASCADE, related_name='documents')
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name='uploaded_documents',
    )
    document_type = models.CharField(max_length=50, choices=DOCUMENT_TYPES, default='other')
    file = models.FileField(
        upload_to='team_documents/%Y/%m/',
        null=True,
        blank=True,
        help_text='Uploaded document file',
    )
    file_name = models.CharField(max_length=255)
    file_data = models.BinaryField(null=True, blank=True)
    file_size = models.IntegerField()
    mime_type = models.CharField(max_length=100)
    description = models.TextField(blank=True, null=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = 'student_teams'
        db_table = 'team_documents_teamdocument'
        ordering = ['-uploaded_at']

    def __str__(self):
        return f'{self.file_name} - {self.team.name}'

    @property
    def file_size_mb(self):
        return round(self.file_size / (1024 * 1024), 2)

    @property
    def file_url(self):
        if self.file:
            return self.file.url
        return None
