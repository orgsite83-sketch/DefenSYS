from django.urls import path

from .views import (
    AcademicPeriodListCreateView,
    SchoolYearDetailView,
    SemesterActivateView,
    SemesterCreateView,
    SemesterCreatePreviewView,
    SemesterStatusView,
    SemesterTransitionPreviewView,
    ReturningTeamsView,
)


urlpatterns = [
    path('semesters/<int:semester_id>/returning-teams/', ReturningTeamsView.as_view(), name='academic_period_returning_teams'),
    path('', AcademicPeriodListCreateView.as_view(), name='academic_periods'),
    path('<int:school_year_id>/', SchoolYearDetailView.as_view(), name='academic_period_detail'),
    path('<int:school_year_id>/semesters/', SemesterCreateView.as_view(), name='academic_period_semesters'),
    path('<int:school_year_id>/semesters/transition-preview/', SemesterCreatePreviewView.as_view(), name='academic_period_create_preview'),
    path('semesters/<int:semester_id>/transition-preview/', SemesterTransitionPreviewView.as_view(), name='academic_period_semester_transition_preview'),
    path('semesters/<int:semester_id>/activate/', SemesterActivateView.as_view(), name='academic_period_semester_activate'),
    path('semesters/<int:semester_id>/', SemesterStatusView.as_view(), name='academic_period_semester_status'),
]
