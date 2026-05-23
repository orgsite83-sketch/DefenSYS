from django.urls import path

from .views import (
    TeamDocumentDetailView,
    TeamDocumentDownloadView,
    TeamDocumentListView,
    TeamDocumentUploadView,
)


urlpatterns = [
    path('', TeamDocumentListView.as_view(), name='document-list'),
    path('upload/', TeamDocumentUploadView.as_view(), name='document-upload'),
    path('<int:document_id>/', TeamDocumentDetailView.as_view(), name='document-detail'),
    path('<int:document_id>/download/', TeamDocumentDownloadView.as_view(), name='document-download'),
]
