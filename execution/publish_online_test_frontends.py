"""Verify/publish a prepared pair of test frontends; production paths are refused.

Run on the server as defensys after sudo -v. Does not switch backend services.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import tempfile

ENVIRONMENTS = {'usertest': 'https://test.defensys.site',
                'clienttest': 'https://client-test.defensys.site'}


def checksum(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def target_paths(environment):
    if environment not in ENVIRONMENTS:
        raise ValueError('Only usertest/clienttest publication is allowed.')
    web = Path('/var/www/defensys-' + environment)
    return web, Path(str(web) + '-releases'), Path(str(web) + '-static')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if os.name != 'posix' or os.getuid() == 0 or Path.home().name != 'defensys':
        parser.error('Run as the normal defensys SSH user, not root.')
    bundle_path = args.bundle.expanduser().resolve(strict=True)
    if checksum(bundle_path) != args.sha256.lower():
        parser.error('Delivery checksum mismatch.')
    transfer = Path.home() / 'defensys-transfer'
    with tempfile.TemporaryDirectory(prefix='frontend-delivery-', dir=transfer) as temp:
        delivery = Path(temp)
        with tarfile.open(bundle_path) as archive:
            members = archive.getmembers()
            if sum(m.size for m in members) > 2 * 1024 ** 3:
                parser.error('Delivery is unexpectedly large.')
            for member in members:
                path = PurePosixPath(member.name)
                if (path.is_absolute() or '..' in path.parts or '\\' in member.name
                        or not (member.isfile() or member.isdir())):
                    parser.error('Unsafe delivery archive member.')
            archive.extractall(delivery, filter='data')
        record = json.loads((delivery / 'delivery.json').read_text())
        if set(record['releases']) != set(ENVIRONMENTS):
            parser.error('Delivery must contain exactly the two testing environments.')
        for name, expected in record['checksums'].items():
            path = (delivery / name).resolve()
            if not path.is_relative_to(delivery) or checksum(path) != expected:
                parser.error('Delivery inventory checksum mismatch: ' + name)
        publisher = delivery / 'execution/publish_app_release.py'
        verifier = delivery / 'execution/verify_web_release.py'
        for environment, origin in ENVIRONMENTS.items():
            release = record['releases'][environment]
            if release['origin'] != origin or Path(release['archive']).name != release['archive']:
                parser.error('Invalid per-environment release mapping.')
            artifact = delivery / 'artifacts' / release['archive']
            if checksum(artifact) != release['sha256']:
                parser.error('Release checksum mismatch: ' + environment)
            web, releases, public_static = target_paths(environment)
            if releases.is_symlink() or public_static.is_symlink():
                parser.error('Test release/static directory must not be a symlink.')
            command = [sys.executable, str(publisher), str(artifact), '--sha256', release['sha256'],
                       '--root', str(releases), '--web-root', str(web), '--origin', origin]
            latest = releases / 'metadata/latest.json'
            already = False
            if latest.exists():
                already = json.loads(latest.read_text()).get('web', {}).get('release_id') == release['release_id']
            if not already:
                subprocess.run(command, check=True)
            print(f'{environment}: verified release mapping; apply={args.apply}', flush=True)
            if not args.apply:
                continue
            if not already:
                subprocess.run(['sudo', '-n', *command, '--apply'], check=True)
            # Collect only this environment's admin static assets, as its user.
            checkout = Path.home() / 'defensys-environments' / environment
            backend = checkout / 'backend'
            from dotenv import dotenv_values
            config = dict(dotenv_values(backend / '.env'))
            if config.get('POSTGRES_DB') != 'defensys_' + environment:
                parser.error('Unexpected environment config during static collection.')
            child_env = {key: value for key, value in os.environ.items()
                         if not key.startswith(('POSTGRES_', 'DJANGO_', 'EMAIL_', 'SMS_', 'JWT_',
                                                'TWILIO_', 'SEMAPHORE_', 'DEFENSYS_'))
                         and key not in ('REDIS_URL', 'SECRET_KEY', 'SENTRY_DSN', 'FRONTEND_URL')}
            child_env.update(config)
            subprocess.run([sys.executable, str(backend / 'manage.py'), 'collectstatic', '--noinput',
                            '--settings=defensys_backend.settings_online_' + environment],
                           cwd=backend, env=child_env, check=True)
            static = backend / 'staticfiles'
            if any(path.is_symlink() for path in static.rglob('*')):
                parser.error('Linked static assets are not supported.')
            subprocess.run(['sudo', '-n', 'install', '-d', '-m', '0755', str(public_static)], check=True)
            subprocess.run(['sudo', '-n', 'cp', '-a', str(static) + '/.', str(public_static)], check=True)
            subprocess.run(['sudo', '-n', 'chmod', '-R', 'u=rwX,go=rX', str(public_static)], check=True)
            subprocess.run([sys.executable, str(verifier), '--origin', origin,
                            '--release-id', release['release_id']], check=True)
        print('Test frontend operation complete. Production release paths and backend states were not changed.')


if __name__ == '__main__':
    main()
