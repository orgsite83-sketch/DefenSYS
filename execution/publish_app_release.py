"""Verify/stage a prepared release; --apply atomically publishes its pointer.

Run on the Ubuntu server. Defaults to preview. Never touches Django/media/.env.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import tarfile
import tempfile
from contextlib import contextmanager
from urllib.parse import urlsplit
from prepare_app_release import sha256, verify_web


def read_bundle(archive, destination):
    with tarfile.open(archive) as bundle:
        if sum(m.size for m in bundle.getmembers()) > 3 * 1024 ** 3:
            raise ValueError('Release archive is too large.')
        for member in bundle.getmembers():
            path = Path(member.name)
            if (PurePosixPath(member.name).is_absolute() or PureWindowsPath(member.name).drive or
                    '\\' in member.name or '..' in path.parts or member.issym() or member.islnk() or member.isdev()):
                raise ValueError('Unsafe archive entry.')
        bundle.extractall(destination, filter='data')
    record = json.loads((destination / 'release.json').read_text())
    checksums = json.loads((destination / 'checksums.json').read_text())
    artifact = destination / 'artifact'
    actual = {p.relative_to(artifact).as_posix(): sha256(p) for p in artifact.rglob('*') if p.is_file()}
    if actual != checksums or not actual:
        raise ValueError('Release inventory/checksums do not match.')
    if any(Path(name).name.startswith('.env') or Path(name).name.lower() in {'key.properties', 'credentials.json', 'token.json'} or
           Path(name).suffix in {'.jks', '.keystore'} for name in actual):
        raise ValueError('Private configuration must not be published.')
    return record, artifact


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as handle:
        json.dump(data, handle, indent=2)
        handle.flush()
        os.fsync(handle.fileno())
        temporary = Path(handle.name)
    temporary.chmod(0o644)
    os.replace(temporary, path)


@contextmanager
def publication_lock(root):
    root = root.absolute()
    if root == Path(root.anchor) or root.resolve() != root:
        raise ValueError('Unsafe release storage path.')
    root.mkdir(parents=True, exist_ok=True)
    with (root / '.publish.lock').open('a+b') as handle:
        if os.name == 'nt':
            import msvcrt
            if handle.tell() == 0:
                handle.write(b'0')
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            if os.name == 'nt':
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def publish(record, artifact, root, web_root, apply=False, origin='https://defensys.site'):
    if not apply:
        return _publish(record, artifact, root, web_root, False, origin)
    with publication_lock(root):
        return _publish(record, artifact, root, web_root, True, origin)


def _publish(record, artifact, root, web_root, apply=False, origin='https://defensys.site'):
    channel, release = record.get('platform'), dict(record.get('release', {}))
    release_id = release.get('release_id', '')
    if channel not in {'web', 'android'} or record.get('schema_version') != 1 or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', release_id):
        raise ValueError('Invalid release record.')
    if type(release.get('build')) is not int or release['build'] < 1 or not re.fullmatch(r'\d+\.\d+\.\d+', release.get('version', '')):
        raise ValueError('Invalid release version/build.')
    root, web_root = root.absolute(), web_root.absolute()
    if root == Path(root.anchor) or web_root == Path(web_root.anchor) or root == web_root or root.is_relative_to(web_root) or web_root.is_relative_to(root):
        raise ValueError('Release storage and web root must be separate explicit directories.')
    if root.resolve() != root or web_root.parent.resolve() != web_root.parent:
        raise ValueError('Release parent directories must not use filesystem links.')
    latest_path = root / 'metadata/latest.json'
    latest = json.loads(latest_path.read_text()) if latest_path.exists() else {'schema_version': 1, 'android': {'available': False}}
    previous = latest.get(channel) or {}
    if release['build'] <= previous.get('build', 0):
        raise ValueError('Build number must exceed the last published build for this channel.')
    if channel == 'web':
        verify_web(artifact)
        bootstrap = (artifact / 'flutter_bootstrap.js').read_text()
        if f'/releases/web/{release_id}/' not in bootstrap:
            raise ValueError('Release asset base does not match its identity.')
        target = root / 'web' / release_id
        if web_root.is_symlink() and not web_root.resolve().is_relative_to(root / 'web'):
            raise ValueError('Existing web pointer is outside managed web releases.')
    else:
        url = urlsplit(release.get('download_url', ''))
        if url.scheme != 'https' or f'{url.scheme}://{url.netloc}' != origin or url.query or url.fragment or not re.fullmatch(r'/releases/android/[A-Za-z0-9._-]+\.apk', url.path):
            raise ValueError('APK URL must use this deployment release origin.')
        if release.get('application_id') != 'com.example.user' or release.get('available') is not True:
            raise ValueError('Unexpected Android package identity.')
        if not re.fullmatch(r'[a-f0-9]{64}', release.get('signing_sha256', '')):
            raise ValueError('Missing verified Android signing certificate.')
        name = Path(url.path).name
        apk = artifact / name
        if not apk.is_file() or sha256(apk) != release.get('sha256') or apk.stat().st_size != release.get('size_bytes'):
            raise ValueError('Published APK checksum/size mismatch.')
        if previous.get('signing_sha256') and previous['signing_sha256'] != release.get('signing_sha256'):
            raise ValueError('Android signing identity changed; review migration before publishing.')
        target = root / 'android' / name
    reuse = False
    if target.exists():
        if channel == 'web' and target.is_dir():
            existing = {p.relative_to(target).as_posix(): sha256(p) for p in target.rglob('*') if p.is_file()}
            incoming = {p.relative_to(artifact).as_posix(): sha256(p) for p in artifact.rglob('*') if p.is_file()}
            reuse = existing == incoming
        elif channel == 'android' and target.is_file():
            reuse = sha256(target) == release['sha256']
        if not reuse:
            raise FileExistsError(f'Refusing to replace an immutable release: {target}')
    report = {'platform': channel, 'release_id': release_id, 'target': str(target), 'apply': apply}
    if not apply:
        return report
    release['published_at'] = datetime.now(timezone.utc).isoformat()
    target.parent.mkdir(parents=True, exist_ok=True)
    if channel == 'web':
        if not reuse:
            shutil.copytree(artifact, target)
        for path in [target, *target.rglob('*')]:
            path.chmod(0o755 if path.is_dir() else 0o644)
        verify_web(target)
        # Keep an old directory on the initial migration and prior immutable
        # releases afterwards. Never recursively delete the current web root.
        old_link = os.readlink(web_root) if web_root.is_symlink() else None
        old_directory = None
        if web_root.exists() and not web_root.is_symlink():
            old_directory = web_root.with_name(web_root.name + '.before-releases-' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f'))
            web_root.rename(old_directory)
        temporary = web_root.with_name(web_root.name + '.next-' + release_id)
        try:
            temporary.symlink_to(target, target_is_directory=True)
            os.replace(temporary, web_root)
            latest[channel] = release
            atomic_json(latest_path, latest)
        except BaseException:
            temporary.unlink(missing_ok=True)
            if web_root.is_symlink():
                web_root.unlink()
            if old_link:
                web_root.symlink_to(old_link, target_is_directory=True)
            elif old_directory:
                old_directory.rename(web_root)
            raise
    else:
        if not reuse:
            shutil.copyfile(apk, target)
        target.chmod(0o644)
        latest[channel] = release
        atomic_json(latest_path, latest)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--sha256')
    parser.add_argument('--root', type=Path, default=Path('/var/www/defensys-releases'))
    parser.add_argument('--web-root', type=Path, default=Path('/var/www/defensys'))
    parser.add_argument('--origin', default='https://defensys.site')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.apply and (not args.sha256 or not re.fullmatch(r'[a-f0-9]{64}', args.sha256)):
        parser.error('--apply requires the SHA-256 printed during preparation.')
    if args.sha256 and sha256(args.archive) != args.sha256:
        raise ValueError('Archive SHA-256 does not match.')
    with tempfile.TemporaryDirectory(prefix='defensys-release-') as temporary:
        record, artifact = read_bundle(args.archive, Path(temporary))
        print(json.dumps(publish(record, artifact, args.root, args.web_root, args.apply, args.origin), indent=2))


if __name__ == '__main__':
    main()
