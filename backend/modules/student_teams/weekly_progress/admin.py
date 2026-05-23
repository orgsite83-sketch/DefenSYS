from django.contrib import admin

from .models import WeeklyProgressReport


@admin.register(WeeklyProgressReport)
class WeeklyProgressReportAdmin(admin.ModelAdmin):
    list_display = ['student', 'team', 'week_number', 'report_date', 'submitted_at']
    list_filter = ['report_date', 'team']
    search_fields = ['student__username', 'student__first_name', 'student__last_name', 'team__name']
    readonly_fields = ['submitted_at', 'updated_at']
    date_hierarchy = 'report_date'
