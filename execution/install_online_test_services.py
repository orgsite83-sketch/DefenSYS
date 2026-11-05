"""Install one environment's isolated test units and the users/client/off switch.

Requires sudo -v. Does not start or enable services, edit Nginx, or touch production.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

SWITCH = r'''#!/usr/bin/env bash
set -euo pipefail
base="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-status}"
case "$mode" in users|client|off|status) ;; *) echo 'Usage: switch-testing.sh users|client|off|status'; exit 2 ;; esac
exec 9>"$base/switch.lock"
flock -n 9 || { echo 'Another testing switch is in progress.'; exit 1; }
all=(defensys-usertest.service defensys-usertest-ws.service defensys-clienttest.service defensys-clienttest-ws.service)
installed=()
previous=()
for unit in "${all[@]}"; do
  if systemctl cat "$unit" >/dev/null 2>&1; then
    installed+=("$unit")
    if systemctl is-active --quiet "$unit"; then previous+=("$unit"); fi
  fi
done
if [[ "$mode" == status ]]; then
  for unit in "${installed[@]}"; do
    state="$(systemctl is-active "$unit" || true)"
    printf '%s: %s\n' "$unit" "$state"
  done
  free -h
  exit 0
fi
if [[ "$mode" != off ]]; then
  if [[ "$mode" == users ]]; then
    selected=(defensys-usertest.service defensys-usertest-ws.service)
    host=test.defensys.site
    port=8100
  else
    selected=(defensys-clienttest.service defensys-clienttest-ws.service)
    host=client-test.defensys.site
    port=8200
  fi
  for unit in "${selected[@]}"; do
    systemctl cat "$unit" >/dev/null 2>&1 || { echo "Not configured yet: $unit. Nothing was stopped."; exit 1; }
  done
fi
sudo -v
if ((${#installed[@]})); then sudo systemctl stop "${installed[@]}"; fi
if [[ "$mode" == off ]]; then echo 'Both testing backends stopped. Saved data retained.'; exit 0; fi
healthy=false
if sudo systemctl start "${selected[@]}"; then
  for ((attempt=1; attempt<=30; attempt++)); do
    if systemctl is-active --quiet "${selected[0]}" && \
       systemctl is-active --quiet "${selected[1]}" && \
       curl --silent --fail --max-time 2 -H "Host: $host" -H 'X-Forwarded-Proto: https' \
       "http://127.0.0.1:$port/api/health/" >/dev/null; then
      healthy=true
      break
    fi
    sleep 1
  done
fi
if [[ "$healthy" != true ]]; then
  sudo systemctl stop "${selected[@]}"
  if ((${#previous[@]})); then sudo systemctl start "${previous[@]}" || true; fi
  echo 'Selected test backend failed its health check; prior test services were requested again.'
  sudo journalctl -u "${selected[0]}" -u "${selected[1]}" -n 35 --no-pager
  exit 1
fi
echo "$mode backend is healthy on local port $port. Production services were not changed."
echo 'Public URL still depends on the separate Nginx/HTTPS/frontend setup.'
free -h
'''


def unit_text(backend, user, websocket=False, environment='usertest'):
    if environment not in ('usertest', 'clienttest'):
        raise ValueError('Unknown testing environment')
    port = 8100 if environment == 'usertest' else 8200
    label = 'user' if environment == 'usertest' else 'client'
    executable = '/opt/defensys/backend/venv/bin/'
    if websocket:
        command = executable + f'daphne -b 127.0.0.1 -p {port + 1} defensys_backend.asgi:application'
    else:
        command = (executable + f'gunicorn --workers 1 --threads 2 --bind 127.0.0.1:{port} '
                   '--timeout 120 --max-requests 500 --max-requests-jitter 50 '
                   'defensys_backend.wsgi:application')
    return f'''[Unit]
Description=DefenSYS {label} testing {'WebSocket' if websocket else 'HTTP'}
After=network.target postgresql.service redis-server.service

[Service]
User={user}
WorkingDirectory={backend}
EnvironmentFile={backend}/.env
ExecStart={command}
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
MemoryAccounting=yes
MemoryHigh={'160M' if websocket else '320M'}
MemoryMax={'192M' if websocket else '384M'}
NoNewPrivileges=true
PrivateTmp=true
UMask=0077
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--environment', choices=('usertest', 'clienttest'), default='usertest')
    args = parser.parse_args()
    if os.name != 'posix' or os.getuid() == 0:
        parser.error('Run as the normal defensys SSH user, not as root.')
    import pwd
    from dotenv import dotenv_values
    user = pwd.getpwuid(os.getuid()).pw_name
    if user != 'defensys':
        parser.error('Expected the existing defensys service/SSH account.')
    base = Path.home() / 'defensys-environments'
    environment = args.environment
    database = 'defensys_' + environment
    checkout = base / environment
    backend = checkout / 'backend'
    config = dotenv_values(backend / '.env')
    if (config.get('POSTGRES_DB') != database
            or config.get('POSTGRES_USER') != database
            or config.get('DJANGO_SETTINGS_MODULE') != 'defensys_backend.settings_online_' + environment
            or config.get('SMS_BACKEND') != 'console'
            or config.get('DJANGO_DEBUG', '').lower() != 'false'):
        parser.error('Expected the previously provisioned isolated online test configuration.')
    report_name = 'database_restore_report.json' if environment == 'usertest' else 'database_setup_report.json'
    report = json.loads((checkout / 'recovery' / report_name).read_text())
    if report['database'] != database:
        parser.error('Successful test restore report is missing.')
    for binary in ('curl', 'flock', 'systemctl', 'systemd-analyze', 'sudo'):
        if not shutil.which(binary):
            parser.error('Required utility missing: ' + binary)
    import socket
    base_port = 8100 if environment == 'usertest' else 8200
    for port in (base_port, base_port + 1):
        with socket.socket() as probe:
            if probe.connect_ex(('127.0.0.1', port)) == 0:
                parser.error(f'Port {port} is already in use; inspect before installing.')
    units = {
        f'defensys-{environment}.service': unit_text(backend, user, environment=environment),
        f'defensys-{environment}-ws.service': unit_text(backend, user, websocket=True, environment=environment),
    }
    switch = base / 'switch-testing.sh'
    targets = {Path('/etc/systemd/system') / name: text for name, text in units.items()}
    targets[switch] = SWITCH
    for path, content in targets.items():
        if path.is_symlink() or (path.exists() and path.read_text() != content):
            parser.error('Refusing to overwrite an existing different file: ' + str(path))
    print(json.dumps({'services': list(units), 'http_workers': 1,
                      'switch': str(switch), 'apply': args.apply}), flush=True)
    if not args.apply:
        return
    os.umask(0o077)
    operations = checkout / 'operations'
    operations.mkdir(exist_ok=True)
    staged = []
    for name, text in units.items():
        path = operations / name
        path.write_text(text)
        staged.append(str(path))
    subprocess.run(['systemd-analyze', 'verify', '--man=no', *staged], check=True)
    for path in staged:
        subprocess.run(['sudo', '-n', 'install', '-m', '0644', path,
                        '/etc/systemd/system/' + Path(path).name], check=True)
    switch.write_text(SWITCH)
    switch.chmod(0o700)
    subprocess.run(['bash', '-n', str(switch)], check=True)
    subprocess.run(['sudo', '-n', 'systemctl', 'daemon-reload'], check=True)
    print('Installed test-only service units and switch. Nothing started or enabled.')
    print('Start and check testing: ' + str(switch) + (' users' if environment == 'usertest' else ' client'))
    print('Stop testing to free memory: ' + str(switch) + ' off')
    print('Switching starts only the chosen testing environment; production remains running.')


if __name__ == '__main__':
    main()
