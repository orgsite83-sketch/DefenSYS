from django.urls import include, path

from .views import (
    BulkImportTeamsPreviewView,
    BulkImportTeamsView,
    StudentTeamDetailView,
    StudentTeamListCreateView,
    TeamAdviserHistoryView,
    SectionAssignmentListCreateView,
    SectionAssignmentDetailView,
)


urlpatterns = [
    path('documents/', include('student_teams.documents.urls')),
    path('weekly-progress/', include('student_teams.weekly_progress.urls')),
    path('section-assignments/', SectionAssignmentListCreateView.as_view(), name='section_assignment_list_create'),
    path('section-assignments/<int:pk>/', SectionAssignmentDetailView.as_view(), name='section_assignment_detail'),
    path('', StudentTeamListCreateView.as_view(), name='student_teams'),
    path('bulk-import/preview/', BulkImportTeamsPreviewView.as_view(), name='student_teams_bulk_import_preview'),
    path('bulk-import/', BulkImportTeamsView.as_view(), name='student_teams_bulk_import'),
    path('<int:team_id>/adviser-history/', TeamAdviserHistoryView.as_view(), name='team_adviser_history'),
    path('<int:team_id>/', StudentTeamDetailView.as_view(), name='student_team_detail'),
]
