from django.contrib import admin

from .models import GuestPanelistCode


@admin.register(GuestPanelistCode)
class GuestPanelistCodeAdmin(admin.ModelAdmin):
    list_display = [
        'code',
        'guest_name',
        'defense_schedule',
        'is_active',
        'created_by',
        'created_at',
    ]
    list_filter = ['is_active', 'created_at']
    search_fields = ['code', 'guest_name', 'email', 'defense_schedule__team__name']
    readonly_fields = ['code', 'created_at', 'updated_at']
