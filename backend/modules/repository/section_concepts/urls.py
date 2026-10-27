from django.urls import path
from .views import SectionProjectListView, SectionProjectDetailView, SectionPaperUploadView, SectionPaperFileView, ImportedSectionProjectView
from .shared_views import SharedDeliverablesView, SharedDeliverableFileView

urlpatterns = [
    path('shared-deliverables/', SharedDeliverablesView.as_view(), name='shared_deliverables'),
    path('shared-deliverables/files/<int:file_id>/', SharedDeliverableFileView.as_view(), name='shared_deliverable_file'),
    path('', SectionProjectListView.as_view(), name='section_concept_projects'),
    path('imported/', ImportedSectionProjectView.as_view(), name='section_concept_imported'),
    path('<int:project_id>/', SectionProjectDetailView.as_view(), name='section_concept_project'),
    path('<int:project_id>/upload/', SectionPaperUploadView.as_view(), name='section_concept_upload'),
    path('<int:project_id>/papers/<int:paper_id>/', SectionPaperFileView.as_view(), name='section_concept_paper'),
]
