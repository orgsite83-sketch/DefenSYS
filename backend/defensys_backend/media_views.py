import mimetypes
import os

from django.conf import settings
from django.core.files.storage import default_storage
from django.http import FileResponse, Http404
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView


class AuthenticatedMediaFileView(APIView):
    """Stream local media files when not using DEBUG static serving or S3."""

    permission_classes = [IsAuthenticated]

    def get(self, request, file_path):
        if getattr(settings, 'USE_S3', False):
            raise Http404('Media is served from object storage.')

        resolved = os.path.normpath(file_path)
        drive, path = os.path.splitdrive(resolved)
        if drive or os.path.isabs(resolved) or '..' in resolved or resolved.startswith('/') or resolved.startswith('\\'):
            raise Http404('Invalid file path.')

        if not default_storage.exists(file_path):
            raise Http404('File not found.')

        opened = default_storage.open(file_path, 'rb')
        content_type, _encoding = mimetypes.guess_type(file_path)
        return FileResponse(
            opened,
            content_type=content_type or 'application/octet-stream',
            as_attachment=False,
            filename=file_path.split('/')[-1],
        )
