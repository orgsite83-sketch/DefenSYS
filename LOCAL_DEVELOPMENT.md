# Local backup and fresh development database

Run these PowerShell commands from the DefenSYS project root. The normal
`backend/.env` continues to select `defensys_db`. Sandbox commands explicitly
select `defensys_backend.settings_sandbox`; they use `defensys_sandbox` and
`.sandbox/defensys_sandbox/media/` instead.

## Back up the current setup

Pause backend processes, automation and uploads while taking a full backup.
PostgreSQL provides a consistent database snapshot, but PostgreSQL and the
filesystem do not share a transaction. The script rejects uploads that change
while it runs; pausing writers also coordinates the database with those files.

```powershell
.\backend\venv\Scripts\python.exe deployment\backup\backup_db.py --full
```

This creates a new ZIP in `.backups/` containing:

- `database.dump`: PostgreSQL schema, records, password hashes and sequences.
- `media/`: all current uploads, including documents, signatures and avatars.
- `source/`: current Git-listed working files, including uncommitted changes
  and nonignored new files, plus local `docs/` and `directives/`.
- `config/`: available root, backend and frontend `.env` files for recovery.
- `manifest.json`: per-file SHA-256 hashes, database table counts and versions.

The ZIP is verified after creation, is never overwritten, and is excluded from
Git. Full ZIPs are retained until you choose to remove them. Dependency folders,
build outputs, `.git/`, `.tmp/` and sandbox uploads are excluded. Reinstall
dependencies from the archived requirements and lockfiles when recovering.
The archive includes private records and secrets; it is not encrypted. Store it
privately. A copy on another drive provides protection against failure of this PC.

Verify an archive again:

```powershell
.\backend\venv\Scripts\python.exe deployment\backup\backup_db.py --verify ".backups\YOUR_BACKUP.zip"
```

For recovery, extract the archive into a separate folder. Restore
`database.dump` into a **new database** with PostgreSQL `pg_restore --no-owner
--no-privileges --exit-on-error --single-transaction`, copy `media/` into that
environment's configured uploads directory, and recover the archived source
and configuration. Update the recovered configuration to select the new DB.
Do not use the legacy `restore_db.py --force` to create a sandbox: that command
cleans and replaces the database selected in the normal `.env`.

The older no-argument `backup_db.py` command still makes database-only dumps
with its existing retention policy. Use `--full` to include files and source.

## Create a fresh sandbox once

```powershell
.\backend\venv\Scripts\python.exe execution\setup_sandbox.py
```

This creates a new local PostgreSQL database and applies all current migrations.
It refuses an existing database or a nonempty sandbox uploads folder. It does
not copy current accounts, teams, school years, schedules, evaluations or files.
Django's internal permissions and migration records are included. Defense
stages start empty: add them yourself in Defense Stages Setup. The initial
migration no longer inserts sample stages. The setup tool never runs demo or
suggested-deliverable seeds; the legacy stage fixture command is test-only.

Create your own administrator interactively:

```powershell
.\backend\venv\Scripts\python.exe backend\manage.py createsuperuser --settings=defensys_backend.settings_sandbox
```

Then configure school years/semesters, accounts, teams and defense requirements
in the app to exercise the entire flow yourself. Current database credentials
and passwords are unchanged. Sandbox email and SMS use console backends;
WebSocket events use a process-local channel layer.

## Reset an existing testing sandbox

Preview the exact target and retained administrator count from the project root:

```powershell
.\backend\venv\Scripts\python.exe execution\reset_sandbox.py --database defensys_sandbox
```

To clear its testing data:

```powershell
.\backend\venv\Scripts\python.exe execution\reset_sandbox.py --database defensys_sandbox --apply
```

The reset only accepts a separate local `defensys_sandbox[_name]` database and
checks the actual connected database name. It saves and verifies a PostgreSQL
dump under `.backups/`, then runs Django flush and restores the existing admin
accounts/groups inside one transaction. Admin identities and password hashes
must match exactly before commit. Non-admin accounts and application setup,
teams, schedules, evaluations, submissions, and audit records are cleared;
schema, migrations, internal permissions, and administrator access remain.

The normal database is accessed only for read-only aggregate counts before and
after the operation. The reset report records that comparison. Upload files are
retained on disk, so saved administrator avatars/signatures and the database
backup's file references remain usable; the cleared test submissions no longer
appear in the app. Refresh the app after resetting and configure the academic
periods and workflows again. The command does not change the normal `.env` or
switch the running backend to another environment.

Safety checks: `backend\venv\Scripts\python.exe -m unittest execution.test_backup_sandbox -v`.

## Run the app with the fresh database

`setup_sandbox.py` is a one-time step. You can continue using the usual web
launcher for everyday development. From the project root, select the sandbox
in the current PowerShell terminal and run:

```powershell
$env:DJANGO_SETTINGS_MODULE = "defensys_backend.settings_sandbox"
.\backend\venv\Scripts\python.exe execution\start_local_web.py --restart-backend
```

The launcher starts both Django and Flutter with the fresh database and its
separate uploads. `--restart-backend` ensures it replaces an identified
workspace backend instead of reusing a running server with the original DB.
If the launcher cannot verify ownership of an existing backend, stop that
backend manually and rerun. The usual LAN/hotspot and Android options still work.

To return to the original database with the launcher, stop it with Ctrl+C,
then run in the same terminal:

```powershell
Remove-Item Env:DJANGO_SETTINGS_MODULE -ErrorAction SilentlyContinue
.\backend\venv\Scripts\python.exe execution\start_local_web.py --restart-backend
```

Sign out and sign in with the account for the selected database after switching.
Keep the settings override in each terminal used for sandbox automation too.

To run only the backend, stop any backend already using port 8000, then run:

```powershell
.\backend\venv\Scripts\python.exe backend\manage.py runserver 127.0.0.1:8000 --settings=defensys_backend.settings_sandbox
```

Your usual local Flutter frontend already connects to port 8000. Sign out and
sign in using the sandbox administrator you created; existing login tokens do
not work in the sandbox. Use localhost for this loopback-only development setup.

To return to the original data, stop the sandbox server with Ctrl+C and run:

```powershell
.\backend\venv\Scripts\python.exe backend\manage.py runserver 127.0.0.1:8000 --settings=defensys_backend.settings
```

Sign out and sign in again with your original account. No restore is needed to
switch: both databases and their uploaded files remain separate. Code changes
are shared; migration commands must also select the intended settings module.

If you use the automation scripts against the sandbox, set the following in
**each** automation terminal so local account discovery and API calls use the
same database. Keep the sandbox API on the scripts' default port 8000:

```powershell
$env:DJANGO_SETTINGS_MODULE = "defensys_backend.settings_sandbox"
```

When returning that terminal to your original setup, remove the override with
`Remove-Item Env:DJANGO_SETTINGS_MODULE`. The explicit `--settings` commands
above work without changing the terminal environment.

For future sandbox schema changes:

```powershell
.\backend\venv\Scripts\python.exe backend\manage.py migrate --settings=defensys_backend.settings_sandbox
```

Rebuilding Flutter does not apply Django migrations. The normal development
database and the sandbox each need their own migrations, even though they use
the same source code. For example, a missing `defense.0049_deliverable_template`
in the sandbox causes stage creation to fail with HTTP 500 while an empty
stage list and the basic database health check can still succeed. Check the
running backend's settings and migrate that environment; do not reset the
database or recreate its accounts to fix a missing table.

To start another empty sandbox without erasing this one:

```powershell
.\backend\venv\Scripts\python.exe execution\setup_sandbox.py --database defensys_sandbox_flow2
$env:DEFENSYS_SANDBOX_DB = "defensys_sandbox_flow2"
.\backend\venv\Scripts\python.exe backend\manage.py createsuperuser --settings=defensys_backend.settings_sandbox
.\backend\venv\Scripts\python.exe backend\manage.py runserver 127.0.0.1:8000 --settings=defensys_backend.settings_sandbox
```

Set `DEFENSYS_SANDBOX_DB` in each terminal used for a named sandbox. Remove it
with `Remove-Item Env:DEFENSYS_SANDBOX_DB` to select `defensys_sandbox` again.
Sandbox PostgreSQL credentials come from `backend/.env`; that role needs
permission to create databases for the setup command.

Run automatic regression tests separately with `manage.py test ... --keepdb`.
Those use `test_defensys_db` (or `test_defensys_sandbox` with sandbox settings),
which is separate from both interactive databases. Some existing file tests
use configured media storage unless the suite overrides it; select sandbox
settings or ensure temporary storage is configured when testing uploads.
