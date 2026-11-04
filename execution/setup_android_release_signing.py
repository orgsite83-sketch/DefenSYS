"""Create a private permanent testing-to-release Android signing identity once.

Refuses existing keys/configuration. Secrets are passed to keytool via environment
variables and stored only in ignored recovery/config files, never printed.
"""
import os
from pathlib import Path
import secrets
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    config = ROOT / 'frontend/android/key.properties'
    backup = ROOT / '.backups/android-signing'
    key = backup / 'defensys-release.jks'
    recovery = backup / 'key.properties.recovery'
    if any(path.exists() for path in (config, key, recovery)):
        raise FileExistsError('Signing identity/configuration already exists; nothing was replaced.')
    keytool = shutil.which('keytool')
    if not keytool:
        candidate = Path('C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe')
        keytool = str(candidate) if candidate.is_file() else None
    if not keytool:
        raise FileNotFoundError('Java keytool is required.')
    backup.mkdir(parents=True, exist_ok=True)
    password = secrets.token_urlsafe(36)
    content = f'storeFile={key.as_posix()}\nstorePassword={password}\nkeyAlias=defensys\nkeyPassword={password}\n'
    with recovery.open('x', encoding='utf-8') as stream:
        stream.write(content)
    recovery.chmod(0o600)
    env = {**os.environ, 'DEFENSYS_RELEASE_KEY_PASSWORD': password}
    subprocess.run([keytool, '-genkeypair', '-keystore', str(key), '-storetype', 'JKS',
        '-alias', 'defensys', '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
        '-dname', 'CN=DefenSYS Release,O=DefenSYS,C=PH',
        '-storepass:env', 'DEFENSYS_RELEASE_KEY_PASSWORD', '-keypass:env', 'DEFENSYS_RELEASE_KEY_PASSWORD'],
        env=env, check=True, capture_output=True)
    key.chmod(0o600)
    with config.open('x', encoding='utf-8') as stream:
        stream.write(content)
    config.chmod(0o600)
    print('Created private release identity. Keep .backups/android-signing and frontend/android/key.properties private; copy recovery files to a secure second location.')


if __name__ == '__main__':
    main()
