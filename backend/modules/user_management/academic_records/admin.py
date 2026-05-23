from django.contrib import admin

from .models import StudentAcademicRecord


@admin.register(StudentAcademicRecord)
class StudentAcademicRecordAdmin(admin.ModelAdmin):
    list_display = ('student', 'year_level', 'semester', 'action', 'created_at')
    list_filter = ('year_level', 'semester__label', 'semester__school_year__label', 'action')
    search_fields = ('student__username', 'student__first_name', 'student__last_name', 'student__email')
