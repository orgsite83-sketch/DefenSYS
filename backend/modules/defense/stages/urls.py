from django.urls import path

from .views import (
    DefenseStageDetailView,
    DefenseStageListCreateView,
    StageDeliverableDetailView,
    StageDeliverableListCreateView,
    StageGradingConfigView,
)


urlpatterns = [
    path('', DefenseStageListCreateView.as_view(), name='defense_stages'),
    path('<int:stage_id>/', DefenseStageDetailView.as_view(), name='defense_stage_detail'),
    path(
        '<int:stage_id>/grading-config/',
        StageGradingConfigView.as_view(),
        name='defense_stage_grading_config',
    ),
    path('<int:stage_id>/deliverables/', StageDeliverableListCreateView.as_view(), name='stage_deliverables'),
    path('<int:stage_id>/deliverables/<int:deliverable_id>/', StageDeliverableDetailView.as_view(), name='stage_deliverable_detail'),
]
