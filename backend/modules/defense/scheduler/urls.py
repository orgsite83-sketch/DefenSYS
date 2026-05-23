from django.urls import path

from .views import (
    DefenseScheduleConfirmPlanView,
    DefenseScheduleDetailView,
    DefenseScheduleGeneratePlanView,
    DefenseScheduleListCreateView,
    PanelistAssignmentsView,
    PanelistGradeSubmissionView,
    PitEventConfigLookupView,
)


urlpatterns = [
    path('', DefenseScheduleListCreateView.as_view(), name='defense_schedules'),
    path('pit-event-config/', PitEventConfigLookupView.as_view(), name='defense_pit_event_config'),
    path('generate-plan/', DefenseScheduleGeneratePlanView.as_view(), name='defense_schedule_generate_plan'),
    path('confirm-plan/', DefenseScheduleConfirmPlanView.as_view(), name='defense_schedule_confirm_plan'),
    path('panelist-assignments/', PanelistAssignmentsView.as_view(), name='panelist_assignments'),
    path('submit-grades/', PanelistGradeSubmissionView.as_view(), name='panelist_grade_submission'),
    path('<int:schedule_id>/', DefenseScheduleDetailView.as_view(), name='defense_schedule_detail'),
]
