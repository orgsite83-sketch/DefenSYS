"""Check the launcher's port conflicts and ownership without starting servers."""

import argparse
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import io
import unittest
from unittest.mock import Mock, call, patch

from execution import start_local_web as launcher


class LocalWebLauncherTests(unittest.TestCase):
    def setup_runtime(self, stack):
        stack.enter_context(redirect_stdout(io.StringIO()))
        stack.enter_context(redirect_stderr(io.StringIO()))
        stack.enter_context(patch.object(launcher, 'detect_lan_ip', return_value='192.168.1.3'))
        stack.enter_context(patch.object(launcher.socket, 'socket'))
        stack.enter_context(patch.object(launcher, 'flutter_command', return_value=['flutter']))
        self.listening = stack.enter_context(patch.object(launcher, 'listening', return_value=False))
        self.ready = stack.enter_context(patch.object(launcher, 'ready', return_value=True))
        self.start = stack.enter_context(patch.object(launcher, 'start'))
        self.stop = stack.enter_context(patch.object(launcher, 'stop'))
        self.browser = stack.enter_context(patch.object(launcher.webbrowser, 'open'))
        self.is_web = stack.enter_context(patch.object(launcher, 'is_defensys_web', return_value=False))
        self.monitor = stack.enter_context(patch.object(launcher, 'monitor_servers', return_value=0))
        self.android = stack.enter_context(patch.object(launcher, 'connected_android_device', return_value=None))

    def test_rejects_loopback_public_and_invalid_addresses(self):
        for address in ['127.0.0.1', '0.0.0.0', '203.0.113.10', '172.15.0.1', '172.32.0.1', '192.168.1.300']:
            with self.subTest(address=address), self.assertRaises(argparse.ArgumentTypeError):
                launcher.lan_ip(address)
        for address in ['10.0.0.1', '172.16.0.1', '172.31.255.254', '192.168.1.3']:
            self.assertEqual(launcher.lan_ip(address), address)

    def test_check_mode_never_starts_stops_or_opens_anything(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.assertEqual(launcher.main(['--check']), 0)
            self.start.assert_not_called()
            self.stop.assert_not_called()
            self.browser.assert_not_called()

    def test_published_apk_is_passed_to_web_settings(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            frontend = Mock()
            frontend.poll.return_value = None
            self.start.return_value = frontend
            self.assertEqual(launcher.main(['--android-download-url', 'https://defensys.example/app.apk']), 0)
            command = self.start.call_args.args[0]
            self.assertIn('--dart-define=DEFENSYS_ANDROID_DOWNLOAD_URL=https://defensys.example/app.apk', command)

    def test_download_url_rejects_non_https_and_embedded_credentials(self):
        for address in ['http://192.168.1.3/app.apk', 'javascript:alert(1)', 'https://user:secret@example.com/app.apk']:
            with self.subTest(address=address), self.assertRaises(argparse.ArgumentTypeError):
                launcher.android_download_url(address)

    def test_occupied_web_port_leaves_existing_servers_untouched(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.return_value = True
            self.assertEqual(launcher.main(['--no-browser']), 1)
            self.start.assert_not_called()
            self.stop.assert_not_called()

    def test_healthy_existing_backend_is_reused_and_never_stopped(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            frontend = Mock()
            frontend.poll.return_value = None
            frontend.wait.return_value = 0
            self.start.return_value = frontend
            self.assertEqual(launcher.main([]), 0)
            self.start.assert_called_once()
            self.stop.assert_called_once_with(frontend)
            self.browser.assert_called_once_with('http://192.168.1.3:57583/#/login')

    def test_unreachable_occupied_api_does_not_start_or_stop_servers(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.ready.return_value = False
            self.listening.side_effect = [False, False, True]
            self.assertEqual(launcher.main(['--no-browser']), 1)
            self.start.assert_not_called()
            self.stop.assert_not_called()

    def test_frontend_startup_failure_cleans_up_only_owned_children(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.ready.return_value = False
            stack.enter_context(patch.object(launcher.Path, 'exists', return_value=True))
            backend, frontend = Mock(), Mock()
            self.start.side_effect = [backend, frontend]
            stack.enter_context(patch.object(launcher, 'wait_for', side_effect=[None, RuntimeError('compile failed')]))
            self.assertEqual(launcher.main(['--no-browser']), 1)
            self.assertEqual(self.stop.call_args_list, [call(frontend), call(backend)])
            self.browser.assert_not_called()

    def test_existing_web_does_not_prevent_starting_a_missing_backend(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.side_effect = [True, False, False]
            self.is_web.return_value = True
            self.ready.return_value = False
            stack.enter_context(patch.object(launcher.Path, 'exists', return_value=True))
            stack.enter_context(patch.object(launcher, 'wait_for'))
            backend = Mock()
            self.start.return_value = backend
            self.assertEqual(launcher.main(['--no-browser']), 0)
            self.start.assert_called_once()
            self.assertIn('manage.py', self.start.call_args.args[0])
            self.assertIsNone(self.monitor.call_args.args[0])
            self.stop.assert_called_once_with(backend)

    def test_existing_web_and_api_can_be_reused_without_starting_or_stopping_them(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.return_value = True
            self.is_web.return_value = True
            self.assertEqual(launcher.main(['--no-browser']), 0)
            self.start.assert_not_called()
            self.stop.assert_not_called()

    def test_connected_phone_is_included_when_web_and_api_are_already_up(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.return_value = True
            self.is_web.return_value = True
            self.android.return_value = 'demo-phone'
            phone = Mock()
            self.start.return_value = phone
            self.assertEqual(launcher.main(['--no-browser']), 0)
            self.start.assert_called_once()
            command = self.start.call_args.args[0]
            self.assertIn('demo-phone', command)
            self.assertIn('--dart-define=DEFENSYS_API_HOST=192.168.1.3', command)
            self.assertIn('--dart-define=DEFENSYS_API_PORT=8000', command)
            self.assertIn('--dart-define=GUEST_PORTAL_URL=http://192.168.1.3:57583/#/guest/evaluate', command)
            self.assertIs(self.monitor.call_args.kwargs['mobile'], phone)

    def test_check_mode_does_not_deploy_a_connected_phone(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.android.return_value = 'demo-phone'
            self.assertEqual(launcher.main(['--check']), 0)
            self.start.assert_not_called()
            self.stop.assert_not_called()

    def test_no_android_does_not_query_or_deploy_devices(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.assertEqual(launcher.main(['--check', '--no-android']), 0)
            self.android.assert_not_called()
            self.start.assert_not_called()


class AndroidSelectionTests(unittest.TestCase):
    def select(self, output, requested=None):
        with patch.object(launcher, 'adb_executable', return_value='adb'), \
                patch.object(launcher.subprocess, 'run', return_value=Mock(stdout=output)), \
                redirect_stdout(io.StringIO()):
            return launcher.connected_android_device(requested)

    def test_selects_only_online_physical_phone(self):
        output = 'List of devices attached\nemulator-5554 device\nphone-a device product:demo\nphone-b unauthorized\nphone-c offline\n'
        self.assertEqual(self.select(output), 'phone-a')

    def test_does_not_launch_random_phone_when_multiple_are_connected(self):
        self.assertIsNone(self.select('phone-a device\nphone-b device\n'))
        self.assertEqual(self.select('phone-a device\nphone-b device\n', 'phone-b'), 'phone-b')

    def test_unapproved_or_missing_explicit_device_fails_before_deployment(self):
        for requested in ['phone-a', 'missing-phone']:
            with self.subTest(device=requested), self.assertRaisesRegex(RuntimeError, 'debugging prompt'):
                self.select('phone-a unauthorized\n', requested)

    def test_missing_android_sdk_does_not_block_web_startup(self):
        with patch.object(launcher, 'adb_executable', return_value=None), redirect_stdout(io.StringIO()):
            self.assertIsNone(launcher.connected_android_device())
            with self.assertRaisesRegex(RuntimeError, 'platform-tools'):
                launcher.connected_android_device('phone-a')


class ServerMonitoringTests(unittest.TestCase):
    def test_failed_phone_deployment_does_not_stop_web_or_api_monitoring(self):
        frontend, mobile = Mock(), Mock()
        frontend.poll.side_effect = [None, None, 0]
        mobile.poll.return_value = 1
        output = io.StringIO()
        with patch.object(launcher, 'ready', return_value=True), \
                patch.object(launcher.time, 'sleep'), redirect_stdout(output):
            result = launcher.monitor_servers(frontend, '192.168.1.3', 57583, 8000, 'health', [], mobile=mobile)
        self.assertEqual(result, 0)
        mobile.poll.assert_called_once()
        self.assertIn('web app and backend will stay running', output.getvalue())

    def test_reused_api_is_restored_after_its_original_process_stops(self):
        frontend = Mock()
        frontend.poll.side_effect = [None, None, 0]
        owned = []
        with patch.object(launcher, 'ready', side_effect=[True, False]), \
                patch.object(launcher, 'listening', return_value=False), \
                patch.object(launcher, 'ensure_backend') as restore, \
                patch.object(launcher.time, 'sleep'), redirect_stdout(io.StringIO()):
            result = launcher.monitor_servers(frontend, '192.168.1.3', 57583, 8000, 'health', owned)
        self.assertEqual(result, 0)
        restore.assert_called_once_with('192.168.1.3', 8000, 'health', owned)

    def test_unhealthy_live_backend_is_not_replaced(self):
        frontend = Mock()
        frontend.poll.side_effect = [None, 0]
        with patch.object(launcher, 'ready', return_value=False), \
                patch.object(launcher, 'listening', return_value=True), \
                patch.object(launcher, 'ensure_backend') as restore, \
                patch.object(launcher.time, 'sleep'), redirect_stdout(io.StringIO()):
            self.assertEqual(launcher.monitor_servers(frontend, '192.168.1.3', 57583, 8000, 'health', []), 0)
        restore.assert_not_called()

    def test_missing_existing_web_session_ends_monitoring(self):
        with patch.object(launcher, 'listening', return_value=False), \
                self.assertRaisesRegex(RuntimeError, 'web session stopped'):
            launcher.monitor_servers(None, '192.168.1.3', 57583, 8000, 'health', [])


if __name__ == '__main__':
    unittest.main()
