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


@admin.register(TeamMembership)
class TeamMembershipAdmin(admin.ModelAdmin):
    list_display = ('team', 'student', 'is_leader', 'order')
    list_filter = ('is_leader',)
    search_fields = ('team__name', 'student__username', 'student__first_name', 'student__last_name')
