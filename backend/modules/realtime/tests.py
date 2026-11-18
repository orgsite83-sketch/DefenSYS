from asgiref.sync import async_to_sync
from django.contrib.auth import get_user_model
from django.test import TestCase
from unittest.mock import AsyncMock, patch
import asyncio
import time
from rest_framework_simplejwt.tokens import AccessToken

from academic_period_management.models import SchoolYear, Semester
from realtime.broadcast import notify_capstone_evaluation_flags, notify_pit_peer_grading
from realtime.groups import (
    groups_for_user,
    pit_group_name,
    semester_group_name,
    user_group_name,
)

User = get_user_model()


class RealtimeGroupTests(TestCase):
    def test_pit_group_slug(self):
        self.assertEqual(pit_group_name(2, 'PIT 301 - Event A'), 'pit_2_pit_301_event_a')

    def test_groups_for_user_includes_active_semester(self):
        year = SchoolYear.objects.create(label='2025-2026')
        semester = Semester.objects.create(
            school_year=year,
            label='1st Semester',
            is_active=True,
        )
        user = User.objects.create_user(
            username='student_ws',
            email='student_ws@test.com',
            password='pass',
            role='student',
        )
        groups = groups_for_user(user)
        self.assertIn(user_group_name(user.pk), groups)
        self.assertIn(semester_group_name(semester.id), groups)


class RealtimeBroadcastTests(TestCase):
    def setUp(self):
        year = SchoolYear.objects.create(label='2024-2025')
        self.semester = Semester.objects.create(
            school_year=year,
            label='1st Semester',
            is_active=True,
            capstone_peer_evaluation_enabled=False,
        )

    def test_capstone_broadcast_uses_semester_group(self):
        """In-memory channel layer (test settings) should accept broadcast."""
        notify_capstone_evaluation_flags(
            self.semester,
            peer_eval_enabled=True,
        )
        expected = semester_group_name(self.semester.id)
        self.assertTrue(expected.startswith('semester_'))

    def test_pit_broadcast_uses_event_group(self):
        notify_pit_peer_grading(
            self.semester,
            'PIT Defense Day',
            peer_eval_enabled=True,
        )
        expected = pit_group_name(self.semester.id, 'PIT Defense Day')
        self.assertEqual(expected, 'pit_{}_pit_defense_day'.format(self.semester.id))

    def test_stalled_redis_cannot_hold_a_saved_grade_response_open(self):
        from realtime.broadcast import _send_to_groups

        async def stalled(*args):
            await asyncio.sleep(60)

        layer = AsyncMock()
        layer.group_send.side_effect = stalled
        started = time.monotonic()
        with patch('realtime.broadcast.get_channel_layer', return_value=layer), \
                patch('realtime.broadcast.BROADCAST_TIMEOUT_SECONDS', 0.01), \
                self.assertLogs('realtime.broadcast', level='WARNING'):
            _send_to_groups(['first', 'second'], {'event': 'grading.flags_changed'})
        self.assertLess(time.monotonic() - started, 1)
        self.assertEqual(layer.group_send.await_count, 1)


class GradingFlagsConsumerTests(TestCase):
    def _websocket_application(self):
        from channels.routing import URLRouter

        from realtime.routing import websocket_urlpatterns

        return URLRouter(websocket_urlpatterns)

    def test_rejects_missing_token(self):
        from channels.testing import WebsocketCommunicator

        application = self._websocket_application()

        async def run():
            communicator = WebsocketCommunicator(application, '/ws/grading/')
            connected, _ = await communicator.connect()
            self.assertFalse(connected)

        async_to_sync(run)()

    def test_redis_receive_failure_closes_with_recoverable_code(self):
        from channels.layers import InMemoryChannelLayer
        from channels.testing import WebsocketCommunicator
        from redis.exceptions import TimeoutError as RedisTimeoutError

        class UnavailableLayer(InMemoryChannelLayer):
            async def receive(self, channel):
                raise RedisTimeoutError('Redis unavailable')

        async def run():
            with patch('channels.consumer.get_channel_layer', return_value=UnavailableLayer()), \
                    patch('realtime.consumers.GradingFlagsConsumer.connect', new=AsyncMock()):
                communicator = WebsocketCommunicator(self._websocket_application(), '/ws/grading/')
                connected, code = await communicator.connect()
                self.assertFalse(connected)
                self.assertEqual(code, 4500)
                await communicator.disconnect()

        with self.assertLogs('realtime.consumers', level='WARNING'):
            async_to_sync(run)()

    def test_accepts_valid_token(self):
        from channels.testing import WebsocketCommunicator

        application = self._websocket_application()

        user = User.objects.create_user(
            username='ws_user',
            email='ws@test.com',
            password='pass',
            role='student',
        )
        token = str(AccessToken.for_user(user))

        async def run():
            communicator = WebsocketCommunicator(
                application,
                f'/ws/grading/?token={token}',
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            await communicator.disconnect()

        async_to_sync(run)()
