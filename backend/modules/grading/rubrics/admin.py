from django.contrib import admin

from .models import Rubric, RubricCriterion


class RubricCriterionInline(admin.TabularInline):
    model = RubricCriterion
    extra = 0


@admin.register(Rubric)
class RubricAdmin(admin.ModelAdmin):
    list_display = [
        'name',
        'scope',
        'evaluation_type',
        'status',
        'semester',
        'context_label',
        'is_locked',
    ]
    list_filter = ['scope', 'evaluation_type', 'status', 'is_locked']
    search_fields = ['name', 'event_name', 'defense_stage__label', 'semester__school_year__label']
    inlines = [RubricCriterionInline]
