from django.contrib import admin

from .models import RepositoryAuditLog


@admin.register(RepositoryAuditLog)
class RepositoryAuditLogAdmin(admin.ModelAdmin):
    list_display = ('file_name', 'entry_type', 'action', 'previous_status', 'new_status', 'actor', 'created_at')
    list_filter = ('entry_type', 'action', 'new_status')
    search_fields = ('file_name', 'message', 'actor__username')
    readonly_fields = ('created_at',)
