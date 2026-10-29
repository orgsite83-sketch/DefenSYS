from django.urls import include, path
from .participation_views import StudentParticipationHistoryView, ReuseCapstoneRosterView
from .roster_views import CurrentRosterView
from .roster_workspace_views import (RosterWorkspaceView, RosterPreviewView, RosterApplyView,
    RosterProjectSetupView, EventTeamSetupView, RosterExportView)
from .formation_views import (TeamFormationView, TeamFormationCommitView, PitTeamPolicyView,
                              MyTeamSetupView, TeamLeaderSetupView, TeamRosterOptionsView)
from .formation_workspace import (TeamCreationContextView, SectionRosterPreviewView,
    SectionRosterCommitView, PreparedTeamsPreviewView, PreparedTeamsCommitView)

from .views import (
    BulkImportTeamsPreviewView,
    BulkImportTeamsView,
    StudentTeamDetailView,
    StudentTeamListCreateView,
    TeamAdviserHistoryView,
    SectionAssignmentListCreateView,
    SectionAssignmentDetailView,
    SectionDetailsView,
    StudentTeamSendReminderView,
)


urlpatterns = [
    path('students/<int:student_id>/capstone-history/', StudentParticipationHistoryView.as_view(), name='student_capstone_history'),
    path('<int:team_id>/reuse-roster/', ReuseCapstoneRosterView.as_view(), name='reuse_capstone_roster'),
    path('rosters/', RosterWorkspaceView.as_view(), name='pit_roster_workspace'),
    path('rosters/preview/', RosterPreviewView.as_view(), name='pit_roster_preview'),
    path('rosters/apply/', RosterApplyView.as_view(), name='pit_roster_apply'),
    path('rosters/project-setup/', RosterProjectSetupView.as_view(), name='pit_roster_project_setup'),
    path('rosters/export/', RosterExportView.as_view(), name='pit_roster_export'),
    path('<int:team_id>/events/<int:event_id>/setup/', EventTeamSetupView.as_view(), name='pit_event_team_setup'),
    path('current-roster/', CurrentRosterView.as_view(), name='current_roster'),
    path('roster-options/', TeamRosterOptionsView.as_view(), name='team_roster_options'),
    path('generation/context/', TeamCreationContextView.as_view(), name='team_creation_context'),
    path('generation/roster/', SectionRosterPreviewView.as_view(), name='section_roster_preview'),
    path('generation/roster/create/', SectionRosterCommitView.as_view(), name='section_roster_commit'),
    path('generation/import/', PreparedTeamsPreviewView.as_view(), name='prepared_teams_preview'),
    path('generation/import/create/', PreparedTeamsCommitView.as_view(), name='prepared_teams_commit'),
    path('generation/', TeamFormationView.as_view(), name='team_formation'),
    path('generation/create/', TeamFormationCommitView.as_view(), name='team_formation_create'),
    path('generation/events/<int:event_id>/policy/', PitTeamPolicyView.as_view(), name='pit_team_policy'),
    path('my-setup/', MyTeamSetupView.as_view(), name='my_team_setup'),
    path('<int:team_id>/setup/', TeamLeaderSetupView.as_view(), name='team_leader_setup'),
    path('documents/', include('student_teams.documents.urls')),
    path('weekly-progress/', include('student_teams.weekly_progress.urls')),
    path('section-assignments/', SectionAssignmentListCreateView.as_view(), name='section_assignment_list_create'),
    path('section-assignments/<int:pk>/', SectionAssignmentDetailView.as_view(), name='section_assignment_detail'),
    path('', StudentTeamListCreateView.as_view(), name='student_teams'),
    path('bulk-import/preview/', BulkImportTeamsPreviewView.as_view(), name='student_teams_bulk_import_preview'),
    path('bulk-import/', BulkImportTeamsView.as_view(), name='student_teams_bulk_import'),
    path('<int:team_id>/remind/', StudentTeamSendReminderView.as_view(), name='student_team_send_reminder'),
    path('<int:team_id>/adviser-history/', TeamAdviserHistoryView.as_view(), name='team_adviser_history'),
    path('<int:team_id>/section/', SectionDetailsView.as_view(), name='team_section_details'),
    path('<int:team_id>/', StudentTeamDetailView.as_view(), name='student_team_detail'),
]
