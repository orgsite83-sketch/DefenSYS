from django.urls import path

from .consumers import GradingFlagsConsumer

websocket_urlpatterns = [
    path('ws/grading/', GradingFlagsConsumer.as_asgi()),
]
