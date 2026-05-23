from django.urls import path

from .views import CurriculumAnalyticsView, CurriculumProposalView


urlpatterns = [
    path('', CurriculumAnalyticsView.as_view(), name='curriculum_analytics'),
    path('proposal/', CurriculumProposalView.as_view(), name='curriculum_proposal'),
]
