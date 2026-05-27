# DefenSYS Deployment Guide

> Server: `79.108.225.153` | User: `defensys` | Nginx: `dev.defensys.site`

---

## Table of Contents

- [1. Backup Only](#1-backup-only)
- [2. Backend Changes](#2-backend-changes)
- [3. Web (Flutter) Changes](#3-web-flutter-changes)
- [4. Android App Changes](#4-android-app-changes)
- [5. Full Deploy (All)](#5-full-deploy-all)

---

## 1. Backup Only

SSH into the server and create backups of the database and media files.

```bash
ssh defensys@79.108.225.153

# Create backup directory (first time only)
mkdir -p ~/deploy-backups

# Backup database
pg_dump -h localhost -U defensys defensys_db | gzip > ~/deploy-backups/db_$(date +%F_%H%M).sql.gz

# Backup media files
cp -a /opt/defensys/backend/media ~/deploy-backups/media_$(date +%F_%H%M)
```

### Verify backups

```bash
ls -lh ~/deploy-backups/
```

### Restore database (if needed)

```bash
gunzip -c ~/deploy-backups/db_YYYY-MM-DD_HHMM.sql.gz | psql -h localhost -U defensys defensys_db
```

---

## 2. Backend Changes

### Prerequisites

- Backup completed (see [Section 1](#1-backup-only))
- Changes pushed to the remote Git repository

### Steps (run on server)

```bash
ssh defensys@79.108.225.153

# 1. Pull latest code
cd /opt/defensys
git pull

# 2. Activate virtual environment & install deps
cd backend
source venv/bin/activate
pip install -r requirements.txt

# 3. Validate deployment settings
python manage.py check --deploy

# 4. Run migrations
python manage.py migrate --noinput

# 5. Collect static files (if any admin/static changes)
python manage.py collectstatic --noinput

# 6. Restart backend services
sudo systemctl restart defensys
# If using Daphne for WebSocket:
sudo systemctl restart defensys-ws
```

### Verify

```bash
# Check service status
sudo systemctl status defensys

# Check API health
curl -I https://dev.defensys.site/api/

# Check logs for errors
sudo journalctl -u defensys --since "5 minutes ago" --no-pager
```

---

## 3. Web (Flutter) Changes

### Prerequisites

- Flutter SDK installed locally
- Changes committed and ready

### Steps

#### Build locally (PowerShell)

```powershell
cd C:\Users\Admin\Desktop\DefenSYS\frontend
flutter build web --release
```

#### Deploy to server (PowerShell)

```powershell
scp -r build/web/* defensys@79.108.225.153:/var/www/defensys/
```

#### Fix permissions (run on server)

```bash
ssh defensys@79.108.225.153
sudo chmod -R 755 /var/www/defensys/
```

> **Why?** `scp` from Windows creates directories with `700` permissions, blocking Nginx (`www-data`) from reading them. Always run `chmod` after uploading.

#### One-liner deploy (PowerShell)

```powershell
flutter build web --release; scp -r build/web/* defensys@79.108.225.153:/var/www/defensys/; ssh defensys@79.108.225.153 "sudo chmod -R 755 /var/www/defensys/"
```

### Verify

```powershell
curl.exe -I https://dev.defensys.site/assets/FontManifest.json
# Should return: HTTP/1.1 200 OK
```

### Clear browser cache

Flutter service workers cache aggressively. After deploying, tell users to **hard refresh** (`Ctrl+Shift+R`) or clear site data in the browser.

---

## 4. Android App Changes

### Prerequisites

- Flutter SDK installed locally
- Android signing keystore configured

### Build APK

```powershell
cd C:\Users\Admin\Desktop\DefenSYS\frontend
flutter build apk --release
```

Output: `build\app\outputs\flutter-apk\app-release.apk`

### Build App Bundle (for Play Store)

```powershell
flutter build appbundle --release
```

Output: `build\app\outputs\bundle\release\app-release.aab`

### Distribute

- **Internal testing**: Share the APK directly
- **Play Store**: Upload the `.aab` to Google Play Console

---

## 5. Full Deploy (All)

Run everything in order. Start with backup, then backend, then web.

### On server

```bash
ssh defensys@79.108.225.153

# ── BACKUP ──
mkdir -p ~/deploy-backups
pg_dump -h localhost -U defensys defensys_db | gzip > ~/deploy-backups/db_$(date +%F_%H%M).sql.gz
cp -a /opt/defensys/backend/media ~/deploy-backups/media_$(date +%F_%H%M)

# ── BACKEND ──
cd /opt/defensys
git pull
cd backend
source venv/bin/activate
pip install -r requirements.txt
python manage.py check --deploy
python manage.py migrate --noinput
python manage.py collectstatic --noinput
sudo systemctl restart defensys
sudo systemctl restart defensys-ws
```

### On local machine (PowerShell)

```powershell
# ── WEB ──
cd C:\Users\Admin\Desktop\DefenSYS\frontend
flutter build web --release
scp -r build/web/* defensys@79.108.225.153:/var/www/defensys/
ssh defensys@79.108.225.153 "sudo chmod -R 755 /var/www/defensys/"
```

### Final verification

```powershell
# Web
curl.exe -I https://dev.defensys.site/assets/FontManifest.json

# API
curl.exe -I https://dev.defensys.site/api/
```

---

## Server Reference

| Item               | Value                                              |
| ------------------ | -------------------------------------------------- |
| Server IP          | `79.108.225.153`                                   |
| SSH User           | `defensys`                                         |
| Domain             | `dev.defensys.site`                                |
| Web root           | `/var/www/defensys/`                               |
| Backend root       | `/opt/defensys/backend/`                            |
| Nginx config       | `/etc/nginx/sites-available/defensys`              |
| SSL certs          | `/etc/letsencrypt/live/dev.defensys.site/`         |
| Backups            | `~/deploy-backups/`                                |
| DB name            | `defensys_db`                                      |

---

## Troubleshooting

| Problem | Cause | Fix |
| ------- | ----- | --- |
| `404` on assets after deploy | Directory permissions `700` | `sudo chmod -R 755 /var/www/defensys/` |
| Old web version showing | Service worker cache | Hard refresh `Ctrl+Shift+R` or clear site data |
| `502 Bad Gateway` | Gunicorn not running | `sudo systemctl restart defensys` |
| Migration errors | Conflicting migrations | Check `python manage.py showmigrations` |
| PowerShell `curl` prompts for URI | PS aliases curl | Use `curl.exe` instead of `curl` |

---

## Gotchas & Lessons Learned

- **Always `chmod` after `scp` from Windows** — Windows `scp` creates directories with `700`, Nginx runs as `www-data` and can't read them.
- **Use `curl.exe` on PowerShell** — `curl` is aliased to `Invoke-WebRequest`.
- **Never write to `defensys_db` from scripts** — See `docs/AGENTS.md` for DB safety rules.
