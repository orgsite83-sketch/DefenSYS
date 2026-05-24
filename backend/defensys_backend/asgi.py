"""
ASGI config for defensys_backend project.
"""

import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'defensys_backend.settings')

django_asgi_app = get_asgi_application()

from realtime.routing import websocket_urlpatterns  # noqa: E402

application = ProtocolTypeRouter(
    {
        'http': django_asgi_app,
        'websocket': URLRouter(websocket_urlpatterns),
    }
)
