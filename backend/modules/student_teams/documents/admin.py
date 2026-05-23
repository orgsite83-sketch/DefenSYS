from django.contrib import admin

from .models import TeamDocument


@admin.register(TeamDocument)
class TeamDocumentAdmin(admin.ModelAdmin):
    list_display = ['file_name', 'team', 'document_type', 'uploaded_by', 'file_size_mb', 'uploaded_at']
    list_filter = ['document_type', 'uploaded_at']
    search_fields = ['file_name', 'team__name', 'uploaded_by__username']
    readonly_fields = ['uploaded_at', 'updated_at', 'file_size_mb']
