"""Start DefenSYS with one Wi-Fi address for the PC, phones and invitations.

Uses only the standard library. Reuses an API server already listening on the
LAN; never stops that server or changes .env, firewall rules, accounts or data.
"""

from __future__ import annotations

import argparse
import ipaddress
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, build_opener
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
HTTP = build_opener(ProxyHandler({}))  # Local traffic must not use a proxy.


def lan_ip(value: str) -> str:
    """Accept only RFC1918 IPv4 addresses; never advertise a loopback address."""
    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as error:
        raise argparse.ArgumentTypeError('Use your PC\'s private IPv4 address.') from error
    if not any(address in network for network in (
        ipaddress.ip_network('10.0.0.0/8'),
        ipaddress.ip_network('172.16.0.0/12'),
        ipaddress.ip_network('192.168.0.0/16'),
    )):
        raise argparse.ArgumentTypeError('Use a Wi-Fi/LAN address, not localhost or a public IP.')
    return str(address)


def detect_lan_ip() -> str:
    # UDP connect selects the default network route; no packet is sent.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.connect(('192.0.2.1', 9))
        return lan_ip(probe.getsockname()[0])


def port(value: str) -> int:
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError('Port must be between 1 and 65535.')
    return number


def android_download_url(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise argparse.ArgumentTypeError('Use an HTTPS release APK download URL without embedded credentials.')
    return value


def listening(host: str, number: int) -> bool:
    try:
        with socket.create_connection((host, number), timeout=0.5):
            return True
    except OSError:
        return False


def ready(url: str) -> bool:
    try:
        with HTTP.open(url, timeout=1) as response:
            return response.status == 200
    except (URLError, OSError):
        return False


def flutter_command() -> list[str]:
    executable = shutil.which('flutter.bat' if os.name == 'nt' else 'flutter')
    if not executable:
        raise RuntimeError('Flutter is not on PATH. Add your Flutter SDK bin directory first.')
    if os.name == 'nt':
        # Run the SDK entry point directly so a stopped launcher leaves no
        # intermediary batch process holding the Dart web server open.
        cache = Path(executable).parent / 'cache'
        dart = cache / 'dart-sdk' / 'bin' / 'dart.exe'
        snapshot = cache / 'flutter_tools.snapshot'
        packages = Path(executable).parent.parent / 'packages' / 'flutter_tools' / '.dart_tool' / 'package_config.json'
        if dart.exists() and snapshot.exists() and packages.exists():
            # Flutter's own batch entry point supplies this package config.
            # Omitting it makes web-server look for DWDS in the app's packages.
            return [str(dart), f'--packages={packages}', str(snapshot)]
    return [executable]


def adb_executable() -> str | None:
    executable = shutil.which('adb')
    if executable:
        return executable
    candidates = []
    for name in ('ANDROID_SDK_ROOT', 'ANDROID_HOME'):
        if os.environ.get(name):
            candidates.append(Path(os.environ[name]))
    if os.name == 'nt' and os.environ.get('LOCALAPPDATA'):
        candidates.append(Path(os.environ['LOCALAPPDATA']) / 'Android' / 'sdk')
    candidates.append(Path.home() / 'Android' / 'Sdk')
    for sdk in candidates:
        executable = sdk / 'platform-tools' / ('adb.exe' if os.name == 'nt' else 'adb')
        if executable.is_file():
            return str(executable)
    return None


def parse_android_devices(output: str) -> dict[str, str]:
    devices = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] in ('device', 'offline', 'unauthorized'):
            devices[parts[0]] = parts[1]
    return devices


def connected_android_device(requested: str | None = None) -> str | None:
    adb = adb_executable()
    if not adb:
        if requested:
            raise RuntimeError('Android platform-tools (adb) was not found. Install it in your Android SDK.')
        print('Android app: no adb found; web and API startup will continue.', flush=True)
        return None
    try:
        result = subprocess.run([adb, 'devices', '-l'], capture_output=True, text=True, timeout=10, check=True)
    except (OSError, subprocess.SubprocessError) as error:
        if requested:
            raise RuntimeError('Unable to read Android devices. Check adb and your debugging connection.') from error
        print('Android app: unable to read devices; web and API startup will continue.', flush=True)
        return None
    devices = parse_android_devices(result.stdout)
    if requested:
        if devices.get(requested) != 'device':
            raise RuntimeError(f'Android device {requested} is not ready. Connect it and accept the debugging prompt, then try again.')
        return requested
    phones = [device for device, state in devices.items()
              if state == 'device' and not device.startswith('emulator-')]
    if len(phones) == 1:
        return phones[0]
    if len(phones) > 1:
        print('Android app: multiple phones connected. Choose one with --android-device <device-id>.', flush=True)
    elif any(state == 'unauthorized' for state in devices.values()):
        print('Android app: unlock your phone and accept the USB/wireless debugging prompt, then rerun the launcher.', flush=True)
    else:
        print('Android app: no phone connected. Connect USB or wireless debugging to include it on the next start.', flush=True)
    return None


def android_command(device: str, host: str, api_port: int, web_port: int) -> list[str]:
    # Leave the installed app running after Flutter finishes deployment.
    # Only web startup owns the terminal's interactive hot-reload commands.
    return flutter_command() + [
        'run', '-d', device, '--debug', '--no-resident',
        f'--dart-define=DEFENSYS_API_HOST={host}',
        f'--dart-define=DEFENSYS_API_PORT={api_port}',
        '--dart-define=DEFENSYS_API_SCHEME=http',
        f'--dart-define=GUEST_PORTAL_URL=http://{host}:{web_port}/#/guest/evaluate',
    ]


def start(command: list[str], cwd: Path) -> subprocess.Popen:
    return subprocess.Popen(
        command, cwd=cwd,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == 'nt' else 0,
        start_new_session=os.name != 'nt',
    )


def stop(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    try:
        if os.name == 'nt':
            process.send_signal(signal.CTRL_BREAK_EVENT)
        else:
            os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        process.kill()
        process.wait()


def wait_for(url: str, process: subprocess.Popen, timeout: int) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f'Server exited with code {process.returncode}. See its output above.')
        if ready(url):
            return
        time.sleep(0.5)
    raise RuntimeError(f'Server did not become ready at {url}. See its output above.')


def is_defensys_web(origin: str) -> bool:
    """Identify our app before reusing an occupied web port."""
    try:
        with HTTP.open(origin + '/', timeout=2) as response:
            return response.status == 200 and b'<title>DefenSYS</title>' in response.read(65536)
    except (URLError, OSError):
        return False


def ensure_backend(host: str, number: int, health: str,
                   owned: list[subprocess.Popen]) -> subprocess.Popen | None:
    if ready(health):
        return None
    if listening('127.0.0.1', number) or listening(host, number):
        raise RuntimeError(f'Port {number} is occupied but the API is not healthy over Wi-Fi. Check the backend terminal. No existing process was stopped.')
    python = ROOT / 'backend' / 'venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    if not python.exists():
        raise RuntimeError('Backend virtual environment is missing. Run backend/setup_venv.ps1 first.')
    backend = start([str(python), 'manage.py', 'runserver', f'0.0.0.0:{number}', '--noreload'], ROOT / 'backend')
    owned.append(backend)
    wait_for(health, backend, timeout=45)
    return backend


def monitor_servers(frontend: subprocess.Popen | None, host: str,
                    web_port: int, api_port: int, health: str,
                    owned: list[subprocess.Popen],
                    mobile: subprocess.Popen | None = None) -> int:
    """Keep a reused API from silently disappearing while the web app stays up."""
    unhealthy = False
    while True:
        if frontend is not None:
            result = frontend.poll()
            if result is not None:
                return result
        elif not listening(host, web_port):
            raise RuntimeError('The existing web session stopped. Run this launcher again.')
        if mobile is not None:
            result = mobile.poll()
            if result is not None:
                if result == 0:
                    print('Android app installed and opened with the shared API address. Flutter deployment finished; the phone app stays open.', flush=True)
                else:
                    print(f'Android deployment exited with code {result}. See its output above. The web app and backend will stay running.', flush=True)
                mobile = None
        if not ready(health):
            if not listening('127.0.0.1', api_port) and not listening(host, api_port):
                print('Backend stopped. Restoring it on the shared Wi-Fi address...', flush=True)
                ensure_backend(host, api_port, health, owned)
                print('Backend restored. You can retry signing in.', flush=True)
                unhealthy = False
            elif not unhealthy:
                print('Backend is listening but its health check failed. Check its terminal; no process will be replaced.', flush=True)
                unhealthy = True
        elif unhealthy:
            print('Backend health check is passing again.', flush=True)
            unhealthy = False
        time.sleep(5)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=lan_ip, help='Override detected IP (e.g. when a VPN is active).')
    parser.add_argument('--web-port', type=port, default=57583)
    parser.add_argument('--api-port', type=port, default=8000)
    parser.add_argument('--check', action='store_true', help='Print addresses and check setup without starting anything.')
    parser.add_argument('--no-browser', action='store_true', help='Leave the PC browser closed.')
    parser.add_argument('--debug', action='store_true', help='Use Flutter debug mode for development; default is a release preview for phone testing.')
    parser.add_argument('--android-download-url', type=android_download_url,
                        help='Published HTTPS release APK URL shown in student/panelist web Settings.')
    android = parser.add_mutually_exclusive_group()
    android.add_argument('--no-android', action='store_true', help='Skip installing/opening the Android app, even if a phone is connected.')
    android.add_argument('--android-device', help='Choose a connected Android device ID when more than one phone is available.')
    args = parser.parse_args(argv)
    owned: list[subprocess.Popen] = []
    try:
        host = args.host or detect_lan_ip()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind((host, 0))  # Reject another device's IP before launching.
        if args.web_port == args.api_port:
            raise RuntimeError('The web app and API need different ports.')
        origin = f'http://{host}:{args.web_port}'
        health = f'http://{host}:{args.api_port}/api/health/'
        device = None if args.no_android else connected_android_device(args.android_device)
        mobile_command = android_command(device, host, args.api_port, args.web_port) if device else None
        command = flutter_command() + [
            'run', '-d', 'web-server', '--debug' if args.debug else '--release', '--web-hostname=0.0.0.0',
            f'--web-port={args.web_port}',
            f'--dart-define=DEFENSYS_WEB_ORIGIN={origin}',
            f'--dart-define=DEFENSYS_API_PORT={args.api_port}',
        ]
        if args.android_download_url:
            command.append(f'--dart-define=DEFENSYS_ANDROID_DOWNLOAD_URL={args.android_download_url}')
        print(f'\nUse this address on the PC AND phone: {origin}', flush=True)
        print(f'Guest portal: {origin}/#/guest/evaluate', flush=True)
        print(f'Phone app API: http://{host}:{args.api_port}/api', flush=True)
        print('Phone and PC must be on the same Wi-Fi. No .env edits are needed in development.', flush=True)
        if args.check:
            print(f'Backend ready: {ready(health)}', flush=True)
            print(f'Web port already in use: {listening("127.0.0.1", args.web_port)}', flush=True)
            print('Flutter options: ' + ' '.join(command[command.index('run'):]), flush=True)
            if mobile_command:
                print('Android options: ' + ' '.join(mobile_command[mobile_command.index('run'):]), flush=True)
            return 0
        existing_web = listening('127.0.0.1', args.web_port) or listening(host, args.web_port)
        if existing_web and not is_defensys_web(origin):
            raise RuntimeError(f'Port {args.web_port} is occupied by an unrecognized or unreachable web server. No existing process was stopped. Free the port or choose --web-port.')
        if ensure_backend(host, args.api_port, health, owned) is None:
            print('Using the existing backend and monitoring its availability. It will stay running when this launcher stops.', flush=True)
        frontend = None
        if existing_web:
            print('Using the existing DefenSYS web session. It will stay running when this launcher stops.', flush=True)
        else:
            frontend = start(command, ROOT / 'frontend')
            owned.append(frontend)
            # Flutter serves HTML before compilation finishes. Wait for the
            # entry point so the browser cannot open a half-built preview.
            wait_for(origin + '/main.dart.js', frontend, timeout=180)
        print(f'\nReady: {origin}/#/login\nKeep this terminal open. Press Ctrl+C to stop servers started here.', flush=True)
        mobile = None
        if mobile_command:
            print(f'Updating and opening the Android app on {device} using http://{host}:{args.api_port}...', flush=True)
            mobile = start(mobile_command, ROOT / 'frontend')
            owned.append(mobile)
        if not args.no_browser:
            webbrowser.open(origin + '/#/login')
        return monitor_servers(frontend, host, args.web_port, args.api_port, health, owned, mobile=mobile)
    except KeyboardInterrupt:
        return 0
    except (OSError, RuntimeError, argparse.ArgumentTypeError) as error:
        print(f'\nCannot start DefenSYS: {error}', file=sys.stderr, flush=True)
        return 1
    finally:
        for process in reversed(owned):
            stop(process)


if __name__ == '__main__':
    raise SystemExit(main())
