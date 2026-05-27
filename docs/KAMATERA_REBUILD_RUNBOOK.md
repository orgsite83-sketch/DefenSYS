# DefenSYS Kamatera rebuild runbook

Use this when you want to **terminate a Kamatera server to stop billing**, then rebuild DefenSYS later without guessing every step again.

Related docs:

- [KAMATERA_DEPLOYMENT.md](KAMATERA_DEPLOYMENT.md) - full first-time production deployment
- [UPDATE_GUIDE.md](UPDATE_GUIDE.md) - normal code updates after the server already exists
- [DEPLOYMENT.md](DEPLOYMENT.md) - go-live checklist

## The short version

If you **power off** or **suspend** a Kamatera hourly server, it can still charge for disk/IP. If you **terminate** it, Kamatera stops charging for that server, but the VM is deleted.

Before terminating, save:

1. The production `.env`
2. A PostgreSQL database dump
3. Uploaded media files, unless `USE_S3=True`
4. nginx config
5. systemd service files
6. domain/DNS notes
7. the current public IP and server specs

If you skip those backups, rebuilding may still be possible from the repo, but your production data, uploaded files, and exact secrets/configuration can be lost.

## What termination deletes

Terminating the server usually removes:

- The Ubuntu VM
- PostgreSQL database stored on that VM
- `/opt/defensys`
- `backend/.env`
- `backend/media`
- Python virtual environment
- nginx config
- systemd services
- SSL certificates
- the public IP address

It does **not** delete:

- The GitHub/repo copy of the code
- DNS records at your domain provider
- S3 bucket contents, if file storage uses S3
- local files on your laptop
- Kamatera account billing history

## Decision table

| Situation | Best action |
|----------|-------------|
| Need the server again today/tomorrow | Power off, accept small charge |
| Need the same disk exactly | Take a Kamatera snapshot, then compare snapshot cost |
| Need the app later but can restore from backups | Back up DB/media/config, then terminate |
| Server is unused/test only | Terminate |
| Unsure whether it has important data | Back it up first |

## One-time backup folder on your PC

Create a dated folder on your PC before terminating.

PowerShell:

```powershell
mkdir "$HOME\Desktop\defensys-server-backup-YYYY-MM-DD"
cd "$HOME\Desktop\defensys-server-backup-YYYY-MM-DD"
```

Replace `YYYY-MM-DD` with the actual date.

## Pre-termination checklist

Run these before clicking **Terminate Server**.

### 1. Record server details

Write down:

- Kamatera server name, for example `defensys-server`
- Public IP, for example `203.0.113.50`
- Region, for example `AS-SG`
- OS image, for example Ubuntu 22.04 LTS or 24.04 LTS
- CPU/RAM/disk, for example 2 vCPU, 2048 MB RAM, 30 GB disk
- Billing mode, usually hourly
- Domain name, if any
- SSH username, usually `defensys` or `root`

Save this into a local note:

```text
Server name:
Old public IP:
Region:
OS:
CPU/RAM/disk:
Domain:
SSH user:
Terminated on:
Reason:
```

### 2. Confirm the server is reachable

From your PC:

```powershell
ssh defensys@YOUR_SERVER_IP
```

If you only have root login:

```powershell
ssh root@YOUR_SERVER_IP
```

### 3. Back up the production env file

From your PC:

```powershell
scp defensys@YOUR_SERVER_IP:/opt/defensys/backend/.env .\backend.env.production.backup
```

If using root:

```powershell
scp root@YOUR_SERVER_IP:/opt/defensys/backend/.env .\backend.env.production.backup
```

Open it locally and verify it contains the expected production values:

- `DJANGO_SECRET_KEY`
- `DJANGO_DEBUG=False`
- `DJANGO_ALLOWED_HOSTS`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `USE_S3`
- `AWS_*` values, if S3 is enabled
- `REDIS_URL`, if present

Do **not** commit this file.

### 4. Back up PostgreSQL

SSH into the server:

```bash
ssh defensys@YOUR_SERVER_IP
```

Create a database dump:

```bash
mkdir -p ~/defensys-backup
pg_dump -h localhost -U defensys -d defensys_db --format=custom --file ~/defensys-backup/defensys_db.dump
```

If password prompt appears, use the `POSTGRES_PASSWORD` from `/opt/defensys/backend/.env`.

Also create a plain SQL dump for easier inspection:

```bash
pg_dump -h localhost -U defensys -d defensys_db | gzip > ~/defensys-backup/defensys_db.sql.gz
```

Download to your PC:

```powershell
scp defensys@YOUR_SERVER_IP:~/defensys-backup/defensys_db.dump .\defensys_db.dump
scp defensys@YOUR_SERVER_IP:~/defensys-backup/defensys_db.sql.gz .\defensys_db.sql.gz
```

### 5. Back up uploaded files

If `backend/.env` has `USE_S3=True`, uploaded files should be in S3. Confirm the bucket name and credentials are saved in your env backup.

If `USE_S3=False`, download local media:

```powershell
scp -r defensys@YOUR_SERVER_IP:/opt/defensys/backend/media .\media
```

If `scp -r` is slow, zip it on the server first:

```bash
cd /opt/defensys/backend
tar -czf ~/defensys-backup/media.tar.gz media
```

Then download:

```powershell
scp defensys@YOUR_SERVER_IP:~/defensys-backup/media.tar.gz .\media.tar.gz
```

### 6. Back up nginx and systemd config

From your PC:

```powershell
scp defensys@YOUR_SERVER_IP:/etc/nginx/sites-available/defensys .\nginx-defensys.conf
scp defensys@YOUR_SERVER_IP:/etc/systemd/system/defensys.service .\defensys.service
scp defensys@YOUR_SERVER_IP:/etc/systemd/system/defensys-ws.service .\defensys-ws.service
```

If permissions block `scp`, copy them to the deploy user's home first:

```bash
sudo cp /etc/nginx/sites-available/defensys ~/defensys-backup/nginx-defensys.conf
sudo cp /etc/systemd/system/defensys.service ~/defensys-backup/defensys.service
sudo cp /etc/systemd/system/defensys-ws.service ~/defensys-backup/defensys-ws.service
sudo chown defensys:defensys ~/defensys-backup/*.conf ~/defensys-backup/*.service
```

Then download from `~/defensys-backup/`.

### 7. Optional full server snapshot

Kamatera snapshots are useful if you want a full disk restore, but they may also cost money. Use them only if the saved time is worth the snapshot storage cost.

If taking a snapshot, name it clearly:

```text
defensys-before-termination-YYYY-MM-DD
```

### 8. Verify backups before terminating

On your PC, your backup folder should contain at least:

```text
backend.env.production.backup
defensys_db.dump
defensys_db.sql.gz
media/ or media.tar.gz              # only if USE_S3=False
nginx-defensys.conf
defensys.service
defensys-ws.service
server-notes.txt
```

If these files are present, termination is much less scary.

## Terminating the server

In Kamatera:

1. Go to **My Cloud** -> **Servers**
2. Select the server you no longer need
3. Choose **Actions** -> **Terminate Server**
4. Confirm only after backups are complete

After termination, check:

- **Billing** -> **Usage Reports**
- **Billing** -> **Transaction History**
- Server list no longer shows the terminated server

Hourly servers can still appear on a later invoice for usage that happened before termination.

## Rebuild plan

When you need DefenSYS again, rebuild in this order:

1. Create a new Kamatera server
2. SSH in and create the deploy user
3. Install packages
4. Restore PostgreSQL
5. Clone repo
6. Restore `.env`
7. Install Python dependencies
8. Run migrations
9. Restore media
10. Restore systemd services
11. Restore nginx
12. Rebuild/upload Flutter web
13. Point DNS to the new IP
14. Reissue HTTPS certificate
15. Verify login, uploads, mobile, and WebSocket behavior

## Rebuild steps

### 1. Create the new Kamatera server

Recommended baseline:

| Setting | Value |
|---------|-------|
| Image | Ubuntu 22.04 LTS or 24.04 LTS |
| CPU | 2 vCPU |
| RAM | 2 GB minimum, 4 GB preferred |
| Disk | 30 GB minimum, 40-60 GB preferred |
| Region | Singapore or nearest users |
| Network | Public internet |
| Firewall | Allow 22, 80, 443 |

Copy the new public IP.

### 2. SSH and create deploy user

```bash
ssh root@NEW_SERVER_IP
adduser defensys
usermod -aG sudo defensys
rsync --archive --chown=defensys:defensys ~/.ssh /home/defensys/
```

Reconnect as `defensys`:

```bash
ssh defensys@NEW_SERVER_IP
```

### 3. Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

### 4. Install packages

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git nginx postgresql postgresql-contrib certbot python3-certbot-nginx redis-server build-essential libpq-dev
```

Install Python 3.12.

Ubuntu 22.04:

```bash
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3.12-dev
```

Ubuntu 24.04:

```bash
sudo apt install -y python3.12 python3.12-venv python3.12-dev
```

Verify:

```bash
python3.12 --version
```

### 5. Create PostgreSQL user and database

Use the same DB values from `backend.env.production.backup`.

```bash
sudo -u postgres psql
```

Inside `psql`:

```sql
CREATE USER defensys WITH PASSWORD 'REPLACE_WITH_POSTGRES_PASSWORD_FROM_BACKUP_ENV';
CREATE DATABASE defensys_db OWNER defensys;
\q
```

### 6. Upload and restore database dump

From your PC backup folder:

```powershell
scp .\defensys_db.dump defensys@NEW_SERVER_IP:~/defensys_db.dump
```

On the server:

```bash
pg_restore -h localhost -U defensys -d defensys_db --clean --if-exists ~/defensys_db.dump
```

If restore complains about ownership, try:

```bash
pg_restore -h localhost -U defensys -d defensys_db --no-owner --clean --if-exists ~/defensys_db.dump
```

### 7. Clone the repo

```bash
sudo mkdir -p /opt/defensys
sudo chown defensys:defensys /opt/defensys
cd /opt/defensys
git clone https://github.com/YOUR_ORG/DefenSYS.git .
```

If using SSH:

```bash
git clone git@github.com:YOUR_ORG/DefenSYS.git .
```

### 8. Restore `.env`

From your PC:

```powershell
scp .\backend.env.production.backup defensys@NEW_SERVER_IP:/opt/defensys/backend/.env
```

On the server:

```bash
chmod 600 /opt/defensys/backend/.env
nano /opt/defensys/backend/.env
```

Update these values:

```env
DJANGO_ALLOWED_HOSTS=NEW_SERVER_IP,defensys.yourdomain.edu
```

Keep these from the backup unless intentionally rotating secrets:

```env
DJANGO_SECRET_KEY=...
POSTGRES_PASSWORD=...
USE_S3=...
AWS_...
```

If restoring an existing database, keeping the same `DJANGO_SECRET_KEY` avoids invalidating some signed Django data. If you are starting fresh, generate a new one.

### 9. Install Python dependencies

```bash
cd /opt/defensys/backend
python3.12 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn
```

### 10. Run checks and migrations

```bash
cd /opt/defensys/backend
source venv/bin/activate
python manage.py check --deploy
python manage.py migrate --noinput
```

If you restored a real DB dump, migrations may already be applied. Running `migrate --noinput` is still correct.

### 11. Restore media files

Skip this if `USE_S3=True` and the S3 bucket is still available.

If you backed up a `media` folder:

```powershell
scp -r .\media defensys@NEW_SERVER_IP:/opt/defensys/backend/media
```

If you backed up `media.tar.gz`:

```powershell
scp .\media.tar.gz defensys@NEW_SERVER_IP:~/media.tar.gz
```

On the server:

```bash
cd /opt/defensys/backend
tar -xzf ~/media.tar.gz
chown -R defensys:defensys /opt/defensys/backend/media
```

### 12. Restore systemd services

From your PC:

```powershell
scp .\defensys.service defensys@NEW_SERVER_IP:~/defensys.service
scp .\defensys-ws.service defensys@NEW_SERVER_IP:~/defensys-ws.service
```

On the server:

```bash
sudo cp ~/defensys.service /etc/systemd/system/defensys.service
sudo cp ~/defensys-ws.service /etc/systemd/system/defensys-ws.service
sudo systemctl daemon-reload
sudo systemctl enable redis-server
sudo systemctl start redis-server
sudo systemctl enable defensys
sudo systemctl enable defensys-ws
sudo systemctl start defensys
sudo systemctl start defensys-ws
```

Check:

```bash
sudo systemctl status defensys
sudo systemctl status defensys-ws
journalctl -u defensys -n 80 --no-pager
journalctl -u defensys-ws -n 80 --no-pager
```

### 13. Restore nginx config

From your PC:

```powershell
scp .\nginx-defensys.conf defensys@NEW_SERVER_IP:~/nginx-defensys.conf
```

On the server:

```bash
sudo cp ~/nginx-defensys.conf /etc/nginx/sites-available/defensys
sudo ln -sf /etc/nginx/sites-available/defensys /etc/nginx/sites-enabled/defensys
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

If the config contains the old IP or old domain, edit it:

```bash
sudo nano /etc/nginx/sites-available/defensys
sudo nginx -t
sudo systemctl reload nginx
```

### 14. Rebuild and upload Flutter web

Build on your PC:

```powershell
cd frontend
flutter pub get
flutter build web --release `
  --dart-define=DEFENSYS_API_HOST=defensys.yourdomain.edu `
  --dart-define=DEFENSYS_API_SCHEME=https `
  --dart-define=DEFENSYS_API_PORT=
```

If you do not have the domain yet and are testing by IP:

```powershell
flutter build web --release `
  --dart-define=DEFENSYS_API_HOST=NEW_SERVER_IP `
  --dart-define=DEFENSYS_API_SCHEME=http `
  --dart-define=DEFENSYS_API_PORT=
```

Prepare web root on the server:

```bash
sudo mkdir -p /var/www/defensys
sudo chown defensys:defensys /var/www/defensys
```

Upload from your PC:

```powershell
scp -r frontend/build/web/* defensys@NEW_SERVER_IP:/var/www/defensys/
```

### 15. DNS and HTTPS

At your DNS provider, update the A record:

```text
defensys.yourdomain.edu -> NEW_SERVER_IP
```

Wait for DNS to resolve:

```powershell
nslookup defensys.yourdomain.edu
```

On the server:

```bash
sudo certbot --nginx -d defensys.yourdomain.edu
sudo systemctl reload nginx
```

### 16. Create admin only if needed

If you restored the old database, existing admin accounts should still exist.

If this is a fresh database:

```bash
cd /opt/defensys/backend
source venv/bin/activate
export DJANGO_SUPERUSER_USERNAME=admin
export DJANGO_SUPERUSER_EMAIL=admin@yourdomain.edu
export DJANGO_SUPERUSER_PASSWORD='REPLACE_WITH_STRONG_ADMIN_PASSWORD'
python manage.py create_admin
```

## Verification checklist

Run from the server:

```bash
curl -I http://127.0.0.1:8000/api/login/
sudo systemctl status defensys
sudo systemctl status defensys-ws
sudo nginx -t
```

Run from your PC/browser:

- Open `https://defensys.yourdomain.edu/`
- Log in as admin
- Open Django admin at `/admin/`
- Upload a test deliverable
- Download/open the uploaded file
- Test student login
- Test panelist flow
- Test peer evaluation toggle/live update
- Check browser dev tools for failed `/api/` or `/ws/` requests

Check logs:

```bash
journalctl -u defensys -n 100 --no-pager
journalctl -u defensys-ws -n 100 --no-pager
sudo tail -n 100 /var/log/nginx/error.log
```

## Cost-control checklist

Use this every time you create or terminate servers:

- [ ] Only one active DefenSYS server unless you are intentionally testing a second one
- [ ] Unused test servers terminated, not just powered off
- [ ] Billing mode checked: hourly vs monthly
- [ ] Snapshots reviewed for storage charges
- [ ] Extra disks removed if unused
- [ ] Usage Reports checked after termination
- [ ] Transaction History checked after termination
- [ ] Trial server identified; second server assumed paid unless Kamatera confirms otherwise

## Common rebuild problems

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Missing DJANGO_SECRET_KEY` | `.env` not restored | Upload env backup to `/opt/defensys/backend/.env`, `chmod 600`, restart |
| 400 Bad Request | New IP/domain missing from `DJANGO_ALLOWED_HOSTS` | Edit `.env`, restart `defensys` |
| 502 Bad Gateway | Gunicorn not running | `sudo systemctl status defensys`, check logs |
| Web loads but API fails | Flutter build points to old IP/domain | Rebuild web with new `--dart-define`, upload again |
| Uploads missing | `media` not restored or S3 env wrong | Restore media or verify S3 bucket/keys |
| Login users missing | DB dump not restored | Restore `defensys_db.dump` |
| WebSocket live update fails | Redis/Daphne not running | Start `redis-server` and `defensys-ws`, check logs |
| HTTPS fails | DNS still points to old IP | Update A record, wait, rerun Certbot |
| Permission denied on files | Restored as root | `sudo chown -R defensys:defensys /opt/defensys /var/www/defensys` |

## Minimal rebuild if no production data matters

If the server had no important users/files/data, you can skip DB/media restore:

1. Create new Kamatera server
2. Follow [KAMATERA_DEPLOYMENT.md](KAMATERA_DEPLOYMENT.md)
3. Create a fresh admin
4. Re-import test/demo data manually through the app

This is cheaper mentally, but only safe when losing the old database is acceptable.

## Final rule

Terminate servers to stop cost. Back up first to avoid pain. Keep this runbook updated after every real rebuild so the next one is boring.
