from django.urls import path

from .views import (
    StudentWeeklyProgressDetailView,
    StudentWeeklyProgressListCreateView,
    WeeklyProgressReportFileView,
    WeeklyReportCollectionView, WeeklyReportReviewView, WeeklyReportVersionsView,
)


urlpatterns = [
    path('collection/', WeeklyReportCollectionView.as_view(), name='weekly-report-collection'),
    path('collection/review/', WeeklyReportReviewView.as_view(), name='weekly-report-review'),
    path('<int:pk>/versions/', WeeklyReportVersionsView.as_view(), name='weekly-report-versions'),
    path('', StudentWeeklyProgressListCreateView.as_view(), name='weekly-progress-list-create'),
    path('<int:pk>/', StudentWeeklyProgressDetailView.as_view(), name='weekly-progress-detail'),
    path('<int:pk>/file/', WeeklyProgressReportFileView.as_view(), name='weekly-progress-file'),
]
