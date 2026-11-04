"""Build and verify a versioned web/APK release locally, without publishing it.

Output is under .tmp/releases. APK preparation requires permanent signing keys.
No credentials, database writes, SSH operations, or live metadata changes occur.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def flutter_command():
    binary = shutil.which('flutter')
    if not binary:
        raise RuntimeError('Flutter must be on PATH.')
    sdk = Path(binary).resolve().parent.parent
    dart = sdk / 'bin/cache/dart-sdk/bin' / ('dart.exe' if os.name == 'nt' else 'dart')
    snapshot = sdk / 'bin/cache/flutter_tools.snapshot'
    if dart.is_file() and snapshot.is_file():
        return [str(dart), f'--packages={sdk / "packages/flutter_tools/.dart_tool/package_config.json"}', str(snapshot)]
    return [binary]


def verify_web(directory):
    required = ['index.html', 'main.dart.js', 'flutter_bootstrap.js', 'assets/FontManifest.json',
                'assets/AssetManifest.bin.json', 'manifest.json', 'icons/Icon-192.png', 'flutter_service_worker.js']
    for name in required:
        path = directory / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f'Missing release file: {name}')
    bootstrap = (directory / 'flutter_bootstrap.js').read_text(encoding='utf-8')
    if '{{flutter_js}}' in bootstrap or 'entrypointBaseUrl' not in bootstrap or 'assetBase' not in bootstrap:
        raise ValueError('The compiled versioned bootstrap is invalid.')
    worker = (directory / 'flutter_service_worker.js').read_text(encoding='utf-8')
    if worker != (ROOT / 'deployment/web/retire_flutter_service_worker.js').read_text(encoding='utf-8'):
        raise ValueError('The legacy worker retirement script was not packaged.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['web', 'android'])
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', type=int, required=True)
    parser.add_argument('--origin', default='https://defensys.site')
    parser.add_argument('--application-id', default='com.example.user')
    args = parser.parse_args()
    from urllib.parse import urlsplit
    origin = urlsplit(args.origin)
    if origin.scheme != 'https' or not origin.hostname or origin.username or origin.password or origin.query or origin.fragment or origin.path not in ('', '/'):
        parser.error('--origin must be a public HTTPS origin without a path or credentials.')
    if not re.fullmatch(r'\d{1,5}\.\d{1,5}\.\d{1,5}', args.version) or not 1 <= args.build <= 2100000000:
        parser.error('Use a semantic version and a positive increasing integer build.')
    if args.platform == 'android' and not (ROOT / 'frontend/android/key.properties').is_file():
        parser.error('Configure the permanent release keystore in frontend/android/key.properties first. Debug APKs cannot be published.')
    commit = subprocess.check_output(['git', 'rev-parse', '--short=12', 'HEAD'], cwd=ROOT, text=True).strip()
    release_id = f'{args.platform}-{args.version.replace(".", "-")}-{args.build}-{commit}-{uuid4().hex[:8]}'
    output = ROOT / '.tmp/releases' / release_id
    output.mkdir(parents=True, exist_ok=False)
    command = flutter_command() + ['build', 'web' if args.platform == 'web' else 'apk', '--release',
        f'--build-name={args.version}', f'--build-number={args.build}',
        '--dart-define=DEFENSYS_API_SCHEME=https', '--dart-define=DEFENSYS_API_PORT=',
        f'--dart-define=DEFENSYS_RELEASE_ID={release_id}', f'--dart-define=DEFENSYS_RELEASE_VERSION={args.version}',
        f'--dart-define=DEFENSYS_RELEASE_BUILD={args.build}']
    command += [f'--dart-define=DEFENSYS_RELEASE_ORIGIN={args.origin.rstrip("/")}']
    if args.platform == 'web':
        command += ['--no-wasm-dry-run']
    else:
        command += [f'--dart-define=DEFENSYS_API_HOST={origin.netloc}', f'--dart-define=GUEST_PORTAL_URL={args.origin}']
    subprocess.run(command, cwd=ROOT / 'frontend', check=True)
    record = {'version': args.version, 'build': args.build, 'release_id': release_id,
              'published_at': datetime.now(timezone.utc).isoformat()}
    files = output / 'artifact'
    files.mkdir()
    if args.platform == 'web':
        shutil.copytree(ROOT / 'frontend/build/web', files, dirs_exist_ok=True)
        shutil.copyfile(ROOT / 'deployment/web/retire_flutter_service_worker.js', files / 'flutter_service_worker.js')
        bootstrap = files / 'flutter_bootstrap.js'
        text = bootstrap.read_text(encoding='utf-8')
        call = 'await _flutter.loader.load();'
        if call not in text:
            raise ValueError('Unexpected Flutter bootstrap; refusing unversioned release.')
        base = f'/releases/web/{release_id}/'
        bootstrap.write_text(text.replace(call, 'await _flutter.loader.load({config: ' +
            json.dumps({'entrypointBaseUrl': base, 'assetBase': base}) + '});'), encoding='utf-8')
        verify_web(files)
    else:
        apk = ROOT / 'frontend/build/app/outputs/flutter-apk/app-release.apk'
        # Android SDK tools must verify the real package; do not trust filenames.
        sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        if not sdk:
            local = ROOT / 'frontend/android/local.properties'
            match = re.search(r'^sdk.dir=(.+)$', local.read_text(), re.M) if local.exists() else None
            sdk = match[1].replace('\\\\', '\\').replace('\\:', ':') if match else ''
        tools = sorted((Path(sdk) / 'build-tools').glob('*')) if sdk else []
        if not tools:
            raise ValueError('Android build-tools are required to verify the release APK.')
        tool = tools[-1]
        aapt = tool / ('aapt.exe' if os.name == 'nt' else 'aapt')
        signer = tool / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
        identity = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], text=True)
        expected = f"package: name='{args.application_id}' versionCode='{args.build}' versionName='{args.version}'"
        if expected not in identity:
            raise ValueError('APK package/version does not match the release.')
        signing_env = os.environ.copy()
        if not signing_env.get('JAVA_HOME'):
            studio_java = Path('C:/Program Files/Android/Android Studio/jbr')
            if studio_java.is_dir():
                signing_env['JAVA_HOME'] = str(studio_java)
        certificate = subprocess.check_output([str(signer), 'verify', '--print-certs', str(apk)], text=True, env=signing_env)
        if 'android debug' in certificate.lower() or 'androiddebug' in certificate.lower():
            raise ValueError('Refusing to publish a debug-signed APK.')
        signer_hash = re.search(r'certificate SHA-256 digest: ([a-fA-F0-9]+)', certificate)
        if not signer_hash:
            raise ValueError('Could not verify the APK signing certificate.')
        name = f'DefenSYS-{args.version}-{args.build}.apk'
        shutil.copyfile(apk, files / name)
        record.update(available=True, application_id=args.application_id,
            signing_sha256=signer_hash[1].lower(),
            download_url=f'{args.origin.rstrip("/")}/releases/android/{name}',
            size_bytes=apk.stat().st_size, sha256=sha256(apk))
    (output / 'release.json').write_text(json.dumps({'schema_version': 1, 'platform': args.platform,
        'release': record, 'source_commit': commit}, indent=2), encoding='utf-8')
    inventory = {p.relative_to(files).as_posix(): sha256(p) for p in files.rglob('*') if p.is_file()}
    (output / 'checksums.json').write_text(json.dumps(inventory, indent=2), encoding='utf-8')
    archive = output / f'{release_id}.tar.gz'
    with tarfile.open(archive, 'w:gz') as bundle:
        for name in ('artifact', 'release.json', 'checksums.json'):
            bundle.add(output / name, arcname=name)
    print(json.dumps({'release_id': release_id, 'archive': str(archive), 'sha256': sha256(archive)}, indent=2))


if __name__ == '__main__':
    main()
