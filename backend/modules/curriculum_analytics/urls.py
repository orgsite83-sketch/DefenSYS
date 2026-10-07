from django.urls import path
from .explorer_report import CurriculumExplorerReportView

from .views import (
    CurriculumAnalyticsView,
    CurriculumProposalView,
    CurriculumProposalPdfView,
    CurriculumExplorerView,
    CurriculumExplorerDetailView,
)


urlpatterns = [
    path('explorer/', CurriculumExplorerView.as_view(), name='curriculum_explorer'),
    path('explorer/report/', CurriculumExplorerReportView.as_view(), name='curriculum_explorer_report'),
    path('explorer/projects/<str:project_id>/', CurriculumExplorerDetailView.as_view(), name='curriculum_explorer_detail'),
    path('', CurriculumAnalyticsView.as_view(), name='curriculum_analytics'),
    path('proposal/', CurriculumProposalView.as_view(), name='curriculum_proposal'),
    path('proposal/pdf/', CurriculumProposalPdfView.as_view(), name='curriculum_proposal_pdf'),
]
