import mimetypes
import os

from django.core.files.storage import default_storage
from django.http import FileResponse, Http404
from rest_framework.authentication import SessionAuthentication
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework.views import APIView

from authentication_access_control.guest_authentication import GuestJWTAuthentication
from .media_access import can_read_media


class AuthenticatedMediaFileView(APIView):
    """Stream a file only when its owning record is visible to the requester."""

    authentication_classes = [GuestJWTAuthentication, JWTAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated]

    def can_read(self, request, name):
        return can_read_media(request.user, name)

    def get(self, request, file_path):
        resolved = os.path.normpath(file_path).replace('\\', '/')
        drive, path = os.path.splitdrive(resolved)
        if drive or os.path.isabs(resolved) or '..' in resolved or resolved.startswith('/') or resolved.startswith('\\'):
            raise Http404('Invalid file path.')

        if not self.can_read(request, resolved) or not default_storage.exists(resolved):
            raise Http404('File not found.')

        opened = default_storage.open(resolved, 'rb')
        content_type, _encoding = mimetypes.guess_type(resolved)
        response = FileResponse(
            opened,
            content_type=content_type or 'application/octet-stream',
            as_attachment=False,
            filename=resolved.split('/')[-1],
        )
        response['Cache-Control'] = 'private, no-store'
        response['Vary'] = 'Authorization'
        return response


class PublicAvatarFileView(AuthenticatedMediaFileView):
    """Profile avatars are public; private uploads never use this route."""

    authentication_classes = []
    permission_classes = [AllowAny]

    def get(self, request, file_path):
        return super().get(request, 'avatars/' + file_path)

    def can_read(self, request, name):
        from django.contrib.auth import get_user_model

        return get_user_model().objects.filter(avatar=name).exists()
