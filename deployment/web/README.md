# Phone browser and installed web-app updates

Use the versioned release tools for production web changes. A source pull or a
raw `flutter build web` followed by copying `build/web` is not a complete release:
it can leave version metadata missing and put the generated caching worker back.

The startup document requests a fresh bootstrap URL to bypass legacy Flutter
workers that cache the bare URL. Preparation disables generated offline caching,
packages the retirement worker, and points app code/assets at an immutable release
directory. Nginx must serve release metadata as JSON and startup files with
`Cache-Control: no-store`. The retirement worker remains at its old URL to migrate
existing installations. Save open work and reopen/reload the app after deployment;
browser worker-update scheduling can delay migration in an already open app.
Nothing here clears browser credentials/drafts or reloads an active editor.

## 1. Prepare locally (PowerShell, repository root)

Choose a build higher than the published web build. This example uses version
1.0.2, build 3; the publisher refuses a non-increasing build. No APK is needed.

```powershell
.\backend\venv\Scripts\python.exe execution\prepare_app_release.py web --version 1.0.2 --build 3 --origin https://defensys.site
```

Read `deployment.json` from the resulting directory (the preparation tool prints
the release ID). For this example, load the latest matching prepared release:

```powershell
$releaseFolder = Get-ChildItem .tmp\releases -Directory -Filter 'web-1-0-2-3-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$release = Get-Content (Join-Path $releaseFolder.FullName 'deployment.json') -Raw | ConvertFrom-Json
$release
```

Upload source changes through your normal Git push/pull workflow. Alternatively,
copy the files below explicitly. Set the SSH target to your CURRENT server; older
repository deployment guides contain different IP addresses.

```powershell
$deployTarget = 'defensys@YOUR_CURRENT_SERVER_IP'
scp $release.archive "${deployTarget}:~/"
scp execution/prepare_app_release.py execution/publish_app_release.py execution/verify_web_release.py "${deployTarget}:/opt/defensys/execution/"
scp deployment/nginx/releases.conf "${deployTarget}:/opt/defensys/deployment/nginx/"
scp deployment/web/retire_flutter_service_worker.js "${deployTarget}:/opt/defensys/deployment/web/"
```

The publisher imports `prepare_app_release.py` and compares the packaged worker
against `deployment/web/retire_flutter_service_worker.js`; upload those too.
These files contain no backend configuration, uploads, database data or keys.

## 2. Configure Nginx once (server Bash)

Back up the active site config before editing it. Preserve the current HTTPS
domain, certificates, API/media/WebSocket routes and web root. Do not replace the
live configuration with the HTTP starter template.

```bash
sudo cp -p /etc/nginx/sites-available/defensys /etc/nginx/sites-available/defensys.before-web-updates-$(date +%Y%m%d_%H%M%S)
sudo nano /etc/nginx/sites-available/defensys
```

Inside the existing HTTPS `server` block, add this ONCE, after its root directive:

```nginx
include /opt/defensys/deployment/nginx/releases.conf;
```

If the include is already present, keep it. If equivalent exact locations were
previously added manually, consolidate them so there are no duplicate locations.

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Do not continue if validation fails. The include uses the publisher's default
paths `/var/www/defensys` and `/var/www/defensys-releases`.

## 3. Preview and activate (server Bash)

Replace `YOUR_RELEASE_ID` and `YOUR_SHA256` with the values in local
`deployment.json`. Both commands use the SAME archive and hash.

```bash
cd /opt/defensys
python3 execution/publish_app_release.py ~/YOUR_RELEASE_ID.tar.gz --sha256 YOUR_SHA256
sudo python3 execution/publish_app_release.py ~/YOUR_RELEASE_ID.tar.gz --sha256 YOUR_SHA256 --apply
```

Activation keeps the previous web directory/release and changes the web symlink.
It publishes web metadata and preserves existing Android metadata. No backend
restart, database restore, database migration or `.env` edit is needed.

## 4. Verify before checking the phone

From your PC:

```powershell
.\backend\venv\Scripts\python.exe execution\verify_web_release.py --origin https://defensys.site --release-id $release.release_id
```

Or from the server:

```bash
cd /opt/defensys
python3 execution/verify_web_release.py --origin https://defensys.site --release-id YOUR_RELEASE_ID
```

The check fails for HTML at latest.json, missing no-store headers, the old caching
worker, mismatched release pointers or broken versioned bootstrap routing. All
requests are read-only. After it succeeds, save work on the phone, close the
Chrome and installed-app windows, reopen, and confirm version 1.0.2 / build 3 in
Settings. Subsequent releases must use higher web builds through the same tools.

## Local regression checks

```powershell
.\backend\venv\Scripts\python.exe -m unittest execution.test_app_releases execution.test_verify_web_release -v
node execution/test_web_startup.cjs
node execution/test_retire_worker.cjs
```
