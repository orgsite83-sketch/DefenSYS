"""Check the launcher's port conflicts and ownership without starting servers."""

import argparse
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import io
import json
import subprocess
import threading
import unittest
from unittest.mock import Mock, call, patch

from execution import start_local_web as launcher


class NetworkDetectionTests(unittest.TestCase):
    def setUp(self):
        self.wifi = launcher.NetworkAddress('Wi-Fi', '172.20.10.2', True)
        self.ethernet = launcher.NetworkAddress('Ethernet', '192.168.1.3', True)
        self.vpn = launcher.NetworkAddress('VPN', '10.8.0.2', True, True)
        self.vm = launcher.NetworkAddress('VirtualBox', '192.168.56.1', False, True)

    def test_inventory_keeps_hotspot_addresses_and_identifies_virtual_adapters(self):
        records = [
            dict(name='Wi-Fi', address='172.20.10.2', gateway=True, type='Wireless80211'),
            dict(name='USB tethering', address='192.168.42.10', gateway=True, type='Ethernet',
                 description='Remote NDIS based Internet Sharing Device'),
            dict(name='VM', address='192.168.56.1', description='VirtualBox Host-Only Ethernet Adapter'),
            dict(name='VPN', address='10.8.0.2', type='Tunnel'),
            dict(name='Loopback', address='127.0.0.1'),
            dict(name='Unconfigured', address='169.254.1.2'),
            dict(name='Public', address='203.0.113.1'),
            dict(name='IPv6', address='fe80::1'),
            dict(name='Malformed'),
        ]
        result = launcher.parse_network_addresses(json.dumps(records))
        self.assertEqual([item.address for item in result], ['172.20.10.2', '192.168.42.10', '192.168.56.1', '10.8.0.2'])
        self.assertEqual([item.virtual for item in result], [False, False, True, True])

    def test_single_adapter_json_is_supported(self):
        records = dict(name='Wi-Fi', address='172.20.10.2', gateway=True)
        self.assertEqual(launcher.parse_network_addresses(json.dumps(records)), [self.wifi])

    def test_hotspot_is_selected_when_default_route_uses_a_vpn(self):
        with patch.object(launcher, 'default_route_ip', return_value=self.vpn.address):
            self.assertEqual(launcher.detect_lan_ip(addresses=[self.vm, self.vpn, self.wifi]), self.wifi.address)

    def test_hotspot_without_default_route_or_internet_is_supported(self):
        offline_wifi = launcher.NetworkAddress('Wi-Fi', '192.168.43.25')
        with patch.object(launcher, 'default_route_ip', side_effect=OSError('No route')):
            self.assertEqual(launcher.detect_lan_ip(addresses=[self.vm, offline_wifi]), offline_wifi.address)

    def test_public_default_route_does_not_hide_private_hotspot(self):
        with patch.object(launcher, 'default_route_ip', side_effect=argparse.ArgumentTypeError('Public IP')):
            self.assertEqual(launcher.detect_lan_ip(addresses=[self.wifi]), self.wifi.address)

    def test_default_route_is_used_when_it_is_a_lan_adapter(self):
        with patch.object(launcher, 'default_route_ip', return_value=self.ethernet.address):
            self.assertEqual(launcher.detect_lan_ip(addresses=[self.wifi, self.ethernet]), self.ethernet.address)

    def test_interface_override_uses_hotspot_instead_of_ethernet(self):
        with patch.object(launcher, 'default_route_ip', return_value=self.ethernet.address):
            self.assertEqual(launcher.detect_lan_ip(interface='wi-fi', addresses=[self.wifi, self.ethernet]), self.wifi.address)

    def test_missing_interface_never_falls_back_to_another_adapter(self):
        with patch.object(launcher, 'default_route_ip', return_value=self.ethernet.address):
            with self.assertRaisesRegex(RuntimeError, 'No active private IPv4'):
                launcher.detect_lan_ip(interface='Wi-Fi', addresses=[self.ethernet])

    def test_ambiguous_adapters_require_an_override(self):
        with patch.object(launcher, 'default_route_ip', return_value=self.vpn.address):
            with self.assertRaisesRegex(RuntimeError, 'Wi-Fi: 172.20.10.2.*Ethernet: 192.168.1.3'):
                launcher.detect_lan_ip(addresses=[self.wifi, self.ethernet, self.vpn])

    def test_gateway_adapter_is_preferred_over_unrouted_lan(self):
        unrouted = launcher.NetworkAddress('Ethernet', '192.168.1.3')
        with patch.object(launcher, 'default_route_ip', side_effect=OSError('No route')):
            self.assertEqual(launcher.detect_lan_ip(addresses=[unrouted, self.wifi]), self.wifi.address)

    def test_only_virtual_adapters_are_not_advertised_automatically(self):
        with patch.object(launcher, 'default_route_ip', return_value=self.vpn.address):
            with self.assertRaisesRegex(RuntimeError, 'No active LAN/hotspot'):
                launcher.detect_lan_ip(addresses=[self.vm, self.vpn])
            self.assertEqual(launcher.detect_lan_ip(interface='VPN', addresses=[self.vpn]), self.vpn.address)

    def test_default_route_fallback_when_inventory_is_unavailable(self):
        with patch.object(launcher, 'default_route_ip', return_value=self.wifi.address):
            self.assertEqual(launcher.detect_lan_ip(addresses=[]), self.wifi.address)

    def test_windows_inventory_failure_falls_back_without_crashing(self):
        for failure in [OSError('PowerShell missing'), subprocess.TimeoutExpired('powershell', 10)]:
            with self.subTest(failure=failure), patch.object(launcher.os, 'name', 'nt'), \
                    patch.object(launcher.subprocess, 'run', side_effect=failure), \
                    patch.object(launcher.subprocess, 'CREATE_NO_WINDOW', 0, create=True):
                self.assertEqual(launcher.network_addresses(), [])
        with patch.object(launcher.os, 'name', 'nt'), \
                patch.object(launcher.subprocess, 'run', return_value=Mock(stdout='invalid JSON')), \
                patch.object(launcher.subprocess, 'CREATE_NO_WINDOW', 0, create=True):
            self.assertEqual(launcher.network_addresses(), [])


class BrowserApiCheckTests(unittest.TestCase):
    def test_checks_origin_header_and_requires_matching_cors_response(self):
        origin = 'http://172.20.10.2:57583'
        url = 'http://172.20.10.2:8000/api/health/'
        for allowed in [origin, None, '*', 'http://192.168.1.3:57583']:
            with self.subTest(allowed=allowed), patch.object(launcher.HTTP, 'open') as request:
                response = request.return_value.__enter__.return_value
                response.status = 200
                response.headers = {'Access-Control-Allow-Origin': allowed}
                self.assertEqual(launcher.cors_ready(url, origin), allowed == origin)
                self.assertEqual(request.call_args.args[0].get_header('Origin'), origin)
                self.assertEqual(request.call_args.args[0].full_url, url)

    def test_unreachable_api_reports_failed_browser_check(self):
        with patch.object(launcher.HTTP, 'open', side_effect=launcher.URLError('No connection')):
            self.assertFalse(launcher.cors_ready('http://172.20.10.2:8000/api/health/', 'http://172.20.10.2:57583'))


class LocalWebLauncherTests(unittest.TestCase):
    def setup_runtime(self, stack):
        self.output = io.StringIO()
        self.errors = io.StringIO()
        stack.enter_context(redirect_stdout(self.output))
        stack.enter_context(redirect_stderr(self.errors))
        self.detect = stack.enter_context(patch.object(launcher, 'detect_lan_ip', return_value='192.168.1.3'))
        self.addresses = stack.enter_context(patch.object(launcher, 'network_addresses', return_value=[]))
        self.socket = stack.enter_context(patch.object(launcher.socket, 'socket'))
        stack.enter_context(patch.object(launcher, 'flutter_command', return_value=['flutter']))
        self.listening = stack.enter_context(patch.object(launcher, 'listening', return_value=False))
        self.ready = stack.enter_context(patch.object(launcher, 'ready', return_value=True))
        self.cors = stack.enter_context(patch.object(launcher, 'cors_ready', return_value=True))
        self.start = stack.enter_context(patch.object(launcher, 'start'))
        self.start.return_value.poll.return_value = None
        def started(command, cwd, **kwargs):
            if kwargs.get('web_started') is not None:
                kwargs['web_started'].set()
            return self.start.return_value
        self.start.side_effect = started
        self.stop = stack.enter_context(patch.object(launcher, 'stop'))
        self.stop_web = stack.enter_context(patch.object(launcher, 'stop_web'))
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

    def test_check_mode_lists_adapters_and_checks_browser_api_access(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.addresses.return_value = [launcher.NetworkAddress('Wi-Fi', '172.20.10.2', True)]
            self.detect.return_value = '172.20.10.2'
            self.assertEqual(launcher.main(['--check', '--no-android']), 0)
            self.assertIn('Wi-Fi: 172.20.10.2', self.output.getvalue())
            self.assertIn('Browser API access (CORS): True', self.output.getvalue())
            self.cors.assert_called_once_with('http://172.20.10.2:8000/api/health/', 'http://172.20.10.2:57583')
            self.start.assert_not_called()
            self.stop.assert_not_called()

    def test_hotspot_host_is_shared_by_web_and_android(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.android.return_value = 'demo-phone'
            self.assertEqual(launcher.main(['--host', '172.20.10.2', '--no-browser']), 0)
            commands = [item.args[0] for item in self.start.call_args_list]
            self.assertIn('--dart-define=DEFENSYS_WEB_ORIGIN=http://172.20.10.2:57583', commands[0])
            self.assertIn('--dart-define=DEFENSYS_API_HOST=172.20.10.2', commands[1])
            self.detect.assert_not_called()

    def test_interface_flag_is_passed_to_network_detection(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.assertEqual(launcher.main(['--interface', 'Wi-Fi', '--check', '--no-android']), 0)
            self.detect.assert_called_once_with(interface='Wi-Fi', addresses=[])

    def test_host_and_interface_cannot_be_requested_together(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            with self.assertRaises(SystemExit) as error:
                launcher.main(['--host', '172.20.10.2', '--interface', 'Wi-Fi'])
            self.assertEqual(error.exception.code, 2)
            self.start.assert_not_called()

    def test_phone_gateway_address_is_rejected_before_starting_anything(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.socket.return_value.__enter__.return_value.bind.side_effect = OSError('Cannot assign address')
            self.assertEqual(launcher.main(['--host', '172.20.10.1']), 1)
            self.assertIn('rather than the phone/gateway address', self.errors.getvalue())
            self.start.assert_not_called()
            self.android.assert_not_called()
            self.stop_web.assert_not_called()

    def test_check_mode_with_restart_flags_is_still_read_only(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.assertEqual(launcher.main(['--check', '--restart-backend', '--restart-web']), 0)
            self.start.assert_not_called()
            self.stop_backend.assert_not_called()
            self.stop_web.assert_not_called()
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
        for flags in ([], ['--restart-web'], ['--rebuild'], ['--reuse-web']):
            with self.subTest(flags=flags), ExitStack() as stack:
                self.setup_runtime(stack)
                self.listening.return_value = True
                self.assertEqual(launcher.main(flags + ['--no-browser']), 1)
                self.start.assert_not_called()
                self.stop.assert_not_called()
                self.stop_web.assert_not_called()

    def test_normal_start_recompiles_an_existing_web_session(self):
        for flags in ([], ['--restart-web'], ['--rebuild'], ['--debug']):
            with self.subTest(flags=flags), ExitStack() as stack:
                self.setup_runtime(stack)
                self.listening.return_value = True
                self.is_web.return_value = True
                wait = stack.enter_context(patch.object(launcher, 'wait_for'))
                self.assertEqual(launcher.main(flags + ['--no-android', '--no-browser']), 0)
                self.stop_web.assert_called_once_with('192.168.1.3', 57583)
                self.start.assert_called_once()
                command = self.start.call_args.args[0]
                self.assertIn('web-server', command)
                self.assertIn('--debug' if '--debug' in flags else '--release', command)
                self.assertIn('--dart-define=DEFENSYS_WEB_ORIGIN=http://192.168.1.3:57583', command)
                self.assertIn('--dart-define=DEFENSYS_API_PORT=8000', command)
                wait.assert_called_once()
                self.assertIs(wait.call_args.kwargs['web_started'], self.start.call_args.kwargs['web_started'])
                self.stop.assert_called_once_with(self.start.return_value)

    def test_failed_web_stop_does_not_start_a_second_server_or_open_browser(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.return_value = True
            self.is_web.return_value = True
            self.stop_web.side_effect = RuntimeError('web port is still occupied')
            self.assertEqual(launcher.main(['--no-android']), 1)
            self.start.assert_not_called()
            self.stop.assert_not_called()
            self.browser.assert_not_called()

    def test_reuse_and_rebuild_cannot_be_requested_together(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            with self.assertRaises(SystemExit) as error:
                launcher.main(['--reuse-web', '--rebuild'])
            self.assertEqual(error.exception.code, 2)
            self.start.assert_not_called()
            self.stop_web.assert_not_called()

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
            self.assertEqual(launcher.main(['--reuse-web', '--no-browser']), 0)
            self.start.assert_called_once()
            self.assertIn('manage.py', self.start.call_args.args[0])
            self.assertIsNone(self.monitor.call_args.args[0])
            self.stop.assert_called_once_with(backend)

    def test_existing_web_and_api_can_be_reused_without_starting_or_stopping_them(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.return_value = True
            self.is_web.return_value = True
            self.assertEqual(launcher.main(['--reuse-web', '--no-browser']), 0)
            self.start.assert_not_called()
            self.stop.assert_not_called()
            self.stop_web.assert_not_called()

    def test_connected_phone_is_included_when_web_and_api_are_already_up(self):
        with ExitStack() as stack:
            self.setup_runtime(stack)
            self.listening.return_value = True
            self.is_web.return_value = True
            self.android.return_value = 'demo-phone'
            phone = Mock()
            self.start.return_value = phone
            self.assertEqual(launcher.main(['--reuse-web', '--no-browser']), 0)
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
            self.assertEqual(launcher.main(['--debug', '--reuse-web', '--no-browser']), 0)
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


class WebRestartTests(unittest.TestCase):
    def test_waits_for_the_old_server_to_release_the_port(self):
        with patch.object(launcher, 'stop_port', return_value=True) as stop, \
                patch.object(launcher, 'listening', side_effect=[True, False, False]) as listening, \
                patch.object(launcher.time, 'sleep') as sleep:
            launcher.stop_web('192.168.1.3', 57583)
        stop.assert_called_once_with(57583)
        sleep.assert_called_once_with(0.2)
        self.assertEqual(listening.call_args_list[-1], call('192.168.1.3', 57583))

    def test_failed_stop_is_reported(self):
        with patch.object(launcher, 'stop_port', return_value=False), \
                patch.object(launcher, 'listening') as listening, \
                self.assertRaisesRegex(RuntimeError, 'Could not stop'):
            launcher.stop_web('192.168.1.3', 57583)
        listening.assert_not_called()

    def test_port_that_stays_occupied_is_reported_without_another_stop(self):
        with patch.object(launcher, 'stop_port', return_value=True) as stop, \
                patch.object(launcher, 'listening', return_value=True), \
                patch.object(launcher.time, 'monotonic', side_effect=[0, 5]), \
                self.assertRaisesRegex(RuntimeError, 'still occupied'):
            launcher.stop_web('192.168.1.3', 57583)
        stop.assert_called_once()

    def test_taskkill_failure_does_not_count_as_a_successful_stop(self):
        with patch.object(launcher.os, 'name', 'nt'), \
                patch.object(launcher, 'pids_listening_on', return_value=[123]), \
                patch.object(launcher.subprocess, 'run', return_value=Mock(returncode=1)):
            self.assertFalse(launcher.stop_port(57583))


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
