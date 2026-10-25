from django.contrib import admin

from .models import DefenseStage


@admin.register(DefenseStage)
class DefenseStageAdmin(admin.ModelAdmin):
    exclude = ('is_presentation_only',)
    list_display = ('display_order', 'label', 'code', 'is_active', 'updated_at')
    list_filter = ('is_active',)
    search_fields = ('label', 'code', 'description')
    ordering = ('display_order', 'label')
