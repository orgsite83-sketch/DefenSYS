# Ad-hoc scripts (moved from `backend/` root)

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

## Pytest

`pytest.ini` in `backend/` ignores this directory so `test_*.py` names here are not collected as pytest tests.
