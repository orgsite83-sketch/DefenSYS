# DefenSYS — Update guide (backend, web, mobile)

Quick reference for **what to run** after you change code on your PC or deploy to the Kamatera server.

**Related docs:**

- [DEMO_SETUP_GUIDE.md](DEMO_SETUP_GUIDE.md) — first-time local setup
- [KAMATERA_DEPLOYMENT.md](KAMATERA_DEPLOYMENT.md) — full server install
- [DEPLOYMENT.md](DEPLOYMENT.md) — go-live checklist

---

## At a glance

| You changed | Local dev (your PC) | Production (Kamatera server) |
|-------------|---------------------|------------------------------|
| **Backend** (`backend/`) | Restart `runserver`; run migrations if models changed | `pip install`, `migrate`, restart `defensys` + `defensys-ws` |
| **Web UI** (`frontend/` — admin/faculty in browser) | Hot reload via `flutter run -d chrome` or rebuild | `flutter build web` on PC → upload to `/var/www/defensys/` |
| **Mobile UI** (`frontend/` — student/panelist app) | `flutter run` on emulator/device | `flutter build apk` on PC → distribute new APK |

The **web** and **mobile** apps share the same Flutter project (`frontend/`). Only the **build target** and **API host** (`--dart-define`) differ.

---

## Before any update (recommended)

Run on your PC from the repo root:

```powershell
# Backend
cd backend
.\venv\Scripts\Activate.ps1
python manage.py check
python manage.py test --keepdb

# Frontend
cd ..\frontend
flutter pub get
flutter analyze
flutter test
```

On the server (before production backend deploy):

```bash
cd /opt/defensys/backend
source venv/bin/activate
python manage.py check --deploy
```

---

## 1. Backend updates

Backend = Django REST API (`backend/`), usually on port **8000**. WebSockets (real-time grading flags) use **Daphne** on port **8001** when deployed.

### 1a. Local development (Windows)

**Every time you pull or edit Python code**, restart the API:

```powershell
cd backend
.\venv\Scripts\Activate.ps1

# First time or after requirements.txt changed:
pip install -r requirements.txt

# After model/migration changes:
python manage.py makemigrations
python manage.py migrate

# Run API (keep this terminal open):
python manage.py runserver 0.0.0.0:8000
```

**Optional — WebSockets locally** (peer-eval live sync):

1. Install and start Redis, **or** add to `backend/.env`:
   ```env
   DEFENSYS_USE_INMEMORY_CHANNELS=1
   ```
2. Second terminal:
   ```powershell
   cd backend
   .\venv\Scripts\Activate.ps1
   daphne -b 127.0.0.1 -p 8001 defensys_backend.asgi:application
   ```

`runserver` alone does **not** serve WebSockets; use Daphne for `/ws/grading/` tests.

**JWT session lengths** (optional overrides in `backend/.env`):

| Variable | Default | Meaning |
|----------|---------|---------|
| `JWT_ACCESS_TOKEN_HOURS` | 8 | API token lifetime (auto-renewed while you work) |
| `JWT_REFRESH_STANDARD_HOURS` | 12 | Max idle sign-in without Remember me |
| `JWT_REFRESH_REMEMBER_DAYS` | 7 | Max idle sign-in when Remember me is checked at login |

Login sends `remember_me: true` for the longer refresh. See [DEFENSYS_REAL_SYSTEM_FLOW.md](DEFENSYS_REAL_SYSTEM_FLOW.md) § Authentication.

### 1b. Production server (Kamatera)

SSH into the server, then:

```bash
cd /opt/defensys
git pull
# If not a git repo, use rsync from KAMATERA_DEPLOYMENT.md §15

cd backend
source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate --noinput
python manage.py check --deploy
sudo systemctl restart defensys
sudo systemctl restart defensys-ws
```

**Restart cheat sheet**

| Service | Command | When |
|---------|---------|------|
| REST API (Gunicorn) | `sudo systemctl restart defensys` | Any backend code/settings change |
| WebSocket (Daphne) | `sudo systemctl restart defensys-ws` | `realtime/`, Channels, or `.env` `REDIS_URL` |
| Redis | `sudo systemctl restart redis-server` | Rare; only if Redis itself changed |
| nginx | `sudo systemctl reload nginx` | Only after editing nginx site config |

**Logs**

```bash
journalctl -u defensys -n 80 --no-pager
journalctl -u defensys-ws -n 80 --no-pager
```

---

## 2. Web UI updates (admin / faculty in browser)

Web UI = same `frontend/` project, built for **web** and served as static files (nginx → `/var/www/defensys/`).

### 2a. Local development

```powershell
cd frontend
flutter pub get

# Dev server with hot reload (uses localhost API :8000 by default):
flutter run -d chrome
```

If the API runs on another machine or port, use `--dart-define` (see §4).

After `flutter pub get` or dependency changes, stop and run again.

### 2b. Production deploy

Build on **your PC** (not on the VPS):

```powershell
cd frontend
flutter pub get
flutter build web --release
```

**HTTPS production** (replace with your domain):

```powershell
flutter build web --release `
  --dart-define=DEFENSYS_API_HOST=defensys.yourdomain.edu `
  --dart-define=DEFENSYS_API_SCHEME=https `
  --dart-define=DEFENSYS_API_PORT=
```

Upload to the server:

```powershell
scp -r frontend/build/web/* defensys@YOUR_SERVER_IP:/var/www/defensys/
```

No Gunicorn restart needed for web-only changes. Hard-refresh the browser (`Ctrl+Shift+R`) if assets look cached.

---

## 3. Mobile UI updates (student / panelist APK)

Mobile = same `frontend/` project, built for **Android** (APK). iOS is not documented in this repo’s deploy path.

### 3a. Local development

```powershell
cd frontend
flutter pub get

# List devices:
flutter devices

# Android emulator (Django on host PC → 10.0.2.2):
flutter run --dart-define=DEFENSYS_ANDROID_EMULATOR=true

# Physical phone on same Wi‑Fi (use your PC’s LAN IP):
flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.100
```

Ensure `DJANGO_ALLOWED_HOSTS` in `backend/.env` includes `10.0.2.2` (emulator) and your LAN IP (phone), then **restart** `runserver`.

For WebSocket testing on a phone, the API host must reach Daphne/nginx `/ws/` — easiest on production HTTPS; locally you can run Daphne on `0.0.0.0:8001` and point defines at your LAN IP (advanced).

### 3b. Production APK (release)

```powershell
cd frontend
flutter pub get
flutter build apk --release `
  --dart-define=DEFENSYS_API_HOST=defensys.yourdomain.edu `
  --dart-define=DEFENSYS_API_SCHEME=https `
  --dart-define=DEFENSYS_API_PORT=
```

Output APK:

```text
frontend/build/app/outputs/flutter-apk/app-release.apk
```

Distribute the new APK to users (portal, MDM, etc.). Users must **install the new build**; it is not auto-updated like the web app.

**Backend-only changes** do not require a new APK unless you changed Flutter code or `api_config` behavior.

---

## 4. API host overrides (`--dart-define`)

Used when the app must not use default `127.0.0.1:8000`.

| Variable | Example | Purpose |
|----------|---------|---------|
| `DEFENSYS_API_HOST` | `192.168.1.50` or `defensys.school.edu` | API hostname |
| `DEFENSYS_API_SCHEME` | `https` | `http` or `https` |
| `DEFENSYS_API_PORT` | *(empty)* | Omit `:8000` behind nginx 443 |
| `DEFENSYS_ANDROID_EMULATOR` | `true` | Use `10.0.2.2` on Android emulator |

Web production build typically sets all three host/scheme/port defines. Mobile production uses the same for a public server.

---

## 5. Common combined scenarios

### Only Flutter UI (no backend changes)

| Target | Action |
|--------|--------|
| Local web | Save files → hot reload, or `r` in `flutter run` terminal |
| Local mobile | Save → hot reload, or restart `flutter run` |
| Production web | `flutter build web --release` → `scp` to `/var/www/defensys/` |
| Production mobile | `flutter build apk --release` → distribute APK |

### Backend + web + mobile together

1. Deploy backend (§1b) — **migrate + restart `defensys` and `defensys-ws`**
2. Build and upload web (§2b)
3. Build and distribute APK (§3b) if mobile UI or API URL changed

### Database migrations only

```powershell
# Local
cd backend
.\venv\Scripts\Activate.ps1
python manage.py migrate
```

```bash
# Production
cd /opt/defensys/backend && source venv/bin/activate
python manage.py migrate --noinput
sudo systemctl restart defensys
```

No Flutter rebuild required unless you also changed the frontend.

---

## 6. Full local stack (three terminals)

Typical day when working on all layers:

| Terminal | Command |
|----------|---------|
| 1 — API | `cd backend` → venv → `python manage.py runserver 0.0.0.0:8000` |
| 2 — WebSocket (optional) | `daphne -b 127.0.0.1 -p 8001 defensys_backend.asgi:application` |
| 3 — Flutter | `cd frontend` → `flutter run -d chrome` **or** `flutter run` with device defines |

---

## 7. What not to run in production

- `python manage.py runserver` — use Gunicorn (`defensys` service)
- `dev_create_40_students` or ad-hoc scripts on the live DB
- Committing or copying dev `.env` to the server

See [KAMATERA_DEPLOYMENT.md §14](KAMATERA_DEPLOYMENT.md#14-go-live-verification).

---

## 8. Quick troubleshooting

| Problem | Check |
|---------|--------|
| Web loads, API 404 / wrong port | Rebuild web with `DEFENSYS_API_PORT=` empty; same-origin nginx |
| Phone cannot login | `DEFENSYS_API_HOST` = PC LAN IP; `DJANGO_ALLOWED_HOSTS` includes that IP |
| Peer eval does not update live | `defensys-ws` running; Redis up; `REDIS_URL` in server `.env` |
| 502 after backend deploy | `journalctl -u defensys -n 50`; run `migrate` |
| Old web UI after deploy | Hard refresh browser; confirm `scp` targeted `/var/www/defensys/` |

More detail: [KAMATERA_DEPLOYMENT.md §16 — Troubleshooting](KAMATERA_DEPLOYMENT.md#16-troubleshooting).
