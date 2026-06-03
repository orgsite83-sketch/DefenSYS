from django.conf import settings
from django.http import HttpResponse


class LocalCorsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.method == 'OPTIONS':
            response = HttpResponse(status=204)
        else:
            response = self.get_response(request)

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
    return (origin.startswith('http://localhost') or 
            origin.startswith('http://127.0.0.1') or 
            origin.startswith('http://192.168.') or 
            origin.startswith('http://10.'))
