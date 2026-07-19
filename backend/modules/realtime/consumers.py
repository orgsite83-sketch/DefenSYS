import asyncio
import json
import logging
from urllib.parse import parse_qs

from django.utils import timezone
from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken

from .groups import groups_for_user_async

logger = logging.getLogger(__name__)
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
            self.token_exp = token.get('exp')
            user_id = token['user_id']
            self.user = await User.objects.aget(pk=user_id)
            if not self.user.is_active:
                await self.close(code=4403)
                return
        except (TokenError, KeyError, User.DoesNotExist):
            await self.close(code=4401)
            return

        self.joined_groups: list[str] = []
        for group in await groups_for_user_async(self.user):
            await self.channel_layer.group_add(group, self.channel_name)
            self.joined_groups.append(group)

        await self.accept()
        self.validation_task = asyncio.create_task(self.periodic_validation())

    async def disconnect(self, close_code):
        if hasattr(self, 'validation_task'):
            self.validation_task.cancel()
        for group in getattr(self, 'joined_groups', []):
            await self.channel_layer.group_discard(group, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        # Re-validate if client sends any message
        if not await self.is_token_and_user_valid():
            await self.close(code=4401)

    async def grading_flags_changed(self, event):
        if not await self.is_token_and_user_valid():
            await self.close(code=4401)
            return
        await self.send(text_data=json.dumps(event['payload']))

    async def is_token_and_user_valid(self) -> bool:
        # Check token expiration
        if not getattr(self, 'token_exp', None):
            return False
        now_timestamp = timezone.now().timestamp()
        if now_timestamp > self.token_exp:
            logger.info('realtime_sync: ws token expired for user=%s', getattr(self, 'user', None))
            return False

        # Check if user is still active in DB
        try:
            user = await User.objects.aget(pk=self.user.pk)
            if not user.is_active:
                logger.info('realtime_sync: ws user deactivated user=%s', user)
                return False
        except User.DoesNotExist:
            logger.info('realtime_sync: ws user deleted pk=%s', self.user.pk)
            return False

        return True

    async def periodic_validation(self):
        try:
            while True:
                await asyncio.sleep(60)  # Check every 60 seconds
                if not await self.is_token_and_user_valid():
                    await self.close(code=4401)
                    break
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.exception('realtime_sync: ws periodic validation error: %s', e)
            await self.close(code=4500)
