"""Read-only HTTPS checks after publishing a web release. Never accesses Django."""
import argparse
import json
from pathlib import Path
import re
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]


def fetch(origin, path):
    separator = '&' if '?' in path else '?'
    request = Request(origin + path + separator + f'check={time.time_ns()}',
                      headers={'Cache-Control': 'no-cache, no-store'})
    with urlopen(request, timeout=20) as response:
        body = response.read(1024 * 1024 + 1)
        if len(body) > 1024 * 1024:
            raise ValueError(f'{path}: response exceeds the verification limit.')
        return body, response.headers


def verify(origin, expected_release=None):
    parsed = urlsplit(origin)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or
            parsed.password or parsed.path not in ('', '/') or parsed.query or parsed.fragment):
        raise ValueError('Use the public HTTPS origin without a path or credentials.')
    origin = origin.rstrip('/')

    def startup(path, content_type):
        body, headers = fetch(origin, path)
        if content_type not in headers.get('Content-Type', '').lower():
            raise ValueError(f'{path}: expected {content_type}; check the Nginx release include (SPA HTML fallback is not release metadata).')
        if 'no-store' not in headers.get('Cache-Control', '').lower():
            raise ValueError(f'{path}: missing Cache-Control: no-store; reload the Nginx release configuration.')
        return body

    metadata = json.loads(startup('/releases/latest.json', 'application/json'))
    web = metadata.get('web') if isinstance(metadata, dict) else None
    if not isinstance(metadata, dict) or metadata.get('schema_version') != 1 or not isinstance(web, dict):
        raise ValueError('No published web release in latest.json.')
    release_id = web.get('release_id', '')
    if (not isinstance(release_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', release_id)
            or type(web.get('build')) is not int or web['build'] < 1):
        raise ValueError('Invalid published web identity.')
    if expected_release and release_id != expected_release:
        raise ValueError(f'Expected {expected_release}, but the server advertises {release_id}.')
    index = startup('/index.html', 'text/html').decode('utf-8')
    if "searchParams.set('startup'," not in index:
        raise ValueError('The deployed index cannot bypass the cached legacy bootstrap.')
    worker = startup('/flutter_service_worker.js', 'javascript').decode('utf-8')
    expected_worker = (ROOT / 'deployment/web/retire_flutter_service_worker.js').read_text(encoding='utf-8')
    if worker.replace('\r\n', '\n') != expected_worker.replace('\r\n', '\n'):
        raise ValueError('The server still serves a generated or unexpected service worker.')
    bootstrap = startup('/flutter_bootstrap.js', 'javascript').decode('utf-8')
    base = f'/releases/web/{release_id}/'
    if base not in bootstrap:
        raise ValueError('The active bootstrap does not match the advertised web release.')
    # Check the immutable bootstrap as well, without downloading a large bundle.
    versioned, headers = fetch(origin, base + 'flutter_bootstrap.js')
    if versioned.decode('utf-8') != bootstrap or 'immutable' not in headers.get('Cache-Control', ''):
        raise ValueError('Versioned release routing or its immutable cache policy is incorrect.')
    return {'origin': origin, 'release_id': release_id, 'build': web['build'], 'verified': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--origin', default='https://defensys.site')
    parser.add_argument('--release-id')
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.origin, args.release_id), indent=2))
    except Exception as error:
        parser.exit(1, f'Web release verification failed: {error}\n')


if __name__ == '__main__':
    main()
