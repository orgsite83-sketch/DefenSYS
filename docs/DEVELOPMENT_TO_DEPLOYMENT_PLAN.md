# Development → deployment roadmap (DefenSYS)

Practical order of work from “messy dev tree” to something you can host safely. Adjust timelines to your team size. **§3** is the backlog of **system improvements and product development** (what to build and harden); **§§4–7** are phased **delivery** steps (security config, quality, deployment, go-live).

---

## 1. Should you delete all those test files?

**No — do not delete the Django app test modules.**

| What | Examples | Recommendation |
|------|----------|----------------|
| **Real tests** | `backend/modules/<app>/tests.py` (e.g. `modules/grade_center/tests.py`) | **Keep.** Run with `python manage.py test`. Grow these for regression safety. |
| **Ad-hoc scripts** | `backend/tests/` (`test_*.py`, `check_*.py`, seeds, etc.) | **Do not mass-delete on day one.** Many encode one-off knowledge. Prefer **delete only** scripts you are sure are obsolete; keep the rest in `backend/tests/` (see `backend/tests/README.md`). |
| **Data / secrets** | `.env` (gitignored), old keys in git history | Rotate secrets for production even if you use `.env` now. |

**Why not delete everything:** you lose quick diagnostics and any behavior encoded in scripts before CI and proper tests cover the same flows.

---

## 2. Phase A — Stabilize the repo (1–3 days)

- [x] **Single Python env:** one **`backend/venv/`** per machine; install everything with **`pip install -r backend/requirements.txt`**. On Windows: `powershell -ExecutionPolicy Bypass -File backend/setup_venv.ps1`, then `.\venv\Scripts\Activate.ps1` in new shells (or `python -m venv venv` + `pip install -r requirements.txt`). CI images should use the same file in a non-interactive `pip install -r` step.
- [x] **`.env` everywhere:** `backend/.env.example` is the template; `backend/.env` is used locally and is **gitignored** (see `backend/.gitignore`). **New clone:** from `backend/`, run `copy .env.example .env` (cmd) or `Copy-Item .env.example .env` (PowerShell), then set secrets and DB values. Never commit `.env`.
- [x] **Root `.gitignore`:** repo root **`.gitignore`** covers Python bytecode, `venv/`, SQLite, **`.env`**, **`backend/media/`**, IDE metadata (`.idea/`, `*.iml`), OS junk, caches, and coverage. Adjust the commented **`.vscode/`** line if your team commits shared VS Code settings. Nested **`frontend/.gitignore`** and **`backend/.gitignore`** still apply under those trees.
- [ ] **Script hygiene:** ad-hoc runners live in **`backend/tests/`** (not Django’s per-app `tests.py`). Run them as `cd backend` then `python -m tests.check_server` (see `backend/tests/README.md`). Add one-line docstrings at the top of scripts you keep.
- [ ] **Baseline:** `python manage.py check` and `python manage.py test` — note failures and fix or skip with tickets.

---

## 3. System improvements, gaps & product development

Use this as a **living backlog** of what to improve and what to build next, separate from “how we ship” (Phases 4–7). Prioritize with your stakeholders (faculty, IT, students).

### 3.1 Security & privacy (must-harden for real deployment)

| Gap | Why it matters | Direction |
|-----|----------------|-----------|
zrd5xdr5tfdxrt5
| **No DRF default permission** | New views can accidentally stay `AllowAny`. | Set `DEFAULT_PERMISSION_CLASSES` to authenticated; whitelist only login, token refresh, and truly public flows (e.g. guest code validation). |
| **JWT lifetimes** | Long-lived access tokens increase impact of token theft. | Shorter access TTL in production; optional refresh rotation + blacklist. |
| **Guest code endpoint** | Public validation is correct for UX; needs abuse controls. | Rate limits, logging, strong code entropy, optional CAPTCHA under load. |
| **Digital vault visibility** | All authenticated users share the same visible vault slice. | Decide policy: keep school-wide archive **or** add team-/role-scoped visibility and filters in the API. |
| **CORS / TLS** | Dev middleware assumes private HTTP origins. | Production CORS allowlist + HTTPS; do not rely on `DEBUG` CORS hacks on the public internet. |
| **Media delivery** | `/media/` with `DEBUG` is not a production pattern. | Authenticated downloads or short-lived signed URLs behind your proxy. |

### 3.2 Platform reliability & operations

- **Observability:** structured application logging, error tracking (e.g. Sentry), and log retention policy.
- **Health beyond `check`:** lightweight `/health/` (DB + disk) for load balancers and Kubernetes, without leaking internals.
- **Uploads & heavy work:** large PDFs / ML extraction can block workers — consider async jobs (RQ, Celery, or managed queue) and file size limits.
- **Performance:** review N+1 queries on hot list endpoints; add indexes for common filters (teams, schedules, vault search).
- **Rate limiting** at reverse proxy or API gateway for login and public-ish endpoints.

### 3.3 Product & UX development (feature work)

- **Flutter client:** consistent loading/error/offline messaging; finalize **production API base URL** (no hard-coded LAN IPs for release builds); review `BridgeService` (port 8080) — remove, replace, or document for production.
- **Role completeness:** walk each role (student, faculty, panelist, admin, uploader) end-to-end against acceptance criteria; fix gaps in navigation and permissions in the UI.
- **Scheduling & board:** edge cases (conflicts, cancellations, panel reassignment, timezone display for `USE_TZ`).
- **Grading & rubrics:** clearer states (draft / published / locked), exports for records, and adviser vs panel weighting communicated in UI.
- **Reporting:** CSV/PDF exports where faculty need official records; optional email notifications for deadlines and defense changes.
- **Accessibility & i18n:** keyboard navigation, contrast, screen reader labels; English-first is fine short-term — plan if you need Filipino or other locales later.

### 3.4 Data, academic lifecycle & governance

- **Semesters / rollover:** scripts like academic rollover should be documented, idempotent, and run in staging first.
- **Retention:** how long to keep submissions, logs, and guest codes; GDPR-style deletion if you store personal data beyond the institution’s needs.
- **Backups:** automated PostgreSQL backups, tested restore procedure, and separation of **media** backups from DB.
- **Media layout (local / S3):** PIT archive PDFs live under `backend/media/vault_entries/pit/{year-level}/{academic_year}/{MM}/` (see `VaultEntry` + `relocate_vault_files`). Capstone “digital vault” deliverables stay under `backend/media/deliverables/` until an optional unify; Repository Audit and Digital Vault merge both in the API (filter by type in the UI).
- **Integrity:** audit trail for who changed grades, schedules, or rubric weights (beyond current domain models if missing).

### 3.5 Engineering quality (how the codebase matures)

- **Test coverage:** grow `modules/*/tests.py`; port the most valuable flows from `backend/tests/` into proper `TestCase`s.
- **CI:** block merges on `manage.py check` + `test` (Phase 5); add optional lint/format (`ruff`, `black`).
- **API contract:** optional OpenAPI schema (`drf-spectacular` or similar) for Flutter and future clients; consider `/api/v1/` when breaking changes are unavoidable.
- **Dependency hygiene:** periodic `pip audit` / Dependabot; pin or lockfile for production images once you are happy with versions.

### 3.6 Documentation & onboarding

- **Onboarding:** one page for “clone → venv → `.env` → migrate → runserver → Flutter `dart-define`” (this doc + `SYSTEM_OVERVIEW.md` are a start).
- **Runbooks:** who provisions admins, how to rotate secrets, where backups live (ties to Phase 7).
- **Architecture decisions:** short ADRs only when you choose something non-obvious (e.g. job queue, hosting provider).

---

## 4. Phase B — Security & configuration (high priority before any shared host)

From the earlier audit, tackle in this order:

- [ ] **Production settings:** `DJANGO_DEBUG=False`, strong `DJANGO_SECRET_KEY`, non-default `POSTGRES_PASSWORD`, tight `DJANGO_ALLOWED_HOSTS`.
- [ ] **HTTPS:** terminate TLS at reverse proxy (nginx, Caddy, cloud load balancer); update CORS strategy for real origins (not only dev `LocalCorsMiddleware`).
- [ ] **Lock down public API reads:** teams list, rubrics list, team documents list — require authentication (and refine by role) before exposing the API beyond localhost.
- [ ] **DRF default:** set `DEFAULT_PERMISSION_CLASSES` to `IsAuthenticated`; explicitly `AllowAny` only on login, refresh, and truly public endpoints (e.g. guest code validation).
- [ ] **JWT:** shorten access token lifetime for production; consider refresh rotation + blacklist if sessions matter.
- [ ] **Media:** do not rely on `DEBUG` media serving in production — use authenticated downloads or signed URLs behind your proxy.

---

## 5. Phase C — Quality & automation (ongoing)

- [ ] **CI pipeline** (GitHub Actions / GitLab CI): on each push — install deps, `manage.py check`, `manage.py test`, optional lint (`ruff` / `flake8`).
- [ ] **Migrate valuable `test_*.py` logic** into `app/tests.py` or `tests/` package so `manage.py test` covers critical flows (login, one happy path per major domain).
- [ ] **Database:** production PostgreSQL backups, migration strategy (`migrate` in deploy step).
- [ ] **Frontend:** `flutter build apk` / `flutter build web` in CI or release docs; store build artifacts or deploy to static hosting as you choose.

---

## 6. Phase D — Deployment architecture (pick one path)

**Typical small-team stack:**

1. **App server:** Gunicorn or uvicorn (ASGI only if you need it) running Django WSGI.
2. **Reverse proxy:** nginx (or managed equivalent) — TLS, gzip, static/media rules.
3. **Database:** managed PostgreSQL or a hardened VM install.
4. **Secrets:** environment variables or a secret manager — not files on disk in the image if avoidable.

**Checklist:**

- [ ] `collectstatic` if you serve Django admin/static via WhiteNoise or nginx.
- [ ] Health endpoint or `manage.py check` in container `CMD` smoke step.
- [ ] Logging: stdout JSON or structured logs for the host environment.

---

## 7. Phase E — Go-live & post-deploy

- [ ] Smoke test: login, one student flow, one admin flow, one file upload/download.
- [ ] **Rotate** any secret that ever lived in git history.
- [ ] Document **ops runbook:** backup/restore, how to run migrations, who gets admin accounts.

---

## Suggested next actions (this week)

1. **Run** `python manage.py test` (from `backend/` with venv active) and fix the first failing test or gap you care about.
2. **Plan** Phase 4 (security): decide hosting (VPS vs PaaS) and schedule tightening API permissions + `DEBUG=False` for a staging environment first.
3. **Pick 2–3 items** from **§3 System improvements** (e.g. public API lockdown + vault policy + CI) and turn them into tracked tickets with owners.

---

*Last updated: 2026-05-13*
