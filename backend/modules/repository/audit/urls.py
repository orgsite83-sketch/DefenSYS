from django.urls import path

from .views import (
    RepositoryAuditExportView,
    RepositoryAuditListView,
    RepositoryAuditOverrideStatusView,
    RepositoryAuditTrailView,
    RepositoryAuditUploadCapstoneView,
    RepositoryAuditUploadPitView,
)


urlpatterns = [
    path('', RepositoryAuditListView.as_view(), name='repository_audit'),
    path('upload-pit/', RepositoryAuditUploadPitView.as_view(), name='repository_audit_upload_pit'),
    path(
        'upload-capstone/',
        RepositoryAuditUploadCapstoneView.as_view(),
        name='repository_audit_upload_capstone',
    ),
    path('override-status/', RepositoryAuditOverrideStatusView.as_view(), name='repository_audit_override_status'),
    path('trail/', RepositoryAuditTrailView.as_view(), name='repository_audit_trail'),
    path('export/', RepositoryAuditExportView.as_view(), name='repository_audit_export'),
]
