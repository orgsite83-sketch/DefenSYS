# DefenSYS — Kamatera deployment guide

End-to-end guide: create a Kamatera VPS → deploy this repository → serve over HTTPS → go live.

**Related docs:** [DEPLOYMENT.md](DEPLOYMENT.md) (go-live checklist) · [DEMO_SETUP_GUIDE.md](DEMO_SETUP_GUIDE.md) (local dev only) · [UPDATE_GUIDE.md](UPDATE_GUIDE.md) (commands when you change backend / web / mobile)

**Stack on one VM:** Ubuntu · PostgreSQL · Gunicorn (Django) · nginx (TLS + Flutter web static files)

**Rebuild after terminating a paid VPS:** [KAMATERA_REBUILD_RUNBOOK.md](KAMATERA_REBUILD_RUNBOOK.md) - backup checklist, terminate safely, restore DefenSYS on a fresh server.

---

## Table of contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Create the Kamatera server](#3-create-the-kamatera-server)
4. [First login and firewall](#4-first-login-and-firewall)
5. [Install system packages](#5-install-system-packages)
6. [PostgreSQL setup](#6-postgresql-setup)
7. [Deploy the backend](#7-deploy-the-backend)
8. [Gunicorn (systemd)](#8-gunicorn-systemd)
9. [Build and deploy Flutter web](#9-build-and-deploy-flutter-web)
10. [nginx configuration](#10-nginx-configuration)
11. [HTTPS (Let’s Encrypt)](#11-https-lets-encrypt)
12. [DNS — make the server official](#12-dns--make-the-server-official)
13. [Mobile apps (optional)](#13-mobile-apps-optional)
14. [Go-live verification](#14-go-live-verification)
15. [Backups and maintenance](#15-backups-and-maintenance)
16. [Troubleshooting](#16-troubleshooting)
17. [Appendix A — Flutter HTTPS / same-origin fix](#appendix-a--flutter-https--same-origin-fix)

---

## 1. Overview

```text
Internet
   │
   ▼
[Kamatera VM — public IP]
   │
   ├─ nginx :443 (TLS)
   │     ├─ /          → /var/www/defensys/     (Flutter web)
   │     ├─ /api/      → Gunicorn 127.0.0.1:8000
   │     └─ /admin/    → Gunicorn
   │
   ├─ Gunicorn → Django (backend/)
   ├─ PostgreSQL (localhost only)
   └─ /opt/defensys/backend/media/  (uploads; or S3 later)
```

**Why same-origin?** With `DJANGO_DEBUG=False`, CORS is only enabled for local/LAN origins in dev. Serving Flutter and the API under **one domain** (`https://yourdomain.edu/`) avoids cross-origin issues.

**Do not use** Kamatera’s prebuilt **Django + MySQL** or **LEMP** images. DefenSYS requires **PostgreSQL**.

---

## 2. Prerequisites

| Item | Notes |
|------|--------|
| Kamatera account | [kamatera.com](https://www.kamatera.com/) |
| Domain name (recommended) | e.g. `defensys.yourschool.edu` — A record points to Kamatera IP |
| Git access to this repo | SSH key or HTTPS clone URL |
| Your PC | Flutter SDK (to build web/APK), SSH client |
| Secrets | New `DJANGO_SECRET_KEY`, DB password, admin password — **never** commit `.env` |

**Before go-live on the server**, run on your PC (from a dev clone):

```bash
cd backend && python manage.py check --deploy
cd backend && python manage.py test
cd frontend && flutter test
```

---

## 3. Create the Kamatera server

1. Log in to the Kamatera console → **My Cloud** → **Create New Service**.
2. **Type:** Server (not load balancer).
3. **Image:** **Ubuntu 22.04 LTS** (plain server — **not** Django/MySQL marketplace).
4. **Specs (minimum):**
   - CPU: **2 vCPU**
   - RAM: **4 GB**
   - Disk: **40–60 GB** SSD
5. **Networking:** **Public Internet** (required for HTTPS and mobile clients).
6. **Region:** Closest to your users (e.g. Singapore / Hong Kong for lower latency in SEA).
7. **SSH key:** Add your public key (recommended) or note the root password.
8. Create the server and copy the **public IP** (e.g. `203.0.113.50`).

**Optional:** Kamatera firewall — allow inbound **22**, **80**, **443** only.

---

## 4. First login and firewall

From your PC:

```bash
ssh root@203.0.113.50
```

Replace the IP with your Kamatera public IP.

### Create a deploy user (recommended)

```bash
adduser defensys
usermod -aG sudo defensys
rsync --archive --chown=defensys:defensys ~/.ssh /home/defensys/
```

Log in as `defensys` for the rest of the guide:

```bash
ssh defensys@203.0.113.50
```

### Firewall (UFW)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

PostgreSQL must **not** be exposed publicly — keep it on `localhost` only.

---

## 5. Install system packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git nginx postgresql postgresql-contrib certbot python3-certbot-nginx redis-server
```

### Python 3.12+

DefenSYS requires **Python 3.12+** (see `backend/requirements.txt`).

**Ubuntu 22.04** (add deadsnakes PPA):

```bash
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3.12-dev build-essential libpq-dev
```

**Ubuntu 24.04** (if available on Kamatera): `python3.12` may be available directly via `apt install python3.12`.

Verify:

```bash
python3.12 --version
```

---

## 6. PostgreSQL setup

```bash
sudo -u postgres psql
```

In the `psql` shell (change passwords):

```sql
CREATE USER defensys WITH PASSWORD 'REPLACE_WITH_STRONG_DB_PASSWORD';
CREATE DATABASE defensys_db OWNER defensys;
\q
```

Test connection:

```bash
psql -h localhost -U defensys -d defensys_db -c 'SELECT 1;'
```

---

## 7. Deploy the backend

### Clone the repository

```bash
sudo mkdir -p /opt/defensys
sudo chown defensys:defensys /opt/defensys
cd /opt/defensys
git clone https://github.com/YOUR_ORG/DefenSYS.git .
# Or: git clone git@github.com:YOUR_ORG/DefenSYS.git .
```

### Python virtual environment

```bash
cd /opt/defensys/backend
python3.12 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn
```

### Production `.env`

```bash
cp .env.production.example .env
chmod 600 .env
nano .env
```

The repo includes [`backend/.env.production.example`](../backend/.env.production.example) with documentation-safe placeholder values. Replace `203.0.113.50` with your Kamatera public IP, and add your domain when DNS is ready.

Example production values (edit domain and IP):

```env
DJANGO_SECRET_KEY="paste-a-long-random-string-here"
DJANGO_DEBUG=False
DJANGO_ALLOWED_HOSTS=defensys.yourdomain.edu,203.0.113.50

POSTGRES_DB=defensys_db
POSTGRES_USER=defensys
POSTGRES_PASSWORD="REPLACE_WITH_STRONG_DB_PASSWORD"
POSTGRES_HOST=localhost
POSTGRES_PORT=5432

USE_S3=False
```

Generate a secret key on the server:

```bash
python3.12 -c "import secrets; print(secrets.token_urlsafe(50))"
```

### Migrate and create admin

```bash
cd /opt/defensys/backend
source venv/bin/activate
python manage.py check --deploy
python manage.py migrate
```

Create the bootstrap admin (from [DEPLOYMENT.md](DEPLOYMENT.md)):

```bash
export DJANGO_SUPERUSER_USERNAME=admin
export DJANGO_SUPERUSER_EMAIL=admin@yourdomain.edu
export DJANGO_SUPERUSER_PASSWORD='REPLACE_WITH_STRONG_ADMIN_PASSWORD'
python manage.py create_admin
```

Or: `python manage.py createsuperuser`

### Media directory

```bash
mkdir -p /opt/defensys/backend/media
chown -R defensys:defensys /opt/defensys/backend/media
```

---

## 8. Gunicorn (systemd)

Create a systemd unit:

```bash
sudo nano /etc/systemd/system/defensys.service
```

Paste (adjust `User` if needed):

```ini
[Unit]
Description=DefenSYS Gunicorn
After=network.target postgresql.service

[Service]
User=defensys
Group=defensys
WorkingDirectory=/opt/defensys/backend
Environment="PATH=/opt/defensys/backend/venv/bin"
ExecStart=/opt/defensys/backend/venv/bin/gunicorn \
    --workers 3 \
    --bind 127.0.0.1:8000 \
    --timeout 120 \
    defensys_backend.wsgi:application
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable defensys
sudo systemctl start defensys
sudo systemctl status defensys
```

Quick API test (on the server):

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/api/login/
# Expect 405 (Method Not Allowed) for GET — means Gunicorn + Django are up
```

---

## 8b. Redis + WebSocket (real-time grading flags)

Students receive live updates when admins enable peer evaluation (no re-login). This uses **Django Channels** on a separate ASGI process.

### Redis

```bash
sudo systemctl enable redis-server
sudo systemctl start redis-server
```

Add to `/opt/defensys/backend/.env`:

```env
REDIS_URL=redis://127.0.0.1:6379/0
```

Local dev without Redis: `DEFENSYS_USE_INMEMORY_CHANNELS=1` in `.env` (single-process only).

### Daphne (WebSocket ASGI)

```bash
sudo nano /etc/systemd/system/defensys-ws.service
```

```ini
[Unit]
Description=DefenSYS WebSocket (Daphne)
After=network.target redis-server.service

[Service]
User=defensys
Group=defensys
WorkingDirectory=/opt/defensys/backend
Environment="PATH=/opt/defensys/backend/venv/bin"
EnvironmentFile=/opt/defensys/backend/.env
ExecStart=/opt/defensys/backend/venv/bin/daphne \
    -b 127.0.0.1 -p 8001 defensys_backend.asgi:application
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable defensys-ws
sudo systemctl start defensys-ws
```

After `pip install -r requirements.txt`, ensure `channels`, `channels-redis`, and `daphne` are installed in the venv.

---

## 9. Build and deploy Flutter web

Build on **your PC** (not required on the VPS).

### Required: HTTPS / same-origin fix

The stock `frontend/lib/config/api_config.dart` uses `http://` and port `:8000`. Behind nginx on **443**, the web app must call `https://yourdomain.edu/api/` **without** port 8000.

### Build

```bash
cd frontend
flutter pub get
flutter build web --release
```

Served from a **public IP or domain** (Kamatera), the build uses same-origin URLs (`http://YOUR_IP/api`, no `:8000`) automatically.

For **HTTPS** after Certbot, rebuild (scheme follows the page) or pass:

```bash
flutter build web --release \
  --dart-define=DEFENSYS_API_HOST=defensys.yourdomain.edu \
  --dart-define=DEFENSYS_API_SCHEME=https \
  --dart-define=DEFENSYS_API_PORT=
```

### Upload to the server

On the server:

```bash
sudo mkdir -p /var/www/defensys
sudo chown defensys:defensys /var/www/defensys
```

From your PC:

```bash
scp -r frontend/build/web/* defensys@203.0.113.50:/var/www/defensys/
```

---

## 10. nginx configuration

Create the site config:

```bash
sudo nano /etc/nginx/sites-available/defensys
```

Paste (replace `defensys.yourdomain.edu`):

```nginx
server {
    listen 80;
    server_name defensys.yourdomain.edu;

    # Flutter web (static)
    root /var/www/defensys;
    index index.html;

    # Django API + admin
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 100M;
    }

    location /admin/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket: live grading flags (Daphne on 8001)
    location /ws/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_buffering off;
    }

    # SPA: send unknown paths to index.html (Flutter web routing)
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Enable and test:

```bash
sudo ln -sf /etc/nginx/sites-available/defensys /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

At this point (HTTP only), you can test: `http://203.0.113.50/` or `http://defensys.yourdomain.edu/` if DNS is already set.

---

## 11. HTTPS (Let’s Encrypt)

**DNS must point to this server** before Certbot can validate (see next section).

```bash
sudo certbot --nginx -d defensys.yourdomain.edu
```

Follow prompts (email, agree to terms). Certbot updates nginx for TLS and sets up auto-renewal.

Verify renewal timer:

```bash
sudo systemctl status certbot.timer
```

Test HTTPS in a browser: `https://defensys.yourdomain.edu/`

---

## 12. DNS — make the server official

At your domain registrar or school DNS panel:

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | `defensys` (or `@`) | `203.0.113.50` (Kamatera public IP) | 300–3600 |

Wait for propagation (minutes to hours). Check:

```bash
dig +short defensys.yourdomain.edu
```

When the A record resolves to your Kamatera IP, run Certbot (§11) if you have not already.

**Official URL:** `https://defensys.yourdomain.edu/`

Share this URL with admins and faculty for the web app.

---

## 13. Mobile apps (optional)

Physical phones must reach the Kamatera host over the internet.

1. Apply **Appendix A** (HTTPS + port).
2. Build APK on your PC:

```bash
cd frontend
flutter build apk --release \
  --dart-define=DEFENSYS_API_HOST=defensys.yourdomain.edu \
  --dart-define=DEFENSYS_API_SCHEME=https \
  --dart-define=DEFENSYS_API_PORT=
```

3. Distribute the APK securely (school portal, MDM, etc.).

**Note:** `DEFENSYS_API_HOST` must be the public hostname, not `127.0.0.1`.

---

## 14. Go-live verification

Use the checklist from [DEPLOYMENT.md](DEPLOYMENT.md):

- [ ] Login as admin at `https://defensys.yourdomain.edu/`
- [ ] `DJANGO_DEBUG=False` in `.env`
- [ ] `python manage.py check --deploy` passes on server
- [ ] Create a test user; confirm role-appropriate access
- [ ] Upload a document / deliverable; download via authenticated media URL
- [ ] Panelist flow: guest code or panelist login (mobile)
- [ ] Student peer evaluation (mobile)
- [ ] No prototype endpoints (`demo-fill`, `seed-demo`) — they are removed from production builds
- [ ] Secrets were **new** for production (not copied from dev `.env`)

### Do not run in production

- `python manage.py dev_create_40_students`
- Scripts under `backend/tests/` or `backend/scripts/` (unless you know what they do)
- `python manage.py runserver` (use Gunicorn only)

---

## 15. Backups and maintenance

### Kamatera snapshots

In the Kamatera console, schedule **periodic snapshots** of the VM for quick full-disk restore.

### PostgreSQL backup (daily cron example)

```bash
sudo mkdir -p /var/backups/defensys
sudo chown defensys:defensys /var/backups/defensys
crontab -e
```

Add:

```cron
0 2 * * * pg_dump -h localhost -U defensys defensys_db | gzip > /var/backups/defensys/db_$(date +\%F).sql.gz
```

### Media files

Back up `/opt/defensys/backend/media/` regularly, or set `USE_S3=true` in `.env` for durable object storage.

### Deploy updates

If `/opt/defensys` is **not** a git repo (`fatal: not a git repository`), update code with `rsync` — see [§16 Troubleshooting](#16-troubleshooting).

```bash
cd /tmp && rm -rf DefenSYS && git clone https://github.com/YOUR_ORG/DefenSYS.git
cp -a /opt/defensys/backend/media /tmp/defensys-media-backup
cp -a /opt/defensys/backend/.env /tmp/defensys-env-backup 2>/dev/null || true
rsync -av --exclude media --exclude venv /tmp/DefenSYS/backend/ /opt/defensys/backend/
rsync -av /tmp/defensys-media-backup/ /opt/defensys/backend/media/
cp -a /tmp/defensys-env-backup /opt/defensys/backend/.env 2>/dev/null || true
cd /opt/defensys/backend && source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate --noinput
sudo systemctl restart defensys
# Rebuild Flutter web on PC, scp to /var/www/defensys/
```

If `/opt/defensys` **is** a git clone:

```bash
cd /opt/defensys
git pull
cd backend && source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate --noinput
sudo systemctl restart defensys
# Rebuild Flutter web on PC, scp to /var/www/defensys/
```

---

## 16. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| 502 Bad Gateway | Gunicorn not running | `sudo systemctl status defensys` · check logs: `journalctl -u defensys -n 50` |
| **`journalctl -u gunicorn` shows no entries** | Wrong unit name | Use **`defensys`**, not `gunicorn`: `journalctl -u defensys -n 100` |
| Upload / API **500** · `No module named 'defensys_backend.exception_handlers'` | Incomplete backend deploy | Ensure full tree under `/opt/defensys/backend/` including `defensys_backend/exception_handlers.py` (see rsync update above) |
| **`Missing DJANGO_SECRET_KEY`** on `manage.py` / 500 | No `.env` | `cp .env.production.example .env`, set secrets, `chmod 600 .env`, restart `defensys` |
| `/opt/defensys/backend/` only has `media/` | Code never copied | `rsync` from git clone; do not `git clone` into non-empty dir without backup |
| 400 Bad Request (DisallowedHost) | Host not in `DJANGO_ALLOWED_HOSTS` | Add domain + IP to `.env`, restart Gunicorn |
| Web loads but API fails (mixed content / wrong port) | `api_config.dart` still uses `http://:8000` | Apply Appendix A; rebuild and re-upload web |
| CORS errors in browser | Cross-origin API URL | Use same-origin nginx (`/` + `/api/` on one domain) |
| Certbot fails | DNS not pointing to server | Fix A record, wait, retry `certbot` |
| Upload fails | Body size limit | Increase `client_max_body_size` in nginx `location /api/` |
| DB connection refused | Postgres down or wrong `.env` | `sudo systemctl status postgresql` · verify `POSTGRES_*` |

### Required files checklist (after deploy)

```bash
ls -la /opt/defensys/backend/manage.py
ls -la /opt/defensys/backend/defensys_backend/exception_handlers.py
ls -la /opt/defensys/backend/.env
ls -la /opt/defensys/backend/venv/bin/gunicorn
sudo systemctl status defensys
```

---

## Appendix A — Flutter HTTPS / same-origin fix

**Implemented in** [`frontend/lib/config/api_config.dart`](../frontend/lib/config/api_config.dart).

Production web on a **public host** (e.g. `http://203.0.113.50/`) automatically uses **`http://203.0.113.50/api`** (no `:8000`). Local dev on `localhost` still uses **`:8000`**.

### 1. Add dart-define keys in `frontend/lib/config/api_config.dart`

After existing `dartDefineApiHost`, add:

```dart
static const String dartDefineApiScheme =
    String.fromEnvironment('DEFENSYS_API_SCHEME', defaultValue: '');

static const String dartDefineApiPort =
    String.fromEnvironment('DEFENSYS_API_PORT', defaultValue: '8000');
```

### 2. Add helpers and update URL getters

```dart
static String get _scheme {
  if (dartDefineApiScheme.isNotEmpty) return dartDefineApiScheme;
  if (kIsWeb) {
    final pageScheme = Uri.base.scheme;
    if (pageScheme == 'https') return 'https';
  }
  return 'http';
}

static String get _portSuffix {
  final port = dartDefineApiPort;
  if (port.isEmpty) return '';
  if (_scheme == 'https' && port == '443') return '';
  if (_scheme == 'http' && port == '80') return '';
  return ':$port';
}

static String get baseUrl => '$_scheme://$baseIp$_portSuffix/api';

static String get mediaUrl => '$_scheme://$baseIp$_portSuffix';
```

### 3. Build commands (after the change)

**Web** (same domain as API — recommended):

```bash
flutter build web --release
# Uses Uri.base host + https when served from https://yourdomain.edu/
```

**Web** (explicit host):

```bash
flutter build web --release \
  --dart-define=DEFENSYS_API_HOST=defensys.yourdomain.edu \
  --dart-define=DEFENSYS_API_SCHEME=https \
  --dart-define=DEFENSYS_API_PORT=
```

**Mobile:**

```bash
flutter build apk --release \
  --dart-define=DEFENSYS_API_HOST=defensys.yourdomain.edu \
  --dart-define=DEFENSYS_API_SCHEME=https \
  --dart-define=DEFENSYS_API_PORT=
```

After changing `api_config.dart`, rebuild and re-upload `build/web` to the server.

---

*Last updated: 2026-05-24*
