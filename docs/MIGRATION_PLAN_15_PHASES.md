# DefenSYS 15-Phase Migration Plan (Module-by-Module)

This plan strictly follows a **1-to-1 mapping**. There are 15 modules in the Javascript `prototype/modules` folder, so there will be exactly **15 Phases**. 

## Vertical Slice Approach (Backend + Design Together)
The best practice is to do **both at the same time for a single module**. 
Instead of designing the entire Flutter app first without a backend (which would require rewriting a lot of the Flutter code later to connect it to the database), each phase below follows this workflow:
1. **Backend**: Build the Django App and API for that specific module.
2. **Design**: Build the Flutter UI (the design) for that specific module.
3. **Connect**: Wire them together so that specific feature is 100% finished before moving to the next.

---

## Current Migration Status

- **Phase 1: authentication_access_control** - Done for Django JWT login, custom user role flags, and Flutter login routing.
- **Phase 2: dashboards** - Done for Django-backed dashboard API contracts and Flutter Admin, Faculty, Student, and Panelist dashboard wiring.
- **Phase 3: academic_period_management** - Done for Django school year/semester APIs, single active-semester enforcement, dashboard active-semester wiring, and Flutter Admin Academic Periods management.
- **Phase 4: user_management** - Done for Django user CRUD, faculty role flags, CSV bulk import, admin-only API permissions, and Flutter Admin User Management.
- **Phase 5: student_academic_records** - Done for Django student academic record CRUD, active-semester options, rollover preview/confirm, student dashboard academic context, and Flutter Admin Student Records.
- **Phase 6: student_teams** - Done for Django team CRUD, member/leader/adviser assignment, bulk team import, dashboard team counts/context, student dashboard team data, and Flutter Admin Student Teams.
- **Phase 7: defense_stages** - Done for Django defense stage defaults, CRUD, code generation, activation, ordered previous-stage contracts, dashboard counts, and Flutter Admin Defense Stages.
- **Phase 8: rubric_engine** - Done for Django rubric/criteria CRUD, scope-aware Capstone/PIT validation, publish/lock, weight configuration, demo seed rubrics, dashboard counts, and Flutter Admin Rubric Engine.
- **Phase 9: defense_scheduler** - Done for Django defense schedule persistence, generate/confirm scheduling plans, panelist assignments, manual scheduling, dashboard schedule counts, and Flutter Admin Defense Scheduler.
- **Phase 10: defense_board** - Done for Django board listing/filtering, scoped PIT board views, schedule status actions, deletes, stat cards, and Flutter Admin Defense Board.
- **Phase 11: grade_center** - Done for Django grade record sync from schedules/teams, weighted final grade calculation, publish/result updates, rubric breakdowns, demo fill, dashboard counts, and Flutter Admin Grade Center tabs.
- **Important boundary**: Deliverable counts and vault archival remain placeholders until deliverables and vault modules are migrated.
- **Next phase**: Phase 12, `capstone_deliverables`.

---

## The 15 Phases

### Phase 1: authentication_access_control
- **Backend (Django)**: Create `authentication_access_control` app, User model, and `/api/login/` endpoint.
- **Design (Flutter)**: Design the Login Screen and connect it using Riverpod.

### Phase 2: dashboards
- **Backend**: Create `dashboards` app. APIs to fetch dashboard summary numbers.
- **Design**: Design the Flutter Admin, Faculty, and Student dashboard layouts.

### Phase 3: academic_period_management
- **Backend**: Create `academic_period_management` app. API for semesters.
- **Design**: Design the Flutter Academic Periods settings screen.

### Phase 4: user_management
- **Backend**: Create `user_management` app. APIs for CRUD operations on users.
- **Design**: Design the Admin Flutter screens for managing users and bulk importing.

### Phase 5: student_academic_records
- **Backend**: Create `student_academic_records` app.
- **Design**: Design the Flutter screens for viewing academic statuses.

### Phase 6: student_teams
- **Backend**: Create `student_teams` app. APIs for creating teams.
- **Design**: Design the Team Management screens in Flutter.

### Phase 7: defense_stages
- **Backend**: Create `defense_stages` app.
- **Design**: Design the screens for configuring PIT vs Capstone stages.

### Phase 8: rubric_engine
- **Backend**: Create `rubric_engine` app.
- **Design**: Design the Flutter screens for creating and editing grading rubrics.

### Phase 9: defense_scheduler
- **Backend**: Create `defense_scheduler` app.
- **Design**: Design the drag-and-drop calendar/scheduling UI in Flutter.

### Phase 10: defense_board
- **Backend**: Create `defense_board` app.
- **Design**: Design the live defense status board in Flutter.

### Phase 11: grade_center
- **Backend**: Create `grade_center` app.
- **Design**: Design the Grade Sheet and Overall Results tabs in Flutter.

### Phase 12: capstone_deliverables
- **Backend**: Create `capstone_deliverables` app (File uploads).
- **Design**: Design the file upload and viewing UI in Flutter.

### Phase 13: digital_vault
- **Backend**: Create `digital_vault` app.
- **Design**: Design the vault searching and browsing UI in Flutter.

### Phase 14: repository_audit
- **Backend**: Create `repository_audit` app.
- **Design**: Design the Flutter screen that shows GitHub/Drive repository statuses.

### Phase 15: curriculum_analytics
- **Backend**: Create `curriculum_analytics` app.
- **Design**: Design the charts and graphs UI in Flutter using `fl_chart`.
