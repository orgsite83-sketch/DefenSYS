from ipaddress import IPv4Address, IPv4Network
from urllib.parse import urlsplit

from asgiref.sync import iscoroutinefunction, markcoroutinefunction
from django.conf import settings
from django.http import HttpResponse


LAN_NETWORKS = tuple(IPv4Network(value) for value in (
    '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16',
))


class LocalCorsMiddleware:
    sync_capable = True
    async_capable = True

    def __init__(self, get_response):
        self.get_response = get_response
        self.async_mode = iscoroutinefunction(get_response)
        if self.async_mode:
            # Keep ASGI requests async so disconnects don't cross nested
            # sync/async adapters and produce shielded-future errors.
            markcoroutinefunction(self)

    def __call__(self, request):
        if self.async_mode:
            return self.__acall__(request)

        if request.method == 'OPTIONS':
            response = HttpResponse(status=204)
        else:
            response = self.get_response(request)

        return self._add_headers(request, response)

    async def __acall__(self, request):
        if request.method == 'OPTIONS':
            response = HttpResponse(status=204)
        else:
            response = await self.get_response(request)

        return self._add_headers(request, response)

    def _add_headers(self, request, response):
        origin = request.headers.get('Origin')
        if origin and _is_allowed_origin(origin):
            response['Access-Control-Allow-Origin'] = origin
            response['Access-Control-Allow-Credentials'] = 'true'
            response['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
            response['Access-Control-Allow-Headers'] = 'Authorization, Content-Type, Range'
            response['Access-Control-Max-Age'] = '86400'
            response['Access-Control-Expose-Headers'] = 'Content-Disposition, Content-Type, Content-Length, Accept-Ranges, Content-Range'
            response['Vary'] = 'Origin'
            
            # Add headers for PDF viewing
            if request.path.startswith('/media/') and request.path.endswith('.pdf'):
                response['Accept-Ranges'] = 'bytes'
                response['Cache-Control'] = 'public, max-age=3600'

        return response


def _is_allowed_origin(origin):
    allowed_origins = set(getattr(settings, 'CORS_ALLOWED_ORIGINS', []))
    if origin in allowed_origins:
        return True
    return bool(settings.DEBUG and _is_local_origin(origin))


def _is_local_origin(origin):
    # Parse the origin so lookalike hostnames cannot pass a prefix check.
    try:
        parsed = urlsplit(origin)
        if (parsed.scheme != 'http' or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or parsed.path or parsed.query or parsed.fragment):
            return False
        if parsed.port is not None and parsed.port == 0:
            return False
        if parsed.hostname == 'localhost':
            return True
        address = IPv4Address(parsed.hostname)
    except ValueError:
        return False
    if address == IPv4Address('127.0.0.1'):
        return True
    # All RFC1918 ranges, including 172.16/12 hotspots, require opt-in
    # to prevent accidental exposure if DEBUG=True leaks to production.
    if getattr(settings, 'CORS_ALLOW_LAN', False):
        return any(address in network for network in LAN_NETWORKS)
    return False
