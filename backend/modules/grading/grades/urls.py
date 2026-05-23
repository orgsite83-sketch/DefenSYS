from django.urls import path

from .adviser_views import AdviserGradeListView, AdviserSubmitGradeView
from .peer_views import StudentPeerEvaluationSubmitView
from .views import (
    CapstoneEvaluationSettingsView,
    GradeCenterDetailView,
    GradeCenterGroupSettingsView,
    GradeCenterListView,
    GradeCenterPublishView,
    GradeCenterSyncView,
)


urlpatterns = [
    path('', GradeCenterListView.as_view(), name='grade_center'),
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
    path('<int:grade_id>/publish/', GradeCenterPublishView.as_view(), name='grade_center_publish'),
    # Adviser-specific grading endpoints
    path('adviser-grades/', AdviserGradeListView.as_view(), name='adviser_grade_list'),
    path('adviser-grades/<int:grade_id>/submit/', AdviserSubmitGradeView.as_view(), name='adviser_grade_submit'),
    path(
        'peer-evaluations/',
        StudentPeerEvaluationSubmitView.as_view(),
        name='student_peer_evaluation_submit',
    ),
]
