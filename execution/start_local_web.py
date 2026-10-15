"""Start DefenSYS with one LAN/hotspot address for the PC, phones and invitations.

Uses only the standard library. Reuses a current API server on the LAN and
enables Django's code reload. Compiles the current frontend on every start
unless --reuse-web is requested. Restarts only identified DefenSYS servers;
does not change .env, firewall rules, accounts or data.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import ipaddress
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
HTTP = build_opener(ProxyHandler({}))  # Local traffic must not use a proxy.
LAN_NETWORKS = tuple(ipaddress.ip_network(value) for value in (
    '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16',
))


def lan_ip(value: str) -> str:
    """Accept only RFC1918 IPv4 addresses; never advertise a loopback address."""
    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as error:
        raise argparse.ArgumentTypeError('Use your PC\'s private IPv4 address.') from error
    if not any(address in network for network in LAN_NETWORKS):
        raise argparse.ArgumentTypeError('Use a LAN/hotspot address, not localhost or a public IP.')
    return str(address)


@dataclass(frozen=True)
class NetworkAddress:
    name: str
    address: str
    has_gateway: bool = False
    virtual: bool = False


def parse_network_addresses(output: str) -> list[NetworkAddress]:
    """Keep active RFC1918 addresses from the Windows adapter inventory."""
    records = json.loads(output or '[]')
    if isinstance(records, dict):
        records = [records]
    if not isinstance(records, list):
        raise ValueError('Invalid network adapter inventory')
    addresses = []
    for record in records:
        if not isinstance(record, dict):
            continue
        try:
            address = lan_ip(record['address'])
            name = record['name']
            if not isinstance(name, str) or not name:
                continue
        except (KeyError, TypeError, argparse.ArgumentTypeError):
            continue
        description = str(record.get('description', '')).casefold()
        virtual = record.get('type') == 'Tunnel' or any(marker in description for marker in (
            'virtual', 'vpn', 'wireguard', 'wintun', 'tap-', 'tun-',
            'hyper-v', 'vmware', 'tailscale', 'zerotier', 'loopback',
        ))
        candidate = NetworkAddress(name, address, record.get('gateway') is True, virtual)
        if candidate not in addresses:
            addresses.append(candidate)
    return addresses


def network_addresses() -> list[NetworkAddress]:
    """Read adapters without internet access, WMI privileges or extra packages."""
    if os.name == 'nt':
        # .NET works on Windows even where Get-NetIPConfiguration/CIM is denied.
        # Wi-Fi and USB tethering appear as ordinary active network interfaces.
        script = """
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
@([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
    Where-Object {$_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback'} |
    ForEach-Object {
        $adapter = $_
        $properties = $adapter.GetIPProperties()
        $gateway = @($properties.GatewayAddresses | Where-Object {
            $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -ne '0.0.0.0'
        }).Count -gt 0
        $properties.UnicastAddresses | Where-Object {
            $_.Address.AddressFamily -eq 'InterNetwork' -and $_.DuplicateAddressDetectionState -eq 'Preferred'
        } | ForEach-Object {
            [pscustomobject]@{
                name = $adapter.Name
                description = $adapter.Description
                type = $adapter.NetworkInterfaceType.ToString()
                address = $_.Address.ToString()
                gateway = $gateway
            }
        }
    }) | ConvertTo-Json -Compress
"""
        try:
            result = subprocess.run(
                ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
                capture_output=True, text=True, encoding='utf-8', timeout=10, check=True,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
            return parse_network_addresses(result.stdout)
        except (OSError, subprocess.SubprocessError, ValueError):
            # Preserve default-route detection if PowerShell is unavailable.
            return []
    try:
        hostname = socket.gethostname()
        records = [dict(name=hostname, address=entry[4][0]) for entry in
                   socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_DGRAM)]
        return parse_network_addresses(json.dumps(records))
    except OSError:
        return []


def default_route_ip() -> str:
    # UDP connect selects the route; no packet or internet request is sent.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.connect(('192.0.2.1', 9))
        return lan_ip(probe.getsockname()[0])


def detect_lan_ip(*, interface: str | None = None,
                  addresses: list[NetworkAddress] | None = None) -> str:
    addresses = network_addresses() if addresses is None else addresses
    try:
        route = default_route_ip()
    except (OSError, argparse.ArgumentTypeError):
        route = None
    if interface is not None:
        candidates = [item for item in addresses if item.name.casefold() == interface.casefold()]
        if not candidates:
            raise RuntimeError(f'No active private IPv4 address on interface {interface!r}. Use --check to list adapters or --host <PC-IP>.')
    else:
        candidates = [item for item in addresses if not item.virtual]
        if not addresses and route:
            return route
        if not candidates:
            raise RuntimeError('No active LAN/hotspot IPv4 address found. Connect the PC to Wi-Fi, a phone hotspot or USB tethering, then retry; use --host <PC-IP> if adapter detection is unavailable.')
    if route in [item.address for item in candidates]:
        return route
    if interface is None:
        candidates = [item for item in candidates if item.has_gateway] or candidates
    if len(candidates) == 1:
        return candidates[0].address
    choices = ', '.join(f'{item.name}: {item.address}' for item in candidates)
    raise RuntimeError(f'Multiple LAN/hotspot addresses found ({choices}). Choose --interface "<adapter-name>" or --host <PC-IP>.')


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
        # A cold database connection or a concurrent Flutter release build can
        # take over a second. Don't disconnect healthy ASGI requests so early.
        with HTTP.open(url, timeout=5) as response:
            return response.status == 200
    except (URLError, OSError):
        return False


def cors_ready(url: str, origin: str) -> bool:
    """Check browser API access; a plain health request cannot detect CORS failures."""
    try:
        with HTTP.open(Request(url, headers={'Origin': origin}), timeout=5) as response:
            return response.status == 200 and response.headers.get('Access-Control-Allow-Origin') == origin
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


def android_command(device: str, host: str, api_port: int, web_port: int,
                    *, debug: bool = False) -> list[str]:
    # Leave the installed app running after Flutter finishes deployment.
    # Only web startup owns the terminal's interactive hot-reload commands.
    return flutter_command() + [
        'run', '-d', device, '--debug' if debug else '--release', '--no-resident',
        f'--dart-define=DEFENSYS_API_HOST={host}',
        f'--dart-define=DEFENSYS_API_PORT={api_port}',
        '--dart-define=DEFENSYS_API_SCHEME=http',
        f'--dart-define=GUEST_PORTAL_URL=http://{host}:{web_port}/#/guest/evaluate',
    ]


def forward_web_output(process: subprocess.Popen, started: threading.Event) -> None:
    """Forward Flutter logs and recognize its post-compilation server message."""
    for line in process.stdout:
        try:
            print(line, end='', flush=True)
        except UnicodeEncodeError:
            # Redirected Windows terminals may still use a legacy code page.
            encoding = sys.stdout.encoding or 'utf-8'
            print(line.encode(encoding, errors='replace').decode(encoding),
                  end='', flush=True)
        # Flutter opens the HTTP port before building and may serve old files.
        # WebServerDevice prints this only after the current build succeeds.
        if ' is being served at http://' in line:
            started.set()


def start(command: list[str], cwd: Path,
          *, web_started: threading.Event | None = None) -> subprocess.Popen:
    output = {}
    if web_started is not None:
        output = dict(stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                      text=True, encoding='utf-8', errors='replace', bufsize=1)
    process = subprocess.Popen(
        command, cwd=cwd,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name == 'nt' else 0,
        start_new_session=os.name != 'nt',
        **output,
    )
    if web_started is not None:
        threading.Thread(target=forward_web_output, args=(process, web_started),
                         daemon=True).start()
    return process


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
        # Django's reloader and Windows' venv redirector both spawn children.
        # Killing just the parent can leave an old API holding the port open.
        if os.name == 'nt':
            subprocess.run(['taskkill', '/F', '/T', '/PID', str(process.pid)],
                           capture_output=True, check=False, timeout=10)
        else:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)


def wait_for(url: str, process: subprocess.Popen, timeout: int,
             *, web_started: threading.Event | None = None) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f'Server exited with code {process.returncode}. See its output above.')
        if (web_started is None or web_started.is_set()) and ready(url):
            return
        time.sleep(0.5)
    raise RuntimeError(f'Server did not become ready at {url}. See its output above.')


def is_defensys_web(origin: str) -> bool:
    """Identify our app before restarting or reusing an occupied web port."""
    try:
        with HTTP.open(origin + '/', timeout=2) as response:
            return response.status == 200 and b'<title>DefenSYS</title>' in response.read(65536)
    except (URLError, OSError):
        return False


def pids_listening_on(number: int) -> list[int]:
    """Find process IDs listening on a TCP port."""
    pids = []
    if os.name == 'nt':
        try:
            output = subprocess.check_output(['netstat', '-ano', '-p', 'tcp'], text=True)
            for line in output.splitlines():
                parts = line.split()
                if len(parts) >= 5 and parts[0] == 'TCP' and parts[3] == 'LISTENING':
                    local_address = parts[1]
                    if local_address.endswith(f':{number}'):
                        try:
                            pids.append(int(parts[4]))
                        except ValueError:
                            pass
        except (OSError, subprocess.SubprocessError):
            pass
    return list(dict.fromkeys(pids))


def stop_port(number: int) -> bool:
    """Terminate any process listening on the given port."""
    pids = pids_listening_on(number)
    stopped = False
    for pid in pids:
        try:
            if os.name == 'nt':
                result = subprocess.run(['taskkill', '/F', '/T', '/PID', str(pid)],
                                        capture_output=True, check=False, timeout=10)
                if result.returncode:
                    continue
            else:
                os.kill(pid, signal.SIGTERM)
            stopped = True
        except (OSError, subprocess.SubprocessError):
            pass
    return stopped


def stop_web(host: str, number: int) -> None:
    """Stop an already identified DefenSYS web server and wait for its port."""
    if not stop_port(number):
        raise RuntimeError(f'Could not stop the DefenSYS web server on port {number}. Stop it in its terminal and run this launcher again.')
    deadline = time.monotonic() + 5
    while listening('127.0.0.1', number) or listening(host, number):
        if time.monotonic() >= deadline:
            raise RuntimeError(f'Port {number} is still occupied after stopping the DefenSYS web server. No other process was stopped.')
        time.sleep(0.2)


@dataclass(frozen=True)
class BackendProcess:
    pid: int
    root_pid: int
    reload_enabled: bool


def windows_python_processes() -> dict[int, dict]:
    """Read ownership metadata, without depending on psutil or WMIC."""
    if os.name != 'nt':
        return {}
    script = (
        "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); "
        "@(Get-CimInstance Win32_Process -Filter "
        "\"Name = 'python.exe' OR Name = 'pythonw.exe'\" | "
        "Select-Object ProcessId, ParentProcessId, CommandLine) | "
        "ConvertTo-Json -Compress"
    )
    try:
        result = subprocess.run(
            ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script],
            capture_output=True, text=True, encoding='utf-8', timeout=10, check=True,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        records = json.loads(result.stdout or '[]')
        if isinstance(records, dict):
            records = [records]
        return {int(record['ProcessId']): record for record in records}
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return {}


def workspace_backend_args(command_line: str, number: int) -> list[str] | None:
    """Require this repo's venv, Django entry point and API port before a stop."""
    try:
        args = [arg.strip('"') for arg in shlex.split(command_line, posix=False)]
    except ValueError:
        return None
    if len(args) < 4:
        return None

    def normalized(value: str) -> str:
        return value.replace('/', '\\').casefold()

    python = ROOT / 'backend' / 'venv' / 'Scripts' / 'python.exe'
    manage = ROOT / 'backend' / 'manage.py'
    if normalized(args[0]) != normalized(str(python)):
        return None
    if normalized(args[1]) not in ('manage.py', normalized(str(manage))):
        return None
    if args[2] != 'runserver' or not args[3].endswith(f':{number}'):
        return None
    return args


def backend_listener(number: int) -> BackendProcess | None:
    """Identify the listener and its matching Django parents on Windows.

    Unknown or manually launched servers remain untouched. On platforms where
    ownership cannot be verified, an explicit restart requires a manual stop.
    """
    pids = pids_listening_on(number)
    if len(pids) != 1:
        return None
    processes = windows_python_processes()
    record = processes.get(pids[0], {})
    args = workspace_backend_args(record.get('CommandLine') or '', number)
    if args is None:
        return None
    root_pid = pids[0]
    seen = {root_pid}
    while record.get('ParentProcessId') in processes:
        parent_pid = record['ParentProcessId']
        parent = processes[parent_pid]
        if parent_pid in seen or workspace_backend_args(parent.get('CommandLine') or '', number) is None:
            break
        seen.add(parent_pid)
        root_pid = parent_pid
        record = parent
    return BackendProcess(pids[0], root_pid, '--noreload' not in args)


def stop_backend(backend: BackendProcess, host: str, number: int) -> None:
    """Stop the verified backend tree, including redirector/reloader parents."""
    result = subprocess.run(
        ['taskkill', '/F', '/T', '/PID', str(backend.root_pid)],
        capture_output=True, text=True, timeout=10, check=False,
    )
    if result.returncode:
        raise RuntimeError(f'Could not stop the identified backend (PID {backend.root_pid}). Check its terminal.')
    deadline = time.monotonic() + 5
    while listening('127.0.0.1', number) or listening(host, number):
        if time.monotonic() >= deadline:
            raise RuntimeError(f'Port {number} is still occupied after the backend restart. No other process was stopped.')
        time.sleep(0.2)


def backend_parent_alive(backend: BackendProcess, number: int) -> bool:
    """The reloader parent remains alive while its HTTP worker restarts."""
    record = windows_python_processes().get(backend.root_pid, {})
    return workspace_backend_args(record.get('CommandLine') or '', number) is not None


def ensure_backend(host: str, number: int, health: str,
                   owned: list[subprocess.Popen],
                   *, restart: bool = False) -> subprocess.Popen | None:
    if ready(health):
        existing = backend_listener(number)
        if existing is None:
            if restart:
                raise RuntimeError(f'Cannot verify that the server on port {number} belongs to this workspace. Stop it manually before restarting; no existing process was stopped.')
            return None
        if existing.reload_enabled and not restart:
            return None
        reason = 'an explicit restart was requested' if restart else 'automatic code reload was disabled'
        print(f'Restarting the workspace backend: {reason}.', flush=True)
        stop_backend(existing, host, number)
    if listening('127.0.0.1', number) or listening(host, number):
        raise RuntimeError(f'Port {number} is occupied but the API is not healthy over the LAN/hotspot. Check the backend terminal. No existing process was stopped.')
    python = ROOT / 'backend' / 'venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    if not python.exists():
        raise RuntimeError('Backend virtual environment is missing. Run backend/setup_venv.ps1 first.')
    backend = start([str(python), 'manage.py', 'runserver', f'0.0.0.0:{number}'], ROOT / 'backend')
    owned.append(backend)
    wait_for(health, backend, timeout=45)
    print('Backend ready with automatic Python code reload.', flush=True)
    return backend


def monitor_servers(frontend: subprocess.Popen | None, host: str,
                    web_port: int, api_port: int, health: str,
                    owned: list[subprocess.Popen],
                    mobile: subprocess.Popen | None = None,
                    backend: subprocess.Popen | None = None,
                    external_backend: BackendProcess | None = None) -> int:
    """Keep a reused API from silently disappearing while the web app stays up."""
    unhealthy = False
    reloading = False
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
                parent_alive = (backend is not None and backend.poll() is None) or (
                    external_backend is not None and backend_parent_alive(external_backend, api_port)
                )
                if parent_alive:
                    if not reloading:
                        print('Backend is reloading. Waiting for its existing process; no second server will be started.', flush=True)
                    reloading = True
                else:
                    print('Backend stopped. Restoring it on the shared LAN/hotspot address...', flush=True)
                    backend = ensure_backend(host, api_port, health, owned)
                    external_backend = backend_listener(api_port) if backend is None else None
                    print('Backend restored. You can retry signing in.', flush=True)
                    unhealthy = False
                    reloading = False
            elif not unhealthy:
                print('Backend is listening but its health check failed. Check its terminal; no process will be replaced.', flush=True)
                unhealthy = True
        elif unhealthy or reloading:
            print('Backend health check is passing again.', flush=True)
            unhealthy = False
            reloading = False
        time.sleep(5)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    network = parser.add_mutually_exclusive_group()
    network.add_argument('--host', type=lan_ip, help="Use this PC's private LAN/hotspot IPv4 address.")
    network.add_argument('--interface', help='Choose an active network adapter by name (e.g. "Wi-Fi" or "Ethernet 2").')
    parser.add_argument('--web-port', type=port, default=57583)
    parser.add_argument('--api-port', type=port, default=8000)
    parser.add_argument('--check', action='store_true', help='Print addresses and check setup without starting anything.')
    parser.add_argument('--no-browser', action='store_true', help='Leave the PC browser closed.')
    parser.add_argument('--debug', action='store_true', help='Use Flutter debug mode for web and Android development; both default to release mode for phone testing.')
    web = parser.add_mutually_exclusive_group()
    web.add_argument('--restart-web', '--rebuild', action='store_true',
                     help='Compile the current frontend (the default); retained for existing commands.')
    web.add_argument('--reuse-web', action='store_true',
                     help='Reuse an existing DefenSYS web session without compiling. Its code and compiled settings may be older.')
    parser.add_argument('--restart-backend', action='store_true',
                        help='Restart the identified workspace backend, including changes to .env. New servers automatically reload Python changes.')
    parser.add_argument('--android-download-url', type=android_download_url,
                        help='Published HTTPS release APK URL shown in student/panelist web Settings.')
    android = parser.add_mutually_exclusive_group()
    android.add_argument('--no-android', action='store_true', help='Skip installing/opening the Android app, even if a phone is connected.')
    android.add_argument('--android-device', help='Choose a connected Android device ID when more than one phone is available.')
    args = parser.parse_args(argv)
    owned: list[subprocess.Popen] = []
    try:
        addresses = network_addresses()
        if args.check:
            print('\nActive private IPv4 addresses:', flush=True)
            for item in addresses:
                kind = 'virtual/VPN' if item.virtual else 'LAN/hotspot'
                print(f'  {item.name}: {item.address} ({kind})', flush=True)
            if not addresses:
                print('  Adapter inventory unavailable or no active private IPv4; trying the default route.', flush=True)
        host = args.host or detect_lan_ip(interface=args.interface, addresses=addresses)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            try:
                probe.bind((host, 0))  # Reject another device's IP before launching.
            except OSError as error:
                raise RuntimeError(f'{host} is not available on this PC. Use the PC address on the hotspot, rather than the phone/gateway address; run --check after connecting.') from error
        if args.web_port == args.api_port:
            raise RuntimeError('The web app and API need different ports.')
        origin = f'http://{host}:{args.web_port}'
        health = f'http://{host}:{args.api_port}/api/health/'
        device = None if args.no_android else connected_android_device(args.android_device)
        mobile_command = android_command(device, host, args.api_port, args.web_port,
                                         debug=args.debug) if device else None
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
        selected = next((item for item in addresses if item.address == host), None)
        if selected:
            print(f'Network adapter: {selected.name}', flush=True)
        print('Connect the PC and client devices to the same Wi-Fi or phone hotspot. No .env edits are needed in development.', flush=True)
        if args.check:
            backend_ready = ready(health)
            print(f'API health URL: {health}', flush=True)
            print(f'Backend ready: {backend_ready}', flush=True)
            if backend_ready:
                print(f'Browser API access (CORS): {cors_ready(health, origin)}', flush=True)
            print(f'Web port already in use: {listening("127.0.0.1", args.web_port)}', flush=True)
            print('Web startup: ' + ('reuse an existing session if available' if args.reuse_web else 'compile the current frontend'), flush=True)
            print('Flutter options: ' + ' '.join(command[command.index('run'):]), flush=True)
            if mobile_command:
                print('Android options: ' + ' '.join(mobile_command[mobile_command.index('run'):]), flush=True)
            print('On the phone, open the API health URL first. If it works only on the PC, check the current Windows firewall profile and whether the hotspot permits device-to-device traffic.', flush=True)
            return 0
        existing_web = listening('127.0.0.1', args.web_port) or listening(host, args.web_port)
        if existing_web and not is_defensys_web(origin):
            raise RuntimeError(f'Port {args.web_port} is occupied by an unrecognized or unreachable web server. No existing process was stopped. Free the port or choose --web-port.')
        if existing_web and not args.reuse_web:
            print(f'Stopping the existing DefenSYS web server on port {args.web_port} to compile the current frontend...', flush=True)
            stop_web(host, args.web_port)
            existing_web = False
        backend = ensure_backend(host, args.api_port, health, owned, restart=args.restart_backend)
        external_backend = backend_listener(args.api_port) if backend is None else None
        if backend is None:
            print('Using the existing backend and monitoring its availability. It will stay running when this launcher stops.', flush=True)
        frontend = None
        if existing_web:
            print('Using the existing DefenSYS web session because --reuse-web was requested. It will stay running when this launcher stops.', flush=True)
            print('Compilation skipped. Frontend code and compiled settings may be older. Run without --reuse-web to update them.', flush=True)
        else:
            print('Compiling the current frontend. Wait for Ready: before opening or reloading the browser.', flush=True)
            web_started = threading.Event()
            frontend = start(command, ROOT / 'frontend', web_started=web_started)
            owned.append(frontend)
            # Cached entry points are reachable while Flutter recompiles.
            # Require its post-build message as well as a reachable entry point.
            wait_for(origin + '/main.dart.js', frontend, timeout=300,
                     web_started=web_started)
        print(f'\nReady: {origin}/#/login\nKeep this terminal open. Press Ctrl+C to stop servers started here.', flush=True)
        mobile = None
        if mobile_command:
            print(f'Updating and opening the Android app on {device} using http://{host}:{args.api_port}...', flush=True)
            mobile = start(mobile_command, ROOT / 'frontend')
            owned.append(mobile)
        if not args.no_browser:
            webbrowser.open(origin + '/#/login')
        return monitor_servers(frontend, host, args.web_port, args.api_port, health, owned,
                               mobile=mobile, backend=backend, external_backend=external_backend)
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
