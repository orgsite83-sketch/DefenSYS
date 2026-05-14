from django.urls import path

from .views import (
    RepositoryAuditClassifyView,
    RepositoryAuditDemoFillView,
    RepositoryAuditExportView,
    RepositoryAuditListView,
    RepositoryAuditOverrideStatusView,
    RepositoryAuditUploadPitView,
)


urlpatterns = [
    path('', RepositoryAuditListView.as_view(), name='repository_audit'),
    path('upload-pit/', RepositoryAuditUploadPitView.as_view(), name='repository_audit_upload_pit'),
    path('classify/', RepositoryAuditClassifyView.as_view(), name='repository_audit_classify'),
    path('override-status/', RepositoryAuditOverrideStatusView.as_view(), name='repository_audit_override_status'),
    path('demo-fill/', RepositoryAuditDemoFillView.as_view(), name='repository_audit_demo_fill'),
    path('export/', RepositoryAuditExportView.as_view(), name='repository_audit_export'),
]
