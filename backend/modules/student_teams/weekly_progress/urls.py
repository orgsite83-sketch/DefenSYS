from django.urls import path

from .views import (
    StudentWeeklyProgressDetailView,
    StudentWeeklyProgressListCreateView,
    WeeklyProgressReportFileView,
)


urlpatterns = [
    path('', StudentWeeklyProgressListCreateView.as_view(), name='weekly-progress-list-create'),
    path('<int:pk>/', StudentWeeklyProgressDetailView.as_view(), name='weekly-progress-detail'),
    path('<int:pk>/file/', WeeklyProgressReportFileView.as_view(), name='weekly-progress-file'),
]
