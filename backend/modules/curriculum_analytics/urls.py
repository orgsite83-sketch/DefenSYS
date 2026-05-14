from django.urls import path

from .views import CurriculumAnalyticsView, CurriculumClassifierView, CurriculumProposalView


urlpatterns = [
    path('', CurriculumAnalyticsView.as_view(), name='curriculum_analytics'),
    path('classify/', CurriculumClassifierView.as_view(), name='curriculum_classifier'),
    path('proposal/', CurriculumProposalView.as_view(), name='curriculum_proposal'),
]
