from django.urls import path
from .views import (
    AdminDashboardView,
    FacultyDashboardView,
    PanelistDashboardView,
    PitLeadCohortView,
    PitLeadCohortRolloverConfirmView,
    PitLeadCohortRolloverPreviewView,
    PitLeadRepositoryAssistantView,
    StudentDashboardView,
)

urlpatterns = [
    path('admin/', AdminDashboardView.as_view(), name='dashboard_admin'),
    path('pit-lead/cohort/', PitLeadCohortView.as_view(), name='dashboard_pit_lead_cohort'),
    path(
        'pit-lead/cohort/rollover-preview/',
        PitLeadCohortRolloverPreviewView.as_view(),
        name='dashboard_pit_lead_cohort_rollover_preview',
    ),
    path(
        'pit-lead/cohort/rollover/',
        PitLeadCohortRolloverConfirmView.as_view(),
        name='dashboard_pit_lead_cohort_rollover',
    ),
    path(
        'pit-lead/repository-assistant/',
        PitLeadRepositoryAssistantView.as_view(),
        name='dashboard_pit_lead_repository_assistant',
    ),
    path('faculty/', FacultyDashboardView.as_view(), name='dashboard_faculty'),
    path('student/', StudentDashboardView.as_view(), name='dashboard_student'),
    path('panelist/', PanelistDashboardView.as_view(), name='dashboard_panelist'),
]
