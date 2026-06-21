from django.contrib import admin

from .models import GradeBreakdown, StudentStageGrade, TeamGrade


class GradeBreakdownInline(admin.TabularInline):
    model = GradeBreakdown
    extra = 0


class StudentStageGradeInline(admin.TabularInline):
    model = StudentStageGrade
    extra = 0


@admin.register(TeamGrade)
class TeamGradeAdmin(admin.ModelAdmin):
    list_display = (
        'team',
        'scope',
        'stage_label',
        'defense_stage',
        'pit_event_config',
        'panel_score',
        'adviser_score',
        'peer_score',
        'final_grade',
        'status',
    )
    list_filter = ('scope', 'status', 'semester', 'defense_stage', 'pit_event_config')
    search_fields = ('team__name', 'team__project_title', 'stage_label')
    inlines = [GradeBreakdownInline, StudentStageGradeInline]
