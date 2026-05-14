from django.urls import path

from .views import (
    CapstoneDeliverableDemoFillView,
    CapstoneDeliverableEndorseView,
    CapstoneDeliverableRemoveView,
    CapstoneDeliverableUploadView,
    CapstoneDeliverablesListView,
    CompileWeeklyReportsView,
)


urlpatterns = [
    path('', CapstoneDeliverablesListView.as_view(), name='capstone_deliverables'),
    path('upload/', CapstoneDeliverableUploadView.as_view(), name='capstone_deliverable_upload'),
    path('remove/', CapstoneDeliverableRemoveView.as_view(), name='capstone_deliverable_remove'),
    path('endorse/', CapstoneDeliverableEndorseView.as_view(), name='capstone_deliverable_endorse'),
    path('demo-fill/', CapstoneDeliverableDemoFillView.as_view(), name='capstone_deliverable_demo_fill'),
    path('compile-weekly-reports/', CompileWeeklyReportsView.as_view(), name='compile_weekly_reports'),
]
