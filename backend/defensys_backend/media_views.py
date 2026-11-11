import mimetypes
import os
from pathlib import Path, PureWindowsPath
import re
from urllib.parse import quote

from django.conf import settings
from django.core.files.storage import default_storage
from django.http import FileResponse, Http404, HttpResponse, StreamingHttpResponse
from django.utils.http import content_disposition_header, http_date, parse_http_date_safe
from rest_framework.authentication import SessionAuthentication
from rest_framework.permissions import AllowAny, IsAuthenticated
from authentication_access_control.workspace_authentication import WorkspaceJWTAuthentication as JWTAuthentication
from rest_framework.views import APIView

from authentication_access_control.guest_authentication import GuestJWTAuthentication
from .media_access import can_read_media
from .media_sessions import MediaCookieAuthentication


def _file_chunks(opened, start, length):
    try:
        opened.seek(start)
        remaining = length
        while remaining > 0:
            chunk = opened.read(min(64 * 1024, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            yield chunk
    finally:
        opened.close()


def _range_bounds(header, size):
    match = re.fullmatch(r'bytes=(\d*)-(\d*)', header or '')
    if not match or not any(match.groups()) or size == 0:
        raise ValueError('Unsupported range')
    left, right = match.groups()
    if left:
        start, end = int(left), int(right) if right else size - 1
    else:
        if int(right) == 0:
            raise ValueError('Empty suffix')
        start, end = max(0, size - int(right)), size - 1
    if start >= size or start > end:
        raise ValueError('Unsatisfiable range')
    return start, min(end, size - 1)


class AuthenticatedMediaFileView(APIView):
    """Stream a file only when its owning record is visible to the requester."""

    authentication_classes = [GuestJWTAuthentication, JWTAuthentication, MediaCookieAuthentication, SessionAuthentication]
    permission_classes = [IsAuthenticated]

    def can_read(self, request, name):
        return can_read_media(request.user, name)

    def get(self, request, file_path):
        if '..' in file_path.replace('\\', '/').split('/') or PureWindowsPath(file_path).drive:
            raise Http404('Invalid file path.')
        resolved = os.path.normpath(file_path).replace('\\', '/')
        drive, path = os.path.splitdrive(resolved)
        if drive or os.path.isabs(resolved) or '..' in resolved or resolved.startswith('/') or resolved.startswith('\\'):
            raise Http404('Invalid file path.')

        if not self.can_read(request, resolved) or not default_storage.exists(resolved):
            raise Http404('File not found.')

        # FileSystemStorage's lexical checks alone do not reject escaping symlinks.
        local_path = None
        try:
            local_path = Path(default_storage.path(resolved)).resolve()
            if not local_path.is_relative_to(Path(default_storage.location).resolve()):
                raise Http404('Invalid file path.')
        except NotImplementedError:
            pass
        content_type, _encoding = mimetypes.guess_type(resolved)
        content_type = content_type or 'application/octet-stream'
        prefix = getattr(settings, 'MEDIA_X_ACCEL_PREFIX', '')
        if prefix and local_path is not None:
            if not prefix.startswith('/') or '..' in prefix.split('/'):
                raise ValueError('Invalid internal media prefix.')
            response = HttpResponse(content_type=content_type)
            response['X-Accel-Redirect'] = prefix.rstrip('/') + '/' + quote(resolved, safe='/')
            response['Content-Length'] = str(default_storage.size(resolved))
            response['Content-Disposition'] = content_disposition_header(False, resolved.split('/')[-1])
        else:
            size = default_storage.size(resolved)
            try:
                modified = default_storage.get_modified_time(resolved)
            except NotImplementedError:
                modified = None
            requested = request.headers.get('Range') if request.method == 'GET' else None
            # Only a matching date validator permits a range; no ETag is emitted.
            validator = request.headers.get('If-Range')
            if validator and (modified is None or parse_http_date_safe(validator) != int(modified.timestamp())):
                requested = None
            if requested:
                try:
                    start, end = _range_bounds(requested, size)
                except ValueError:
                    response = HttpResponse(status=416)
                    response['Content-Range'] = f'bytes */{size}'
                else:
                    opened = default_storage.open(resolved, 'rb')
                    response = StreamingHttpResponse(
                        _file_chunks(opened, start, end - start + 1),
                        status=206, content_type=content_type,
                    )
                    # Also close when the client disconnects before iteration starts.
                    response._resource_closers.append(opened.close)
                    response['Content-Length'] = str(end - start + 1)
                    response['Content-Range'] = f'bytes {start}-{end}/{size}'
            elif request.method == 'HEAD':
                response = HttpResponse(content_type=content_type)
                response['Content-Length'] = str(size)
            else:
                response = FileResponse(default_storage.open(resolved, 'rb'), content_type=content_type)
            response['Accept-Ranges'] = 'bytes'
            if modified is not None:
                response['Last-Modified'] = http_date(modified.timestamp())
            response['Content-Disposition'] = content_disposition_header(False, resolved.split('/')[-1])
        response['Cache-Control'] = 'private, no-store'
        response['Vary'] = 'Authorization, Cookie'
        response['X-Content-Type-Options'] = 'nosniff'
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
