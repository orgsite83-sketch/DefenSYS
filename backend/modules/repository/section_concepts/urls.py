from django.urls import path
from .views import SectionProjectListView, SectionProjectDetailView, SectionPaperUploadView, SectionPaperFileView

urlpatterns = [
    path('', SectionProjectListView.as_view(), name='section_concept_projects'),
    path('<int:project_id>/', SectionProjectDetailView.as_view(), name='section_concept_project'),
    path('<int:project_id>/upload/', SectionPaperUploadView.as_view(), name='section_concept_upload'),
    path('<int:project_id>/papers/<int:paper_id>/', SectionPaperFileView.as_view(), name='section_concept_paper'),
]
