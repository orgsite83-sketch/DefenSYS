# DefenSYS Database Backup & Restore Guide

This directory contains automated scripts to manage PostgreSQL database backups and restorations for the DefenSYS monorepo. S3 off-server backups have been removed to focus entirely on server-based local backup administration.

---

## 📂 Contents

- **[backup_db.py](backup_db.py)**: Automated PostgreSQL dump script with password environment isolation and configurable retention.
- **[restore_db.py](restore_db.py)**: Database restoration helper with interactive file selection and safety constraints.

---

## 🛠️ Configuration

Both scripts read settings directly from your backend environment files. By default, they will try to locate `/opt/defensys/backend/.env`.

### Supported Variables in `.env`
```env
POSTGRES_DB=defensys_db
POSTGRES_USER=defensys
POSTGRES_PASSWORD=your_strong_password
POSTGRES_HOST=localhost
POSTGRES_PORT=5432

# Directory where backup files will be saved (Default: /var/backups/defensys)
DEFENSYS_BACKUP_DIR=/var/backups/defensys

# Local retention in days before old dumps are pruned (Default: 7)
DEFENSYS_BACKUP_RETENTION_DAYS=7
```

---

## 💾 Running Backups

### Manual Backup
To run a database backup immediately, execute:

```bash
python3 /opt/defensys/deployment/backup/backup_db.py
```

This generates a compressed binary format dump file at your configured backup directory:
`defensys_db_YYYYMMDD_HHMMSS.dump`

### Scheduling Daily Backups (Cron)
We recommend scheduling backups to run automatically every night.

1. Open the crontab editor for the `defensys` user:
   ```bash
   crontab -e
   ```

2. Add a line to execute the backup script daily at 2:00 AM:
   ```cron
   0 2 * * * /usr/bin/python3 /opt/defensys/deployment/backup/backup_db.py >> /var/log/defensys_backup.log 2>&1
   ```

3. Ensure the `defensys` user has write permissions to `/var/backups/defensys` and `/var/log/defensys_backup.log`.

---

## 🔄 Restoring Backups

The restoration procedure uses `pg_restore` under the hood. It runs with `--clean` and `--if-exists` flags, which drop all existing tables and recreate them from the backup.

> [!WARNING]
> Restoring a backup completely overwrites all existing data in the target database. Perform restores with extreme care.

### Interactive Restoration
To choose from a list of automatically discovered backups:

```bash
python3 /opt/defensys/deployment/backup/restore_db.py
```

You will see a numbered list of available backup files. Enter the number corresponding to your chosen backup file and type `yes` to confirm.

### Specific File Restoration
To restore a specific `.dump` file directly:

```bash
python3 /opt/defensys/deployment/backup/restore_db.py /path/to/backup.dump
```

### Automation / Non-Interactive Restores
If you want to run the restore script inside an automated build or test pipeline, bypass the confirmation prompt with `--force`:

```bash
python3 /opt/defensys/deployment/backup/restore_db.py /path/to/backup.dump --force
```

---

## 📝 Troubleshooting & Notes

- **Permissions**: If the scripts warn that they cannot write to `/var/backups/defensys`, they will create a local folder `deployment/backup/backups` and write dumps there. For production, ensure the directories are properly provisioned:
  ```bash
  sudo mkdir -p /var/backups/defensys
  sudo chown -R defensys:defensys /var/backups/defensys
  ```
- **Postgres Utilities**: Ensure `pg_dump` and `pg_restore` are available in your path. On Ubuntu, these are installed as part of the `postgresql-client` packages.
