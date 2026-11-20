from django.urls import path

from .adviser_views import AdviserGradeListView, AdviserSubmitGradeView
from .peer_views import StudentPeerEvaluationSubmitView
from .dissemination_views import OutcomePreviewView, OutcomeConfirmView, OutcomeHoldView, OutcomeHistoryView
from .views import (
    CapstoneEvaluationSettingsView,
    GradeCenterDetailView,
    GradeCorrectionsView,
    GradeCenterGroupSettingsView,
    GradeCenterListView,
    GradeMasterlistView,
    GradeCenterPublishView,
    GradeCenterSyncView,
    TeamGradeVerdictView,
    TeamGradeWorkflowView,
    TeamGradeAssessmentView,
    TeamGradePanelDecisionView,
    PanelDecisionCorrectionView,
)


urlpatterns = [
    path('<int:grade_id>/panel-decision/correction/', PanelDecisionCorrectionView.as_view()),
    path('<int:grade_id>/panel-decision/', TeamGradePanelDecisionView.as_view(), name='panel_decision'),
    path('outcome-dissemination/preview/', OutcomePreviewView.as_view()),
    path('outcome-dissemination/confirm/', OutcomeConfirmView.as_view()),
    path('outcome-dissemination/history/', OutcomeHistoryView.as_view()),
    path('<int:grade_id>/outcome-dissemination/hold/', OutcomeHoldView.as_view()),
    path('', GradeCenterListView.as_view(), name='grade_center'),
    path('masterlist/', GradeMasterlistView.as_view(), name='grade_masterlist'),
    path('sync/', GradeCenterSyncView.as_view(), name='grade_center_sync'),
    path(
        'evaluation-settings/',
        CapstoneEvaluationSettingsView.as_view(),
        name='grade_center_evaluation_settings',
    ),
    path(
        'group-settings/',
        GradeCenterGroupSettingsView.as_view(),
        name='grade_center_group_settings',
    ),
    path('<int:grade_id>/', GradeCenterDetailView.as_view(), name='grade_center_detail'),
    path('<int:grade_id>/corrections/', GradeCorrectionsView.as_view(), name='grade_corrections'),
    path('<int:grade_id>/publish/', GradeCenterPublishView.as_view(), name='grade_center_publish'),
    path('<int:grade_id>/verdict/', TeamGradeVerdictView.as_view(), name='team_grade_verdict'),
    path('<int:grade_id>/workflow/', TeamGradeWorkflowView.as_view(), name='team_grade_workflow'),
    path('<int:grade_id>/assessment/', TeamGradeAssessmentView.as_view(), name='team_grade_assessment'),
    # Adviser-specific grading endpoints
    path('adviser-grades/', AdviserGradeListView.as_view(), name='adviser_grade_list'),
    path('adviser-grades/<int:grade_id>/submit/', AdviserSubmitGradeView.as_view(), name='adviser_grade_submit'),
    path(
        'peer-evaluations/',
        StudentPeerEvaluationSubmitView.as_view(),
        name='student_peer_evaluation_submit',
    ),
]
