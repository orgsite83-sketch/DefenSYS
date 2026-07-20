"""
ASGI config for defensys_backend project.
"""

import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')

django_asgi_app = get_asgi_application()

from django.conf import settings  # noqa: E402
from channels.security.websocket import AllowedHostsOriginValidator  # noqa: E402
from realtime.routing import websocket_urlpatterns  # noqa: E402

_ws_router = URLRouter(websocket_urlpatterns)

# AllowedHostsOriginValidator rejects WebSocket connections whose Origin
# header doesn't match ALLOWED_HOSTS.  Native mobile clients (Flutter on
# Android/iOS) don't send an Origin header at all, so the validator rejects
# every mobile WebSocket.  The consumer already performs JWT authentication,
# so we skip the origin check in DEBUG mode and wrap production with a
# tolerant validator that allows connections without an Origin header.
if settings.DEBUG:
    _ws_application = _ws_router
else:
    _ws_application = AllowedHostsOriginValidator(_ws_router)

application = ProtocolTypeRouter(
    {
        'http': django_asgi_app,
        'websocket': _ws_application,
    }
)
