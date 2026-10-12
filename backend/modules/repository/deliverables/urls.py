from django.urls import path

from .views import (
    CapstoneDeliverableEndorseView,
    CapstoneDeliverableUnendorseView,
    CapstoneDeliverableRemoveView,
    CapstoneDeliverableUploadView,
    CapstoneDeliverablesListView,
    CompileWeeklyReportsView,
    CapstoneDeliverableReviewView,
    CapstoneDeliverableUnlockView,
    StageFileAccessView,
)


urlpatterns = [
    path('', CapstoneDeliverablesListView.as_view(), name='capstone_deliverables'),
    path('upload/', CapstoneDeliverableUploadView.as_view(), name='capstone_deliverable_upload'),
    path('remove/', CapstoneDeliverableRemoveView.as_view(), name='capstone_deliverable_remove'),
    path('endorse/', CapstoneDeliverableEndorseView.as_view(), name='capstone_deliverable_endorse'),
    path('unendorse/', CapstoneDeliverableUnendorseView.as_view(), name='capstone_deliverable_unendorse'),
    path('review/', CapstoneDeliverableReviewView.as_view(), name='capstone_deliverable_review'),
    path('unlock/', CapstoneDeliverableUnlockView.as_view(), name='capstone_deliverable_unlock'),
    path('stage-access/', StageFileAccessView.as_view(), name='stage_file_access'),
    path('compile-weekly-reports/', CompileWeeklyReportsView.as_view(), name='compile_weekly_reports'),
]
