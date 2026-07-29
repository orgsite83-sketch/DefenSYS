from django.urls import path

from .views import (
    ProjectArchiveExportView,
    ProjectArchiveListView,
    ProjectArchiveOverrideStatusView,
    ProjectArchiveReplaceFileView,
    ProjectArchiveRequestResubmissionView,
    ProjectArchiveTrailView,
    ProjectArchiveUploadCapstoneView,
    ProjectArchiveUploadPitView,
)


urlpatterns = [
    path('', ProjectArchiveListView.as_view(), name='project_archive'),
    path('upload-pit/', ProjectArchiveUploadPitView.as_view(), name='project_archive_upload_pit'),
    path(
        'upload-capstone/',
        ProjectArchiveUploadCapstoneView.as_view(),
        name='project_archive_upload_capstone',
    ),
    path('request-resubmission/', ProjectArchiveRequestResubmissionView.as_view(), name='project_archive_request_resubmission'),
    path('override-status/', ProjectArchiveOverrideStatusView.as_view(), name='project_archive_override_status'),
    path('replace-file/', ProjectArchiveReplaceFileView.as_view(), name='project_archive_replace_file'),
    path('trail/', ProjectArchiveTrailView.as_view(), name='project_archive_trail'),
    path('export/', ProjectArchiveExportView.as_view(), name='project_archive_export'),
]
