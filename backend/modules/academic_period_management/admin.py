from django.contrib import admin

from .models import SchoolYear, Semester, SemesterTransitionLog


class SemesterInline(admin.TabularInline):
    model = Semester
    extra = 0


@admin.register(SchoolYear)
class SchoolYearAdmin(admin.ModelAdmin):
    list_display = ('label', 'semester_count', 'created_at')
    search_fields = ('label',)
    inlines = [SemesterInline]

    def semester_count(self, obj):
        return obj.semesters.count()


@admin.register(Semester)
class SemesterAdmin(admin.ModelAdmin):
    list_display = ('label', 'school_year', 'is_active', 'created_at')
    list_filter = ('is_active', 'label')
    search_fields = ('label', 'school_year__label')


@admin.register(SemesterTransitionLog)
class SemesterTransitionLogAdmin(admin.ModelAdmin):
    list_display = ('from_semester', 'to_semester', 'changed_by', 'forced', 'created_at')
    list_filter = ('forced', 'created_at')
    search_fields = (
        'from_semester__label',
        'from_semester__school_year__label',
        'to_semester__label',
        'to_semester__school_year__label',
        'changed_by__username',
    )
    readonly_fields = (
        'from_semester',
        'to_semester',
        'changed_by',
        'forced',
        'reason',
        'impact_snapshot',
        'created_at',
    )
