from django.urls import path

from .views import (
    RubricDetailView,
    RubricListCreateView,
    RubricPublishView,
    RubricWeightsView,
)


urlpatterns = [
    path('', RubricListCreateView.as_view(), name='rubrics'),
    path('<int:rubric_id>/', RubricDetailView.as_view(), name='rubric_detail'),
    path('<int:rubric_id>/publish/', RubricPublishView.as_view(), name='rubric_publish'),
    path('<int:rubric_id>/weights/', RubricWeightsView.as_view(), name='rubric_weights'),
]
