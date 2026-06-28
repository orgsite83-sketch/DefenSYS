from django.contrib import admin
from .models import DefenseMinutes, MinutesPanelistComment

class MinutesPanelistCommentInline(admin.TabularInline):
    model = MinutesPanelistComment
    extra = 0
    raw_id_fields = ('panelist',)

@admin.register(DefenseMinutes)
class DefenseMinutesAdmin(admin.ModelAdmin):
    list_display = ('team_name', 'defense_stage_label', 'status', 'defense_date', 'defense_time', 'room', 'created_at')
    list_filter = ('status', 'defense_date', 'defense_stage_label')
    search_fields = ('team_name', 'project_title', 'adviser_name', 'documenter_name')
    raw_id_fields = ('schedule', 'documenter_signed_by', 'adviser_signed_by', 'chairman_signed_by')
    inlines = [MinutesPanelistCommentInline]

@admin.register(MinutesPanelistComment)
class MinutesPanelistCommentAdmin(admin.ModelAdmin):
    list_display = ('minutes', 'panelist_name_snapshot', 'panelist_role_snapshot', 'display_order')
    search_fields = ('panelist_name_snapshot', 'comments')
    raw_id_fields = ('minutes', 'panelist')
