from django.urls import path
from .concept_views import ConceptActionView

from .views import (
    CapstoneDeliverableEndorseView,
    ReviewEndorseView,
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
    path('concepts/', ConceptActionView.as_view(), name='deliverable_concepts'),
    path('', CapstoneDeliverablesListView.as_view(), name='capstone_deliverables'),
    path('upload/', CapstoneDeliverableUploadView.as_view(), name='capstone_deliverable_upload'),
    path('remove/', CapstoneDeliverableRemoveView.as_view(), name='capstone_deliverable_remove'),
    path('endorse/', CapstoneDeliverableEndorseView.as_view(), name='capstone_deliverable_endorse'),
    path('review-endorse/', ReviewEndorseView.as_view(), name='deliverable_review_endorse'),
    path('unendorse/', CapstoneDeliverableUnendorseView.as_view(), name='capstone_deliverable_unendorse'),
    path('review/', CapstoneDeliverableReviewView.as_view(), name='capstone_deliverable_review'),
    path('unlock/', CapstoneDeliverableUnlockView.as_view(), name='capstone_deliverable_unlock'),
    path('stage-access/', StageFileAccessView.as_view(), name='stage_file_access'),
    path('compile-weekly-reports/', CompileWeeklyReportsView.as_view(), name='compile_weekly_reports'),
]
