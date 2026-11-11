"""Short-lived media-only cookies; original JWT checks still run on every request."""
import hashlib
import secrets
import time
from types import SimpleNamespace

from django.conf import settings
from django.core.cache import caches
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed, PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from authentication_access_control.workspace_authentication import WorkspaceJWTAuthentication as JWTAuthentication

from authentication_access_control.guest_authentication import GuestJWTAuthentication


def cookie_name():
    return settings.SESSION_COOKIE_NAME + '_media'


def grant_cache():
    return caches['media'] if 'media' in settings.CACHES else caches['default']


def grant_key(value):
    namespace = hashlib.sha256(settings.SECRET_KEY.encode()).hexdigest()[:16]
    return 'media-grant:' + namespace + ':' + hashlib.sha256(value.encode()).hexdigest()


def revoke_media_grant(request, response=None):
    value = request.COOKIES.get(cookie_name())
    if value:
        grant_cache().delete(grant_key(value))
    if response is not None:
        response.delete_cookie(cookie_name(), path='/api/media/', samesite='Strict')


class MediaCookieAuthentication(BaseAuthentication):
    """Installed only on the media view, never on general API endpoints."""

    def authenticate(self, request):
        if not getattr(settings, 'MEDIA_SESSION_ENABLED', False) or request.META.get('HTTP_AUTHORIZATION'):
            return None
        value = request.COOKIES.get(cookie_name())
        if not value:
            return None
        raw = grant_cache().get(grant_key(value))
        if not raw:
            raise AuthenticationFailed('Media session expired. Sign in again.')
        # Keep the credential server-side; reuse account/guest expiry and revocation checks.
        grant = raw if isinstance(raw, dict) else {'token': raw, 'headers': {}}
        authenticated = SimpleNamespace(META={'HTTP_AUTHORIZATION': 'Bearer ' + grant['token']},
                                        headers=grant['headers'])
        for backend in (GuestJWTAuthentication(), JWTAuthentication()):
            result = backend.authenticate(authenticated)
            if result is not None:
                return result
        raise AuthenticationFailed('Invalid media session.')


class MediaSessionView(APIView):
    authentication_classes = [GuestJWTAuthentication, JWTAuthentication, MediaCookieAuthentication]
    permission_classes = [IsAuthenticated]

    def post(self, request):
        if not getattr(settings, 'MEDIA_SESSION_ENABLED', False):
            return Response(status=404)
        if not request.META.get('HTTP_AUTHORIZATION', '').startswith('Bearer '):
            raise PermissionDenied('A signed-in access token is required to renew playback.')
        origin = request.headers.get('Origin')
        if origin and origin != request.build_absolute_uri('/').rstrip('/'):
            raise PermissionDenied('Media sessions require the same origin.')
        expires = int(request.auth.get('exp', 0))
        ttl = min(600, expires - int(time.time()))
        if ttl <= 0:
            raise AuthenticationFailed('Sign in again to play this file.')
        raw = request.META.get('HTTP_AUTHORIZATION', '').split(' ', 1)[-1]
        value = secrets.token_urlsafe(32)
        revoke_media_grant(request)
        headers = {key: request.headers[key] for key in (
            'X-Defensys-Workspace', 'X-Defensys-Year', 'X-Defensys-Section') if key in request.headers}
        grant_cache().set(grant_key(value), {'token': raw, 'headers': headers}, ttl)
        response = Response({'expires_in': ttl})
        response.set_cookie(cookie_name(), value, max_age=ttl, path='/api/media/',
                            secure=not settings.DEBUG, httponly=True, samesite='Strict')
        response['Cache-Control'] = 'no-store'
        return response

    def delete(self, request):
        response = Response(status=204)
        revoke_media_grant(request, response)
        return response
