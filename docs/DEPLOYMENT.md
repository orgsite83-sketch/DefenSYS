# DefenSYS deployment checklist

Use this before go-live. Local demos may use `docs/DEMO_SETUP_GUIDE.md`; production should follow this list.

**Full server guide (Kamatera VPS):** [KAMATERA_DEPLOYMENT.md](KAMATERA_DEPLOYMENT.md) — create VM → deploy repo → HTTPS → go live.

**Rebuild after terminating a paid VPS:** [KAMATERA_REBUILD_RUNBOOK.md](KAMATERA_REBUILD_RUNBOOK.md) - backup checklist, terminate safely, restore DefenSYS on a fresh server.

## Do not run in production

- `python manage.py dev_create_40_students` (prototype `student1`–`student40` accounts)
- Any script under `backend/tests/` (ad-hoc dev utilities; not Django test discovery)
- `backend/scripts/` repair utilities unless you understand the migration state
- A separate `mock_server.py` on port 8080 (mobile and web use Django on port 8000)

## Bootstrap admin

Create the first admin with environment variables (no hardcoded passwords in the repo):

```bash
export DJANGO_SUPERUSER_USERNAME=admin
export DJANGO_SUPERUSER_EMAIL=admin@yourdomain.edu
export DJANGO_SUPERUSER_PASSWORD='<strong-secret>'
python manage.py create_admin
```

Alternatively use Django’s built-in `createsuperuser`.

## Removed prototype APIs

These routes must **not** exist in production builds:

- `POST /api/grading/grades/demo-fill/`
- `POST /api/repository/audit/demo-fill/`
- `POST /api/repository/deliverables/demo-fill/`
- `POST /api/grading/rubrics/seed-demo/`

There is no `ENABLE_PROTOTYPE_TOOLS` setting.

## Verify before go-live

- [ ] PIT Lead team import shows students from User Management (numeric IDs), not only `student1`–`student30`
- [ ] Mobile panelist grading uses `GET /api/defense/schedules/panelist-assignments/` and `POST .../submit-grades/`
- [ ] Student peer evaluation uses `POST /api/grading/grades/peer-evaluations/` with JWT
- [ ] Student digital vault uses `GET /api/repository/vault/` (no hardcoded archive data)
- [ ] `python manage.py test` passes (backend API dry run; uses isolated test DB)
- [ ] `cd frontend && flutter test` passes (unit, provider, and widget tests; no live server)
- [ ] Secrets rotated; `.env` not committed

## Stack

- **Backend:** Django (`python manage.py runserver` or production WSGI/ASGI)
- **Frontend:** Flutter web/mobile against `ApiConfig` (port 8000 by default)
