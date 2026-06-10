from asgiref.sync import async_to_sync
from django.contrib.auth import get_user_model
from django.test import TestCase
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
