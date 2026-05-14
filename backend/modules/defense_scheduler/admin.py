from django.contrib import admin
from django.contrib import messages

from .models import DefenseSchedule, SchedulePanelist


class SchedulePanelistInline(admin.TabularInline):
    model = SchedulePanelist
    extra = 0


def cancel_schedules(modeladmin, request, queryset):
    """Cancel selected schedules"""
    updated = queryset.update(status=DefenseSchedule.STATUS_CANCELLED)
    messages.success(request, f'{updated} schedule(s) cancelled successfully.')
cancel_schedules.short_description = "Cancel selected schedules"


def mark_as_done(modeladmin, request, queryset):
    """Mark selected schedules as done"""
    updated = queryset.update(status=DefenseSchedule.STATUS_DONE)
    messages.success(request, f'{updated} schedule(s) marked as done.')
mark_as_done.short_description = "Mark selected schedules as done"


def reactivate_schedules(modeladmin, request, queryset):
    """Reactivate cancelled schedules"""
    updated = queryset.update(status=DefenseSchedule.STATUS_SCHEDULED)
    messages.success(request, f'{updated} schedule(s) reactivated.')
reactivate_schedules.short_description = "Reactivate selected schedules"


@admin.register(DefenseSchedule)
class DefenseScheduleAdmin(admin.ModelAdmin):
    list_display = [
        'team',
        'stage_label',
        'scope',
        'scheduled_date',
        'start_time',
        'room',
        'status',
    ]
    list_filter = ['scope', 'status', 'scheduled_date']
    search_fields = ['team__name', 'team__project_title', 'room', 'event_name', 'defense_stage__label']
    inlines = [SchedulePanelistInline]
    actions = [cancel_schedules, mark_as_done, reactivate_schedules]
