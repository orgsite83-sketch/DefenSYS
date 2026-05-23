from django.contrib import admin

from .models import DeliverableSubmission


@admin.register(DeliverableSubmission)
class DeliverableSubmissionAdmin(admin.ModelAdmin):
    list_display = (
        'team',
        'stage_label',
        'deliverable_id',
        'deliverable_type',
        'required',
        'file_name',
        'uploaded_by',
        'uploaded_at',
    )
    list_filter = ('stage_label', 'deliverable_type', 'required')
    search_fields = ('team__name', 'team__project_title', 'deliverable_id', 'label', 'file_name')
