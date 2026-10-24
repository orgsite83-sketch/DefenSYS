from django.contrib import admin

from .models import StudentTeam, TeamMembership


class TeamMembershipInline(admin.TabularInline):
    model = TeamMembership
    extra = 0


@admin.register(StudentTeam)
class StudentTeamAdmin(admin.ModelAdmin):
    list_display = ('name', 'level', 'year_level', 'semester', 'status', 'adviser')
    list_filter = ('level', 'year_level', 'status', 'semester__label')
    search_fields = ('name', 'project_title', 'leader__username', 'adviser__username')
    inlines = [TeamMembershipInline]

    def get_readonly_fields(self, request, obj=None):
        if obj and obj.is_capstone:
            return ('semester', 'capstone_phase', 'project_version', 'status',
                    'ready_for_stage', 'current_defense_stage', 'unlocked_stages')
        return ()

    def has_delete_permission(self, request, obj=None):
        if obj and obj.term_participations.filter(closed_at__isnull=False).exists():
            return False
        return super().has_delete_permission(request, obj)


@admin.register(TeamMembership)
class TeamMembershipAdmin(admin.ModelAdmin):
    list_display = ('team', 'student', 'is_leader', 'order')
    list_filter = ('is_leader',)
    search_fields = ('team__name', 'student__username', 'student__first_name', 'student__last_name')
