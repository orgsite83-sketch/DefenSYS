# DefenSYS Demo Guide

> **Local demo only** — not a production install guide. See [DEPLOYMENT.md](DEPLOYMENT.md) for go-live.

---

## Start Everything

**Terminal 1 — Django API:**
```powershell
cd backend
python manage.py runserver 0.0.0.0:8000
```

**Terminal 2 — Flutter (web or device):**
```powershell
cd frontend
flutter run -d chrome
# Android emulator (Django on host PC):
# flutter run --dart-define=DEFENSYS_ANDROID_EMULATOR=true
# Physical phone on Wi‑Fi (uses LAN IP in api_config.dart):
# flutter run --dart-define=DEFENSYS_ANDROID_EMULATOR=false
```

**Browser (Flutter web):** use the URL printed by `flutter run` (typically `http://localhost:<port>/`).

Mobile panelist and student flows call **Django on port 8000** only (no `mock_server.py`).

**Android emulator / phone:** add `10.0.2.2` (emulator → host) and your PC LAN IP to `DJANGO_ALLOWED_HOSTS` in `backend/.env`, then restart `runserver`. Without `10.0.2.2`, login returns an HTML error page and the app shows a connection/parse error.

---

## Demo Flow

### 0. Bootstrap admin
Set env vars and run once (see [DEPLOYMENT.md](DEPLOYMENT.md)), or use an existing admin account.

---

### 1. Setup (Admin)
1. **Academic Periods** → Add `2026-2027` → Add `1st Semester` → toggle ON
2. **Users** → Bulk Import CSV → `sample_file/demo_faculty_import.csv`
3. **Role Assignment** → assign Adviser + **PIT Lead (3rd Year)** to **Ricardo Fontanilla**, plus Panelist roles as needed
4. **Users** → Bulk Import CSV → `sample_file/demo_students_3rd_year_import.csv` (4 students, Student Batch, 3rd Year)
5. If you previously imported 12 students: run `python manage.py remove_extra_demo_students` in `backend/` (drops 4085–4092, keeps 4081–4084)

---

### 2. PIT Phase — 3rd Year 1st Semester
1. Log in as **PIT Lead** faculty (e.g. Ricardo Fontanilla) → **Student Teams** → Bulk Import → `sample_file/demo_teams_3rd_year_import.csv` (1 team, 4 students)
2. **Rubric Engine** → Create rubric (Panel, 1st Semester, select stage)
3. **Defense Scheduler** → Set up run → Generate plan → Confirm
4. **Flutter app** → Log in as panelist → Grade teams → Post grades
5. **Grade Center** → Verify grades synced (Published)
6. Students submit peer evaluations in the mobile app when enabled; admins enter peer summaries in Grade Center as needed

---

### 3. Rollover to 2nd Semester
1. **Academic Periods** → toggle 1st Semester OFF → toggle 2nd Semester ON
2. **Student Academic Records** → Rollover Preview → Promote All → Create Records
3. **Student Teams** (admin) → PIT teams are hidden; list shows capstone teams only 

---

### 4. Capstone Phase — 3rd Year 2nd Semester
1. Log in as **admin** → **Student Teams** → Bulk Import → `sample_file/demo_teams_capstone_import.csv`
2. **Admin Dashboard** → Enable Peer Eval + Adviser Grading toggles
3. **Adviser Dashboard** → Deliverables → upload/endorse for Concept Proposal
4. **Defense Scheduler** → Select `Concept Proposal` stage → Ready Teams → Schedule
5. **Flutter app** → Panelist grades teams; students submit peer evals on mobile
6. **Grade Center** → Enter/sync panel and adviser scores; publish when complete

---

### 5. Repository & Analytics
1. **Repository Audit** → review and approve entries manually
2. **Digital Vault** → Students/faculty can browse published files
3. **Curriculum Analytics** → Tech Stack chart from vault data
4. **ML Classifier** → Paste abstract text → Run Classification

---

## Login Accounts

Use accounts from your CSV imports (faculty/student ID numbers). For a throwaway local DB only:

```powershell
python manage.py dev_create_40_students
```

(Prototype `student1`–`student40` — **not for production**.)

## Sample Files

All under [`sample_file/`](../sample_file/README.md) at the repo root.

| What | File |
|---|---|
| Faculty | `sample_file/demo_faculty_import.csv` |
| Students (4 per year) | `demo_students_{1st,2nd,3rd,4th}_year_import.csv` |
| PIT / capstone teams (1 per year) | `demo_teams_{1st,2nd,3rd,4th}_year_import.csv` |
| 3rd Year capstone (2nd sem) | `sample_file/demo_teams_capstone_import.csv` |
| Remove extra students (DB) | `python manage.py remove_extra_demo_students` |

In the app: **User Management** → Bulk Import → **Download Sample Template** (pick year). **Student Teams** → **CSV Template** (pick year for team CSV).

## Quick Fixes

| Problem | Fix |
|---|---|
| API errors | Confirm Django on port 8000; check `ApiConfig` / `--dart-define=DEFENSYS_API_HOST` |
| Button not clickable | Ctrl+Shift+R (hard refresh) |
| Grades not showing | Hard refresh Grade Center — use Sync if available |
| Phone cannot reach API | Same Wi‑Fi; `flutter run --dart-define=DEFENSYS_API_HOST=<PC-LAN-IP>` |
