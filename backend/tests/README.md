# Ad-hoc scripts (moved from `backend/` root)

**DEV ONLY — not for production.** Do not run these in deploy pipelines or on production databases.
See [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md).

These files are **not** the same as Django’s per-app `tests.py` modules under
`backend/modules/<app>/tests.py`. This folder holds manual checks, smoke scripts,
seed helpers, and experiments.

## How to run

From the **`backend`** directory (where `manage.py` lives), use **module** mode so
imports resolve:

```powershell
cd backend
python -m tests.check_server
python -m tests.test_endpoint
```

Do **not** add `tests` to `INSTALLED_APPS`.

## Django’s test runner

- **App tests:** `python manage.py test` (uses `authentication_access_control/tests.py`, etc.)
- **Do not** expect `python manage.py test tests` to mean this folder unless you intentionally wire it.
- Use **`--keepdb`** when re-running suites locally so Django does not prompt to delete an existing `test_defensys_db`.
- Obsolete one-off scripts belong under **`archive/`** (see `archive/README.md`).

## Combined dry run (backend + Flutter)

From the repo root:

```powershell
cd backend
python manage.py test

cd ..\frontend
flutter pub get
flutter test
```

Backend tests use a temporary database. Flutter tests use mocked HTTP (`test/helpers/mock_http_setup.dart`) and do not require `runserver`.

## Mobile / emulator against local Django

- `backend/.env`: include `10.0.2.2` in `DJANGO_ALLOWED_HOSTS` (Android emulator) and your LAN IP (physical device).
- Restart `python manage.py runserver 0.0.0.0:8000` after changing `.env`.
- Emulator: `flutter run --dart-define=DEFENSYS_ANDROID_EMULATOR=true`

## Pytest

`pytest.ini` in `backend/` ignores this directory so `test_*.py` names here are not collected as pytest tests.
