from django.contrib import admin

from .models import VaultEntry


@admin.register(VaultEntry)
class VaultEntryAdmin(admin.ModelAdmin):
    list_display = (
        'file_name',
        'entry_type',
        'team_name',
        'year_level',
        'academic_year',
        'status',
        'uploaded_at',
    )
    list_filter = ('entry_type', 'year_level', 'academic_year', 'status')
    search_fields = ('file_name', 'team_name', 'course_code', 'stage_label')
    readonly_fields = ('created_at', 'updated_at')
