from django.db import models
from django.contrib.auth import get_user_model
from student_teams.models import StudentTeam

User = get_user_model()


class TeamDocument(models.Model):
    """Model to store uploaded documents for teams"""
    
    DOCUMENT_TYPES = (
        ('proposal', 'Project Proposal'),
        ('documentation', 'Documentation'),
        ('presentation', 'Presentation'),
        ('report', 'Report'),
        ('other', 'Other'),
    )
    
    team = models.ForeignKey(StudentTeam, on_delete=models.CASCADE, related_name='documents')
    uploaded_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='uploaded_documents')
    
    document_type = models.CharField(max_length=50, choices=DOCUMENT_TYPES, default='other')
    
    # Actual file storage
    file = models.FileField(
        upload_to='team_documents/%Y/%m/',
        null=True,
        blank=True,
        help_text='Uploaded document file'
    )
    
    # Metadata (kept for backward compatibility and display)
    file_name = models.CharField(max_length=255)
    file_data = models.BinaryField(null=True, blank=True)  # Deprecated - kept for backward compatibility
    file_size = models.IntegerField()  # Size in bytes
    mime_type = models.CharField(max_length=100)
    
    description = models.TextField(blank=True, null=True)
    
    uploaded_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['-uploaded_at']
        
    def __str__(self):
        return f"{self.file_name} - {self.team.name}"
    
    @property
    def file_size_mb(self):
        """Return file size in MB"""
        return round(self.file_size / (1024 * 1024), 2)
    
    @property
    def file_url(self):
        """Get the URL for the uploaded file"""
        if self.file:
            return self.file.url
        return None
