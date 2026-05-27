from django.urls import path

from .views import (
    AcademicPeriodListCreateView,
    SemesterActivateView,
    SemesterCreateView,
    SemesterStatusView,
    SemesterTransitionPreviewView,
)


urlpatterns = [
    path('', AcademicPeriodListCreateView.as_view(), name='academic_periods'),
    path('<int:school_year_id>/semesters/', SemesterCreateView.as_view(), name='academic_period_semesters'),
    path('semesters/<int:semester_id>/transition-preview/', SemesterTransitionPreviewView.as_view(), name='academic_period_semester_transition_preview'),
    path('semesters/<int:semester_id>/activate/', SemesterActivateView.as_view(), name='academic_period_semester_activate'),
    path('semesters/<int:semester_id>/', SemesterStatusView.as_view(), name='academic_period_semester_status'),
]
