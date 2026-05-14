from django.urls import path

from .views import BulkImportTeamsView, StudentTeamDetailView, StudentTeamListCreateView


urlpatterns = [
    path('', StudentTeamListCreateView.as_view(), name='student_teams'),
    path('bulk-import/', BulkImportTeamsView.as_view(), name='student_teams_bulk_import'),
    path('<int:team_id>/', StudentTeamDetailView.as_view(), name='student_team_detail'),
]
