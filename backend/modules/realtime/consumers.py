import json
from urllib.parse import parse_qs

from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken

from .groups import groups_for_user_async

User = get_user_model()


class GradingFlagsConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        query = parse_qs(self.scope.get('query_string', b'').decode())
        raw_token = (query.get('token') or [None])[0]
        if not raw_token:
            await self.close(code=4401)
            return

        try:
            token = AccessToken(raw_token)
            user_id = token['user_id']
            self.user = await User.objects.aget(pk=user_id)
        except (TokenError, KeyError, User.DoesNotExist):
            await self.close(code=4401)
            return

        self.joined_groups: list[str] = []
        for group in await groups_for_user_async(self.user):
            await self.channel_layer.group_add(group, self.channel_name)
            self.joined_groups.append(group)

        await self.accept()

    async def disconnect(self, close_code):
        for group in getattr(self, 'joined_groups', []):
            await self.channel_layer.group_discard(group, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        # Clients may send pings; no server action required.
        return

    async def grading_flags_changed(self, event):
        await self.send(text_data=json.dumps(event['payload']))
