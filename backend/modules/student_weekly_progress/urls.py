from django.urls import path
from .views import (
    StudentWeeklyProgressListCreateView,
    StudentWeeklyProgressDetailView,
    WeeklyProgressReportFileView,
)

urlpatterns = [
    path('', StudentWeeklyProgressListCreateView.as_view(), name='weekly-progress-list-create'),
    path('<int:pk>/', StudentWeeklyProgressDetailView.as_view(), name='weekly-progress-detail'),
    path('<int:pk>/file/', WeeklyProgressReportFileView.as_view(), name='weekly-progress-file'),
]
