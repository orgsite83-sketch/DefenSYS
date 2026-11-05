"""Add test-only Nginx routes in challenge and HTTPS phases, with rollback.

Does not edit production virtual hosts, databases, or backend service state.
Run as defensys after sudo -v. Certificate issuance is a separate Certbot step.
"""
import argparse
import datetime
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request

AVAILABLE = Path('/etc/nginx/sites-available/defensys-testing.conf')
ENABLED = Path('/etc/nginx/sites-enabled/defensys-testing.conf')
ACME = '/var/www/defensys-testing-acme'
CERT = '/etc/letsencrypt/live/defensys-testing'
HOSTS = ('test.defensys.site', 'client-test.defensys.site')
MARKER = '# Managed DefenSYS testing routes; production is configured separately.\n'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def verify_acme_route(host, expected, *, attempts=12, delay=0.5, opener=None):
    # A reload returns before every new worker is accepting connections.
    # Probe the exact HTTP vhost without proxy variables or redirect following.
    opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(
        'http://127.0.0.1/.well-known/acme-challenge/defensys-route-check.txt',
        headers={'Host': host})
    error = 'no response'
    for attempt in range(attempts):
        try:
            with opener.open(request, timeout=2) as response:
                if response.status == 200 and response.read() == expected:
                    return
                error = 'unexpected status or body'
        except (urllib.error.URLError, OSError) as exc:
            error = str(exc)
        if attempt + 1 < attempts:
            time.sleep(delay)
    raise RuntimeError(f'ACME route failed for {host} after {attempts} attempts: {error}')


def challenge_config():
    return MARKER + f'''server {{
    listen 80;
    server_name {' '.join(HOSTS)};
    location ^~ /.well-known/acme-challenge/ {{
        root {ACME};
        default_type text/plain;
        try_files $uri =404;
    }}
    location / {{ return 503; }}
}}
'''


def https_config(releases_template, usertest_media_root=None):
    result = challenge_config().replace('location / { return 503; }',
                                        'location / { return 301 https://$host$request_uri; }')
    for name, host, port in (('usertest', HOSTS[0], 8100), ('clienttest', HOSTS[1], 8200)):
        protected = ''
        if name == 'usertest' and usertest_media_root is not None:
            root = str(usertest_media_root).rstrip('/')
            if not root.startswith('/') or any(char in root for char in ('"', "'", ';', '{', '}', '\n', '\r')):
                raise ValueError('Invalid protected media root')
            protected = f'''
    location ^~ /_protected_usertest_media/ {{
        internal;
        alias "{root}/";
        disable_symlinks on;
        max_ranges 1;
        add_header Cache-Control "private, no-store" always;
        add_header X-Content-Type-Options nosniff always;
    }}
'''
        release_root = '/var/www/defensys-' + name + '-releases'
        releases = releases_template.replace('/var/www/defensys-releases', release_root)
        # These locations carry the same cache/worker handling as production,
        # with environment-specific release storage.
        result += f'''
server {{
    listen 443 ssl;
    server_name {host};
    ssl_certificate {CERT}/fullchain.pem;
    ssl_certificate_key {CERT}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/defensys-{name};
    index index.html;
    client_max_body_size 500M;{protected}
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    {releases}
    location /api/ {{
        proxy_pass http://127.0.0.1:{port};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }}
    location /admin/ {{
        proxy_pass http://127.0.0.1:{port};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }}
    location /media/ {{
        proxy_pass http://127.0.0.1:{port};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }}
    location /static/ {{ alias /var/www/defensys-{name}-static/; }}
    location /ws/ {{
        proxy_pass http://127.0.0.1:{port + 1};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_buffering off;
    }}
    location / {{
        expires -1;
        try_files $uri $uri/ /index.html;
    }}
}}
'''
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('challenge', 'https'), required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--usertest-protected-media', action='store_true',
                        help='Opt in to internal-only Nginx media delivery for usertest; requires narrow read ACLs.')
    args = parser.parse_args()
    if os.name != 'posix' or os.getuid() == 0 or Path.home().name != 'defensys':
        parser.error('Run as the normal defensys SSH user, not root.')
    releases = Path('/opt/defensys/deployment/nginx/releases.conf').read_text()
    if '/var/www/defensys-releases/' not in releases:
        parser.error('Unexpected release routing template; inspect before continuing.')
    challenge = challenge_config()
    media_root = Path.home() / 'defensys-environments/usertest/backend/media'
    original_https = https_config(releases)
    protected_https = https_config(releases, media_root)
    https = protected_https if args.usertest_protected_media else original_https
    candidate = challenge if args.phase == 'challenge' else https
    if AVAILABLE.is_symlink():
        parser.error('Testing config must not be a symlink.')
    previous = AVAILABLE.read_text() if AVAILABLE.exists() else None
    if previous not in (None, challenge, original_https, protected_https):
        parser.error('Existing testing config differs; refusing to overwrite it.')
    if previous in (original_https, protected_https) and args.phase == 'challenge':
        parser.error('HTTPS is already configured; refusing to downgrade it.')
    if ENABLED.is_symlink():
        if ENABLED.resolve() != AVAILABLE:
            parser.error('Enabled testing symlink points elsewhere.')
    elif ENABLED.exists():
        parser.error('Enabled testing path is not the expected symlink.')

    def sudo(*command, **kwargs):
        return subprocess.run(['sudo', '-n', *command], check=True, **kwargs)

    snapshot = sudo('nginx', '-T', text=True, capture_output=True).stdout
    if previous is None:
        import re
        for names in re.findall(r'^\s*server_name\s+([^;]+);', snapshot, flags=re.M):
            if set(names.split()).intersection(HOSTS):
                parser.error('A test hostname already has a route elsewhere; inspect first.')
    if args.phase == 'https':
        if args.usertest_protected_media:
            if not media_root.is_dir() or media_root.is_symlink():
                parser.error('Expected the existing isolated usertest media directory.')
            sudo('runuser', '-u', 'www-data', '--', 'test', '-x', str(media_root))
            sample = next((path for path in media_root.rglob('*') if path.is_file()), None)
            if sample is not None:
                sudo('runuser', '-u', 'www-data', '--', 'test', '-r', str(sample))
        import re
        sans = sudo('openssl', 'x509', '-in', CERT + '/fullchain.pem', '-noout',
                    '-ext', 'subjectAltName', text=True, capture_output=True).stdout
        certificate_hosts = set(re.findall(r'DNS:([^,\s]+)', sans))
        if not set(HOSTS).issubset(certificate_hosts):
            parser.error('Testing certificate does not cover both exact testing hostnames.')
        for host in HOSTS:
            sudo('openssl', 'x509', '-in', CERT + '/fullchain.pem', '-noout', '-checkhost', host)
        sudo('openssl', 'x509', '-in', CERT + '/fullchain.pem', '-noout', '-checkend', '86400')
    print('Phase:', args.phase, '| Test hosts:', ', '.join(HOSTS), '| Apply:', args.apply, flush=True)
    if not args.apply:
        return
    os.umask(0o077)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    work = Path.home() / 'defensys-environments/nginx-operations' / stamp
    work.mkdir(parents=True, mode=0o700)
    (work / 'nginx-before.txt').write_text(snapshot)
    staged = work / AVAILABLE.name
    staged.write_text(candidate)
    old_file = work / 'previous-testing.conf'
    if previous is not None:
        old_file.write_text(previous)
    sudo('install', '-d', '-m', '0755', ACME + '/.well-known/acme-challenge')
    if args.phase == 'challenge':
        probe = work / 'route-check.txt'
        probe.write_text('defensys-testing-acme-ready\n')
        probe_path = ACME + '/.well-known/acme-challenge/defensys-route-check.txt'
        sudo('install', '-m', '0644', str(probe), probe_path)
    if args.phase == 'https':
        for name in ('usertest', 'clienttest'):
            for suffix in ('', '-releases', '-static'):
                sudo('install', '-d', '-m', '0755', '/var/www/defensys-' + name + suffix)
    was_linked = ENABLED.is_symlink()
    try:
        sudo('install', '-m', '0644', str(staged), str(AVAILABLE))
        if not was_linked:
            sudo('ln', '-s', str(AVAILABLE), str(ENABLED))
        sudo('nginx', '-t')
        sudo('systemctl', 'reload', 'nginx')
        if args.phase == 'challenge':
            for host in HOSTS:
                verify_acme_route(host, probe.read_bytes())
                print('ACME route verified:', host)
    except BaseException:
        if not was_linked and ENABLED.is_symlink():
            sudo('rm', '--', str(ENABLED))
        if previous is None:
            sudo('rm', '--', str(AVAILABLE))
        else:
            sudo('install', '-m', '0644', str(old_file), str(AVAILABLE))
        sudo('nginx', '-t')
        sudo('systemctl', 'reload', 'nginx')
        raise
    print('Test-only Nginx configuration loaded. Production virtual-host files were not edited.')
    print('Config snapshot:', work)


if __name__ == '__main__':
    main()
