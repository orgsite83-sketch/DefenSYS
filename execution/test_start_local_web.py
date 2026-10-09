"""Check the launcher's port conflicts and ownership without starting servers."""

import argparse
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import io
import subprocess
import threading
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
        def started(command, cwd, **kwargs):
            if kwargs.get('web_started') is not None:
                kwargs['web_started'].set()
            return self.start.return_value
        self.start.side_effect = started
        self.stop = stack.enter_context(patch.object(launcher, 'stop'))
        self.browser = stack.enter_context(patch.object(launcher.webbrowser, 'open'))
        self.is_web = stack.enter_context(patch.object(launcher, 'is_defensys_web', return_value=False))
        self.monitor = stack.enter_context(patch.object(launcher, 'monitor_servers', return_value=0))
        self.android = stack.enter_context(patch.object(launcher, 'connected_android_device', return_value=None))
        self.backend_listener = stack.enter_context(patch.object(launcher, 'backend_listener', return_value=None))
        self.stop_backend = stack.enter_context(patch.object(launcher, 'stop_backend'))

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

    def test_check_mode_with_restart_flags_is_still_read_only(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.assertEqual(launcher.main(['--check', '--restart-backend', '--restart-web']), 0)
            self.start.assert_not_called()
            self.stop_backend.assert_not_called()
            self.backend_listener.assert_not_called()

    def test_restart_backend_flag_replaces_only_the_identified_backend(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            existing = launcher.BackendProcess(101, 100, True)
            self.backend_listener.return_value = existing
            backend, frontend = Mock(), Mock()
            self.start.side_effect = [backend, frontend]
            stack.enter_context(patch.object(launcher.Path, 'exists', return_value=True))
            stack.enter_context(patch.object(launcher, 'wait_for'))
            self.assertEqual(launcher.main(['--restart-backend', '--no-android', '--no-browser']), 0)
            self.stop_backend.assert_called_once_with(existing, '192.168.1.3', 8000)
            self.assertEqual(self.stop.call_args_list, [call(frontend), call(backend)])

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
            self.assertIn('--release', command)
            self.assertNotIn('--debug', command)
            self.assertIn('--dart-define=DEFENSYS_API_HOST=192.168.1.3', command)
            self.assertIn('--dart-define=DEFENSYS_API_PORT=8000', command)
            self.assertIn('--dart-define=GUEST_PORTAL_URL=http://192.168.1.3:57583/#/guest/evaluate', command)
            self.assertIs(self.monitor.call_args.kwargs['mobile'], phone)

    def test_debug_flag_keeps_android_development_mode_available(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.return_value = True
            self.is_web.return_value = True
            self.android.return_value = 'demo-phone'
            self.assertEqual(launcher.main(['--debug', '--no-browser']), 0)
            command = self.start.call_args.args[0]
            self.assertIn('--debug', command)
            self.assertNotIn('--release', command)

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


class StartupReadinessTests(unittest.TestCase):
    def test_cached_entry_point_cannot_complete_startup_before_compilation(self):
        process = Mock()
        process.poll.return_value = None
        started = threading.Event()
        with patch.object(launcher, 'ready', return_value=True) as ready, \
                patch.object(launcher.time, 'monotonic', side_effect=[0, 0, 1]), \
                patch.object(launcher.time, 'sleep'), \
                self.assertRaisesRegex(RuntimeError, 'did not become ready'):
            launcher.wait_for('http://localhost/main.dart.js', process, 1,
                              web_started=started)
        ready.assert_not_called()

    def test_served_message_completes_startup_after_current_build(self):
        process = Mock()
        process.poll.return_value = None
        process.stdout = io.StringIO(
            'Compiling lib/main.dart for the Web...\n'
            'lib/main.dart is being served at http://0.0.0.0:57583\n'
        )
        started = threading.Event()
        with redirect_stdout(io.StringIO()), \
                patch.object(launcher, 'ready', return_value=True) as ready:
            launcher.forward_web_output(process, started)
            launcher.wait_for('http://localhost/main.dart.js', process, 1,
                              web_started=started)
        ready.assert_called_once()

    def test_build_failure_exits_without_accepting_cached_files(self):
        process = Mock()
        process.poll.return_value = 1
        process.returncode = 1
        with patch.object(launcher, 'ready', return_value=True) as ready, \
                self.assertRaisesRegex(RuntimeError, 'exited with code 1'):
            launcher.wait_for('http://localhost/main.dart.js', process, 1,
                              web_started=threading.Event())
        ready.assert_not_called()

    def test_flutter_symbols_do_not_break_readiness_on_legacy_terminals(self):
        process = Mock(stdout=io.StringIO(
            '\u2713 Built build/web\n'
            'lib/main.dart is being served at http://0.0.0.0:57583\n'
        ))
        started = threading.Event()
        output = io.BytesIO()
        with io.TextIOWrapper(output, encoding='ascii') as terminal, \
                redirect_stdout(terminal):
            launcher.forward_web_output(process, started)
            self.assertTrue(started.is_set())


class BackendReloadTests(unittest.TestCase):
    def runtime(self, stack, existing=None, healthy=True):
        stack.enter_context(redirect_stdout(io.StringIO()))
        stack.enter_context(patch.object(launcher, 'ready', return_value=healthy))
        self.listener = stack.enter_context(patch.object(launcher, 'backend_listener', return_value=existing))
        self.stop = stack.enter_context(patch.object(launcher, 'stop_backend'))
        self.start = stack.enter_context(patch.object(launcher, 'start'))
        stack.enter_context(patch.object(launcher, 'listening', return_value=False))
        stack.enter_context(patch.object(launcher.Path, 'exists', return_value=True))
        stack.enter_context(patch.object(launcher, 'wait_for'))

    def test_new_backend_enables_django_reload(self):
        owned = []
        with ExitStack() as stack:
            self.runtime(stack, healthy=False)
            backend = launcher.ensure_backend('192.168.1.3', 8000, 'health', owned)
            command = self.start.call_args.args[0]
            self.assertNotIn('--noreload', command)
            self.assertEqual(owned, [backend])
            self.stop.assert_not_called()

    def test_existing_backend_without_reload_is_upgraded(self):
        existing = launcher.BackendProcess(101, 100, False)
        owned = []
        with ExitStack() as stack:
            self.runtime(stack, existing)
            backend = launcher.ensure_backend('192.168.1.3', 8000, 'health', owned)
            self.stop.assert_called_once_with(existing, '192.168.1.3', 8000)
            self.assertEqual(owned, [backend])
            self.assertNotIn('--noreload', self.start.call_args.args[0])

    def test_existing_backend_with_reload_is_reused(self):
        with ExitStack() as stack:
            self.runtime(stack, launcher.BackendProcess(101, 100, True))
            self.assertIsNone(launcher.ensure_backend('192.168.1.3', 8000, 'health', []))
            self.stop.assert_not_called()
            self.start.assert_not_called()

    def test_unknown_healthy_server_is_not_stopped_even_on_explicit_restart(self):
        with ExitStack() as stack:
            self.runtime(stack)
            self.assertIsNone(launcher.ensure_backend('192.168.1.3', 8000, 'health', []))
            with self.assertRaisesRegex(RuntimeError, 'Cannot verify'):
                launcher.ensure_backend('192.168.1.3', 8000, 'health', [], restart=True)
            self.stop.assert_not_called()
            self.start.assert_not_called()

    def test_backend_ownership_requires_repo_venv_entrypoint_and_port(self):
        python = str(launcher.ROOT / 'backend' / 'venv' / 'Scripts' / 'python.exe')
        cases = [
            ([python, 'manage.py', 'runserver', '0.0.0.0:8000'], True),
            ([python, str(launcher.ROOT / 'backend' / 'manage.py'), 'runserver', '0.0.0.0:8000'], True),
            ([python, 'other.py', 'runserver', '0.0.0.0:8000'], False),
            (['C:/other-repo/venv/Scripts/python.exe', 'manage.py', 'runserver', '0.0.0.0:8000'], False),
            ([python, 'manage.py', 'runserver', '0.0.0.0:8001'], False),
            ([python, 'manage.py', 'shell', '0.0.0.0:8000'], False),
        ]
        for args, expected in cases:
            with self.subTest(args=args):
                self.assertEqual(launcher.workspace_backend_args(subprocess.list2cmdline(args), 8000) is not None, expected)

    def test_listener_includes_reloader_parents_and_excludes_the_launcher(self):
        python = str(launcher.ROOT / 'backend' / 'venv' / 'Scripts' / 'python.exe')
        command = subprocess.list2cmdline([python, 'manage.py', 'runserver', '0.0.0.0:8000'])
        table = {
            103: {'ProcessId': 103, 'ParentProcessId': 102, 'CommandLine': command},
            102: {'ProcessId': 102, 'ParentProcessId': 101, 'CommandLine': command},
            101: {'ProcessId': 101, 'ParentProcessId': 100, 'CommandLine': command},
            100: {'ProcessId': 100, 'ParentProcessId': 99, 'CommandLine': 'python start_local_web.py'},
        }
        with patch.object(launcher, 'pids_listening_on', return_value=[103]), \
                patch.object(launcher, 'windows_python_processes', return_value=table):
            self.assertEqual(launcher.backend_listener(8000), launcher.BackendProcess(103, 101, True))
        table[103]['CommandLine'] = command + ' --noreload'
        with patch.object(launcher, 'pids_listening_on', return_value=[103]), \
                patch.object(launcher, 'windows_python_processes', return_value=table):
            self.assertFalse(launcher.backend_listener(8000).reload_enabled)

    def test_backend_stop_failure_does_not_start_a_second_server(self):
        with ExitStack() as stack:
            self.runtime(stack, launcher.BackendProcess(101, 100, False))
            self.stop.side_effect = RuntimeError('Backend could not stop')
            with self.assertRaisesRegex(RuntimeError, 'could not stop'):
                launcher.ensure_backend('192.168.1.3', 8000, 'health', [])
            self.start.assert_not_called()

    def test_windows_cleanup_stops_the_owned_reloader_tree_after_signal_failure(self):
        process = Mock()
        process.pid = 100
        process.poll.return_value = None
        process.send_signal.side_effect = OSError('No console')
        with patch.object(launcher.os, 'name', 'nt'), \
                patch.object(launcher.signal, 'CTRL_BREAK_EVENT', 1, create=True), \
                patch.object(launcher.subprocess, 'run') as terminate:
            launcher.stop(process)
        terminate.assert_called_once()
        self.assertEqual(terminate.call_args.args[0], ['taskkill', '/F', '/T', '/PID', '100'])
        process.kill.assert_not_called()

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
    def test_owned_reloader_is_allowed_to_restart_without_a_second_server(self):
        frontend, backend = Mock(), Mock()
        frontend.poll.side_effect = [None, None, 0]
        backend.poll.return_value = None
        with patch.object(launcher, 'ready', side_effect=[False, True]), \
                patch.object(launcher, 'listening', return_value=False), \
                patch.object(launcher, 'ensure_backend') as restore, \
                patch.object(launcher.time, 'sleep'), redirect_stdout(io.StringIO()):
            self.assertEqual(launcher.monitor_servers(frontend, '192.168.1.3', 57583, 8000, 'health', [backend], backend=backend), 0)
        restore.assert_not_called()

    def test_reused_reloader_is_allowed_to_restart_without_a_second_server(self):
        frontend = Mock()
        frontend.poll.side_effect = [None, None, 0]
        external = launcher.BackendProcess(101, 100, True)
        with patch.object(launcher, 'ready', side_effect=[False, True]), \
                patch.object(launcher, 'listening', return_value=False), \
                patch.object(launcher, 'backend_parent_alive', return_value=True), \
                patch.object(launcher, 'ensure_backend') as restore, \
                patch.object(launcher.time, 'sleep'), redirect_stdout(io.StringIO()):
            self.assertEqual(launcher.monitor_servers(frontend, '192.168.1.3', 57583, 8000, 'health', [], external_backend=external), 0)
        restore.assert_not_called()

    def test_dead_owned_backend_is_restored(self):
        frontend, backend = Mock(), Mock()
        frontend.poll.side_effect = [None, 0]
        backend.poll.return_value = 1
        with patch.object(launcher, 'ready', return_value=False), \
                patch.object(launcher, 'listening', return_value=False), \
                patch.object(launcher, 'ensure_backend') as restore, \
                patch.object(launcher.time, 'sleep'), redirect_stdout(io.StringIO()):
            self.assertEqual(launcher.monitor_servers(frontend, '192.168.1.3', 57583, 8000, 'health', [backend], backend=backend), 0)
        restore.assert_called_once()

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
