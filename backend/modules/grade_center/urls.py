from django.urls import path

from .adviser_views import AdviserGradeListView, AdviserSubmitGradeView
from .views import (
    CapstoneEvaluationSettingsView,
    GradeCenterDemoFillView,
    GradeCenterDetailView,
    GradeCenterListView,
    GradeCenterPublishView,
    GradeCenterSyncView,
)


urlpatterns = [
    path('', GradeCenterListView.as_view(), name='grade_center'),
    path('sync/', GradeCenterSyncView.as_view(), name='grade_center_sync'),
    path('demo-fill/', GradeCenterDemoFillView.as_view(), name='grade_center_demo_fill'),
    path(
        'evaluation-settings/',
        CapstoneEvaluationSettingsView.as_view(),
        name='grade_center_evaluation_settings',
    ),
    path('<int:grade_id>/', GradeCenterDetailView.as_view(), name='grade_center_detail'),
    path('<int:grade_id>/publish/', GradeCenterPublishView.as_view(), name='grade_center_publish'),
    # Adviser-specific grading endpoints
    path('adviser-grades/', AdviserGradeListView.as_view(), name='adviser_grade_list'),
    path('adviser-grades/<int:grade_id>/submit/', AdviserSubmitGradeView.as_view(), name='adviser_grade_submit'),
]
