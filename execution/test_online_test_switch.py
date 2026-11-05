"""Exercise switching with fake commands; never contact systemd or start services."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from execution.install_online_test_services import SWITCH, unit_text


class SwitchTests(unittest.TestCase):
    def test_units_use_isolated_settings_and_one_worker(self):
        http = unit_text('/home/defensys/defensys-environments/usertest/backend', 'defensys')
        self.assertIn('--workers 1', http)
        self.assertIn('127.0.0.1:8100', http)
        self.assertIn('EnvironmentFile=/home/defensys/defensys-environments/usertest/backend/.env', http)
        self.assertNotIn('[Install]', http)
        client = unit_text('/home/defensys/defensys-environments/clienttest/backend', 'defensys',
                           environment='clienttest')
        self.assertIn('127.0.0.1:8200', client)
        self.assertNotIn('127.0.0.1:8100', client)
        self.assertIn('clienttest/backend/.env', client)
        ws = unit_text('/home/defensys/defensys-environments/clienttest/backend', 'defensys',
                       websocket=True, environment='clienttest')
        self.assertIn('-p 8201', ws)

    def test_switch_limits_changes_to_configured_test_units(self):
        bash = Path('C:/Program Files/Git/bin/bash.exe') if os.name == 'nt' else shutil.which('bash')
        if not bash or not Path(bash).exists():
            self.skipTest('Bash is unavailable')
        root = Path(__file__).resolve().parents[1]
        (root / '.tmp').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root / '.tmp') as temp:
            directory = Path(temp)
            switch = directory / 'switch-testing.sh'
            switch.write_text(SWITCH, encoding='utf-8', newline='\n')
            subprocess.run([str(bash), '-n', str(switch)], check=True)
            harness = r'''
systemctl() {
  case "$1" in
    cat) [[ "$2" == defensys-usertest.service || "$2" == defensys-usertest-ws.service ||
            ( "${HAS_CLIENT:-0}" == 1 && ( "$2" == defensys-clienttest.service || "$2" == defensys-clienttest-ws.service ) ) ]] ;;
    is-active) return 0 ;;
    *) echo "Unexpected direct systemctl: $*"; return 99 ;;
  esac
}
sudo() { echo "SUDO $*"; }
flock() { return 0; }
free() { return 0; }
curl() { return 0; }
export -f systemctl sudo flock free curl
export HAS_CLIENT="${3:-0}"
bash "$1" "$2"
'''
            for mode, code, has_client in [('client', 1, False), ('users', 0, False), ('off', 0, False),
                                           ('status', 0, False), ('invalid', 2, False), ('client', 0, True),
                                           ('users', 0, True), ('off', 0, True)]:
                result = subprocess.run([str(bash), '-c', harness, 'harness', str(switch), mode,
                                         '1' if has_client else '0'],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                commands = [line for line in result.stdout.splitlines() if line.startswith('SUDO')]
                self.assertFalse(any('defensys.service' in line or 'defensys-ws.service' in line for line in commands))
                if not has_client:
                    self.assertFalse(any('clienttest' in line for line in commands))
                if mode in ('status', 'invalid') or (mode == 'client' and not has_client):
                    self.assertEqual(commands, [])
                if mode == 'off':
                    self.assertFalse(any('start ' in line for line in commands))
                if mode == 'users':
                    self.assertTrue(any('start defensys-usertest.service defensys-usertest-ws.service' in line for line in commands))
                    self.assertFalse(any('start defensys-clienttest' in line for line in commands))
                if mode == 'client' and has_client:
                    self.assertTrue(any('start defensys-clienttest.service defensys-clienttest-ws.service' in line for line in commands))
                    self.assertFalse(any('start defensys-usertest' in line for line in commands))


if __name__ == '__main__':
    unittest.main()
