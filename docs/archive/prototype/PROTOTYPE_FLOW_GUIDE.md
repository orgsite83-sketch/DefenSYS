# DefenSYS Interactive Prototype — Flow Guide

## How to Run

### Web Prototype + Bridge Server (Recommended)

The **Bridge Server** is a Python API that connects the Web and Flutter apps, enabling real-time role sync, guest code validation, and live evaluation data flow.

```bash
# Start the Bridge Server (serves web files + API endpoints on port 8080)
cd prototype
python mock_server.py

http://localhost:8080/app/

```

Then open: `http://localhost:8080/templates/auth/login_screen.html`

### Flutter Mobile App
 
```bash
# In a separate terminal
cd user
flutter pub get
flutter run -d chrome     # or: flutter run -d <device_id>
```

> **Important:** The Bridge Server (`mock_server.py`) must be running for the Web ↔ Flutter sync to work. If it's offline, both apps fall back to local data gracefully.

### Alternative (Web Only, No Bridge)

```bash
cd prototype
python -m http.server 8080
```

---

## Template Structure

All templates are now organized into subfolders under `templates/`:

```
templates/
  auth/                    login_screen.html
  dashboards/              admin, adviser, panelist, pit_lead, student, faculty_fallback
  evaluation_engine/       rubric_builder, grade_center, live_evaluation_board, peer_evaluation
  repository_and_analytics/ repository_audit, curriculum_analytics
  academic_management/     user_management, academic_periods, team_management, create_team,
                           defense_scheduler, defense_board, defense_stages,
                           student_academic_records, bulk_import, role_assignment, edit_user
```

---

## JS Utilities

| File | Purpose |
|------|---------|
| `js/mock-data.js` | Seed data + sessionStorage persistence (SEED_VERSION controls cache) |
| `js/prototype.js` | All screen handlers, MockDB logic, Guest Code generator |
| `js/nav.js` | Fetch-swap navigation + CSS/style injection |
| `js/sidebar.js` | Dropdown toggle logic |
| `js/rbac.js` | RBAC session management, route guards, element visibility filtering |
| `js/ml_classifier.js` | ML pipeline simulator + Chart.js DSS panel (Curriculum Analytics page) |
| `js/file_gatekeeper.js` | Regex filename validator for uploaded project files |
| `mock_server.py` | Python Bridge Server — serves web files + REST API for cross-platform sync |
| `mock_database.json` | Centralized JSON database (users, teams, schedules, guest codes) |

---

## Demo Credentials

Faculty and students log in using their **ID number as both username and password**.

| Who | Username | Password | Role | Lands on |
|-----|----------|----------|------|----------|
| Rowena Alcantara | `admin` | `admin123` | Admin | Admin Dashboard |
| Bernardo Quilang | `201` | `201` | Panelist + PIT Lead 3rd Year | PIT Lead Dashboard |
| Lourdes Tabañag | `202` | `202` | Panelist + Adviser | Adviser Dashboard |
| Danilo Estorque | `203` | `203` | Panelist | Panelist Dashboard |
| Maribel Cañete | `204` | `204` | PIT Lead 2nd Year | PIT Lead Dashboard |
| Efren Dalisay | `205` | `205` | No roles (empty state) | Faculty Fallback Dashboard |
| Clarisse Matugas | `2001` | `2001` | Student | Student Dashboard |
| Reymart Dagohoy | `2002` | `2002` | Student | Student Dashboard |
| Hazel Pañares | `2003` | `2003` | Student | Student Dashboard |
| Aldrin Cabugwas | `2004` | `2004` | Student | Student Dashboard |
| Trisha Lumayag | `2005` | `2005` | Student | Student Dashboard |

Wrong credentials → inline error message, no navigation.

> **RBAC note:** Login automatically routes to the correct role-specific dashboard. Faculty with no assigned roles (`205`) see a "No Roles Assigned Yet" empty state. Roles are driven by `facultyRoles` in MockDB and configurable via the Role Assignment page.

---

## Admin Flow

### 1. Login → Admin Dashboard
- 4 live stat cards: Active Students, Faculty Members, Active Teams, Scheduled Defenses
- Quick Actions panel: Manage Users, Schedule a Defense, Configure Rubrics, Defense Stages
- Upcoming Defenses panel: next scheduled slots from MockDB
- Active Capstone Teams table: filters to 3rd Year 2nd Sem → 4th Year 1st Sem only
  - Phase badges: Entry (3rd Yr 2nd Sem), Active (4th Yr 1st Sem), Extended (past deadline)
  - Extended teams show a dropdown: **A: Continue existing project** / **B: Reset & pursue new project**
- System Alerts: warns when extended teams exist, rubrics are unpublished, or no defenses scheduled

### 2. Academic Periods
- Sidebar → Academic Periods
- Click **Manage** on any school year → right panel loads that year's semesters
- Toggle a semester switch → active semester updates across the app; only one can be active at a time
- Click **+ Add Year** → modal with YYYY-YYYY format validation
- Click **+ Add Semester** → modal with fixed dropdown (1st Semester, 2nd Semester, Summer); validates no duplicates per year

### 3. User Management
- Sidebar → User Management → Users
- Filter cards (All Users / Faculty / Students) → filters table; counts are live from MockDB
- Role dropdown → filter by Administrator, Panelist, Adviser, PIT Lead, Student
- Search box → filters by ID, name, or email in real time; **Clear** resets
- System Role column shows dynamic role chips (PIT Lead + year, Adviser + phase, Panelist, etc.)
- Click **CSV Template** → downloads `defensys_users_template.csv`
- Click **Bulk Import CSV** → navigates to Bulk Import page
- Click **Generate Guest Code** → opens Guest Code modal (see below)
- Click **Add Single User** → modal to add a user; new row appears in table
- Click edit icon → navigates to Edit User profile page
- Click shield icon (faculty/admin rows only) → navigates to Role Assignment

#### Guest Panelist Code System
- **Generate:** Click Generate Guest Code button → modal with Guest Name + Defense Schedule dropdown → click **Generate & Save**
- Generates a random `DEF-XXXXXX` code (6-char alphanumeric)
- Code saved to: `localStorage`, `MockDB.guestTokens`, and `mock_database.json` (via bridge)
- Success state shows the code with a **Copy** button
- **Management Table:** Below the Users table, shows all generated guest codes
  - Columns: Code (monospace), Guest Name, Defense Schedule, Created date, Status, Action
  - Status:  Active or  Revoked
  - **Copy** button → copies code to clipboard
  - **Revoke** button → deactivates the code (synced to bridge server, prevents Flutter login)
  - Count badge shows "X active / Y total"
  - Empty state shown when no codes exist

### 4. Edit User
- Reached from the edit icon in User Management
- Pre-filled form: First Name, Last Name, Email, Role, Active checkbox
- Click **Save Changes** → updates MockDB, returns to User Management

### 5. Bulk Import Users
- Reached from Bulk Import CSV button on User Management
- Shows CSV format preview and Download Sample Template button
- Choose **Import Batch Type**: Student Batch or Faculty / General Users
- Student Batch shows extra options: Student Period Source, Target Semester (auto-selects active), Batch Year Level
- Preflight Review section updates live as you change dropdowns
- Drag & drop or click to select a `.csv` file
- Click **Import Users** → parses CSV, validates columns, skips duplicates, creates users in MockDB; Student Batch also creates Student Academic Records automatically
- Navigates back to User Management after successful import
- Sample file: `DefenSYS_design_copy/sample_import.csv` (students 3001–3008)

### 6. Role Assignment
- Reached from the shield icon in User Management
- Left panel: user profile card with name, email, ID, base role badge, account status
- Right panel: three role rows — Defense Panelist, PIT Lead, Project Adviser
  - Each row highlights green when toggled on
  - PIT Lead expands a year-level dropdown when enabled
  - Project Adviser expands a capstone phase dropdown when enabled
- Click **Save Role Configuration** → roles saved to MockDB, RBAC session refreshed if user is currently logged in, assignment logged in history table

### 7. Student Teams
- Sidebar → User Management → Student Teams
- 5 stat filter cards: All Teams, Result Pending, Approved, Failed, Adviser Review
- Table columns: Project Title, Year Level, Team Result, Defense Context, Leader, Adviser, Members (progress bar), Action
- Click eye icon → team detail modal with member cards, adviser section, latest defense context, and Edit button

### 8. Create / Edit Team
- Enter project name and select level
- Type in student search → dropdown of matching students; click to add to roster (max 4)
- First student added becomes **Team Leader** (crown icon); others can be removed
- Adviser section appears for 4th Year Capstone and 3rd Year PIT levels
- Click **Save Group Configuration** → saved to MockDB → toast → back to Manage Teams

### 9. Student Academic Records
- Sidebar → User Management → Student Academic Records
- Table shows records with student name, school year, semester, year level
- Search filters by name or ID
- Click **+ Add Record** → modal with student dropdown, school year (from MockDB), semester (updates based on selected year, auto-selects active), year level
- Click edit icon → Edit Record modal: update school year, semester, year level; Delete button requires confirmation
- Click **Rollover Preview** → "Coming Soon" toast

### 10. Defense Stages
- Sidebar → Scheduling → Defense Stages
- Info bar: Total Stages, Active count, "Scheduler uses active stages" badge
- Stage Directory table: Order badge, Name, auto-generated Code tag, Previous Stage, Status, Actions
- Click **Edit** → modal pre-filled with stage name and description
- Click **Deactivate / Activate** → toggles stage active state
- Click **Add Stage** → modal to create new stage
- Click **Defense Scheduler** button → navigates to scheduler

### 11. Defense Scheduler
- Sidebar → Scheduling → Defense Scheduler
- Step 1: choose Stage, Rubric, Date, Starting Time, Slot Duration, Room
- Right panel: Panel Set — search and select panelists; selected items highlight maroon with CSS classes
- Validation badges update live (Stage, Ready Teams, Blocked, Already Scheduled)
- Click **Generate Schedule Plan** → Step 2 panel appears with preview table of consecutive slots
- Remove individual slots with delete icon; rows renumber automatically
- Click **Save Schedule** → all slots saved to MockDB → navigates to Defense Board
- Click **Back** → returns to Step 1

### 12. Defense Board
- Sidebar → Scheduling → Defense Board
- Stat cards: Total Schedules, Upcoming, Completed — live from MockDB
- Filter by Stage, Status, or search by team/room
- Status badges: Scheduled (blue), Done (green), Cancelled (red)
- Click **New Schedule Run** → navigates to Defense Scheduler
- Click delete → removes schedule entry from MockDB, stat cards update

### 13. Rubric Engine
- Sidebar → Rubric Engine
- List view: stat cards (total rubrics, total criteria, weight config), alert banner, searchable table
- Table columns: Rubric Name, Scope (year level / semester / stage / eval type), Weight Distribution chip, Criteria count, Created By, Edit
- Click **Create Standard Rubric** → switches to form view
- Form: Rubric Name, Semester (auto-selects active), Year Level, Defense Stage, Evaluation Type
- Criteria table: Name, Description, Scale, Weight, Order — add/remove rows
- Click **Save as Draft** or **Publish & Lock Rubric** → saves to MockDB, returns to list

### 14. Grade Center (Admin)
- Sidebar → Grade Center
- Table shows teams with panel, adviser, peer scores and final grade
- Filter by Capstone/PIT and Status dropdowns
- Click **View Breakdown** → modal with per-criterion scores
- Click **Export Grading Sheet** → "Coming Soon" toast

### 15. Repository Audit
- Sidebar → Repository Audit
- Table shows mock files with status badges (Approved, Needs Revision, Failed/Hidden)
- Search → filters rows in real time
- Click  audit trail icon → modal with chronological event history
- Click  override icon → prompt for new status → badge updates in table + MockDB
- Pagination buttons → show/hide rows
- Click **Export ISO Audit Log** → "Coming Soon" toast

### 16. Curriculum Analytics
- Sidebar → Curriculum Analytics
- Trend stat cards (Most Adopted Framework, Top Mobile, Declining Technology)
- CSS bar chart with year filter → re-renders on change
- Year-over-year snapshot grid
- DSS suggestions panel with adoption breakdown legend
- **ML Document Classifier** panel:
  - Upload a `.txt`/`.pdf`/`.docx` or paste abstract text
  - Click **Run Classification** → 4-stage pipeline animates (Regex Validation → TF-IDF → Naive Bayes → Output)
  - Result shows: Domain, Confidence %, Top Keywords Detected
  - Filename is validated by `file_gatekeeper.js` before upload is accepted
- **Chart.js DSS Panel**:
  - 3-year tech stack trend chart (bar or line, toggle-able)
  - Curriculum Insights panel with AI-generated if/else recommendations (Python spike warning, Flutter shift, PHP decline)
- Click **Generate Curriculum Proposal** → "Coming Soon" toast

---

## Faculty Flow

Login routes to a role-specific dashboard automatically.

### No roles assigned (`205` / `205`) — Faculty Fallback Dashboard
- "No Roles Assigned Yet" empty state with warning note
- Admin must assign roles via Role Assignment page

### Adviser + Panelist (`202` / `202` — Lourdes Tabañag) — Adviser Dashboard
- Role chips: Panelist + Project Adviser
- My Advised Teams section with team status badges
- Grade Center card → navigates to grade entry

### Panelist only (`203` / `203` — Danilo Estorque) — Panelist Dashboard
- Grade Center card with Open Grade Center button
- My Schedule link (Coming Soon)

### Panelist + PIT Lead (`201` / `201` — Bernardo Quilang) — PIT Lead Dashboard
- PIT Lead scope boundary notice (stops at 3rd Year 1st Sem)
- PIT Teams table filtered to assigned year level
- Rubric Engine + Grade Center cards

### PIT Lead only (`204` / `204` — Maribel Cañete) — PIT Lead Dashboard
- PIT Lead 2nd Year scope notice
- PIT Teams table: Team PitNode + Team SmartLib
- Rubric Engine (2nd Year PIT rubrics) + Grade Center

### Faculty Grade Center
- Dynamic — shows teams based on logged-in faculty's roles
- Panelist: sees scheduled panel teams
- Adviser: sees advised teams
- PIT Lead: sees assigned year-level PIT teams
- Each team shows rubric criteria pre-filled with existing scores
- Submit → saves to MockDB, shows "Submitted" badge

---

## Student Flow

### 1. Login → Student Dashboard (`2001`–`2005`)
- Shows team name, project title, team result badge, latest defense context
- My Team and Digital Vault links → "Coming Soon" toast

### 2. Peer Evaluation
- Sidebar → Peer Evaluation
- Teammates listed with scoring criteria
- Edit scores → click **Submit Peer Evaluation** → saved to MockDB, toast shown

---

## Cross-Platform Bridge

The Bridge Server (`mock_server.py`) enables real-time synchronization between the Web Admin Dashboard and the Flutter Mobile App.

### Architecture
```
Web Admin (HTML/JS)  ←→  Python Bridge (port 8080)  ←→  Flutter Mobile (Dart)
                          ↕
                    mock_database.json
```

### API Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/api/users/<id>` | Fetch user profile + role (for login sync) |
| `POST` | `/api/assign-role` | Admin saves role changes → persists to JSON |
| `GET` | `/api/guest-code/<code>` | Flutter validates a guest panelist code |
| `POST` | `/api/guest-codes` | Web saves a newly generated guest code |
| `POST` | `/api/guest-codes/revoke` | Web revokes a guest code |
| `GET` | `/api/panelist-assignments/<id>` | Flutter fetches real team assignments for a panelist |

All endpoints include CORS headers (`Access-Control-Allow-Origin: *`).

### Data Sync Flows

**Role Assignment:**
1. Admin assigns "Panelist" to faculty `205` on the web
2. Web POSTs to `/api/assign-role` → `mock_database.json` updated
3. Faculty `205` logs in on Flutter → fetches from `/api/users/205` → routes to Panelist Dashboard

**Guest Panelist:**
1. Admin generates code `DEF-K9M2X7` for "Engr. Juan Dela Cruz" on web
2. Web POSTs to `/api/guest-codes` → saved to `mock_database.json`
3. Guest opens Flutter → taps "Guest Panelist Access" → enters `DEF-K9M2X7`
4. Flutter GETs `/api/guest-code/DEF-K9M2X7` → receives guest name → opens Panelist Dashboard
5. Profile shows: "Engr. Juan Dela Cruz" · Guest Panelist · DEF-K9M2X7

**Live Evaluation Data:**
1. Panelist logs in on Flutter as `201` (Bernardo Quilang)
2. Flutter GETs `/api/panelist-assignments/201`
3. Server finds all schedules where `201` is in `panelIds`, enriches with team data + member names
4. Flutter renders: Team DefenSYS, Team AgriNode — with real project titles and student names

---

## Flutter Mobile App

### Login Screen
- ID Number + Password fields (same credentials as web: `201`/`201`, `2001`/`2001`, etc.)
- **Sign In** button → syncs with bridge server to get latest role → routes to dashboard
- **Guest Panelist Access** button (amber/gold) → opens code entry dialog
  - Monospace input with `DEF-XXXXXX` hint
  - Validates against bridge server → if valid, skips Terms & goes to Panelist Dashboard
  - If invalid/revoked → red error snackbar

### Terms & Conditions
- 10-section scrollable terms document
- Checkbox + Agree/Disagree buttons
- Routes to role-appropriate dashboard with user data from bridge

### Student Dashboard (login as `2001`–`2005`)
- Profile shows real name from bridge (e.g., "Clarisse Matugas")
- 3 tabs: Team, Repository, Peer Eval

### Panelist Dashboard (login as `201`–`203`)
- **Live data from bridge** — shows real teams assigned to this panelist
- Loading spinner while fetching assignments
- 3 tabs: Assignments, Grade Sheet, Results
- Assignments: real team names, project titles, member names, defense dates
- Grade Sheet: scoring sliders for each criterion
- Profile sheet: shows real faculty name and ID from bridge

### Dev Panelist / PIT Lead Dashboard (login as `204`)
- Same as Panelist but scoped to PIT teams
- Also fetches real assignments from bridge

### Key Flutter Files

| File | Purpose |
|------|---------|
| `lib/services/bridge_service.dart` | API client for all bridge communication |
| `lib/screens/login_screen.dart` | Login + Guest Access dialog |
| `lib/screens/panelist_dashboard.dart` | Panelist UI with live bridge data |
| `lib/screens/student_dashboard.dart` | Student UI with bridge profile |
| `lib/screens/dev_panelist_dashboard.dart` | PIT Lead UI with bridge data |
| `lib/screens/terms_agreement_screen.dart` | Terms gate, passes userData to dashboards |

---

## RBAC System (`rbac.js`)

### Role Constants
`ROLES.ADMIN`, `ROLES.PIT_LEAD`, `ROLES.ADVISER`, `ROLES.PANELIST`, `ROLES.STUDENT`, `ROLES.REPO_ASSISTANT`, `ROLES.GUEST`

### Route Guard
```html
<script src="../../js/rbac.js"></script>
<script>enforcePageClearance(['ADMIN']);</script>
```
Redirects to login if the session role doesn't match. Admin dashboard is already protected.

### Element-Level Hiding
```html
<button data-role-access="ADMIN, PIT_LEAD">Delete Rubric</button>
```
Elements with `data-role-access` are automatically hidden on `DOMContentLoaded` for unauthorized users.

### Guest Panelist Code (Cross-Platform)
The legacy URL-based `generateGuestToken()` in `rbac.js` is supplemented by the new **Guest Code System**:

1. Admin generates `DEF-XXXXXX` on web → saved to `localStorage` + `mock_database.json`
2. Guest enters code on Flutter → validated via bridge API → opens Panelist Dashboard
3. Admin can **Revoke** codes from the management table → bridge syncs → Flutter rejects the code

---

## File Gatekeeper (`file_gatekeeper.js`)

Enforces strict naming convention before files enter the AI pipeline.

**Required format:** `YearLevel.Course.Semester.pdf`

| Part | Rule |
|------|------|
| YearLevel | Single digit 1–4 |
| Course | Alphabetic only (IT, CS, PIT, CAPSTONE) |
| Semester | 1 or 2 only |
| Extension | `.pdf` (case-insensitive) |

Returns `true` on pass, or an exact rejection string (e.g. `"Upload Rejected: Year level must be between 1 and 4"`) for UI display.

---

## Capstone Timeline Logic

| Phase | Year Level | Semester | Handled By |
|-------|-----------|----------|------------|
| PIT | 1st Year | 1st + 2nd | PIT Lead |
| PIT | 2nd Year | 1st + 2nd | PIT Lead |
| PIT | 3rd Year | 1st only | PIT Lead |
| Capstone Entry | 3rd Year | 2nd | Admin |
| Capstone Active | 4th Year | 1st | Admin |
| Capstone Extended | 4th Year | 2nd+ | Admin (extension action required) |

Extended teams on the Admin Dashboard show a dropdown: **A: Continue existing project** or **B: Reset & pursue new project**.

---

## General Behavior Notes

- **Sidebar stays persistent** — only `.main-content` swaps on navigation; no full page reload
- **CSS injection** — page-specific `<style>` blocks and `<link>` stylesheets are injected automatically on navigation
- **MockDB persists within the session** — data stays until the tab is closed; closing the tab resets everything
- **Guest codes persist across sessions** — stored in `localStorage` (not sessionStorage)
- **Seed versioning** — bump `SEED_VERSION` in `mock-data.js` and hard refresh (`Ctrl+Shift+R`) to force a reseed
- **Coming Soon** — unimplemented buttons show a blue info toast
- **Bridge server is optional** — web runs standalone; Flutter features require the bridge
- **Graceful fallback** — if bridge is offline, both Web and Flutter fall back to local/hardcoded data

---

## Mock Data Reference

| Entity | Seeded Records |
|--------|----------------|
| Users — Admin | Rowena Alcantara (`200`) |
| Users — Faculty | `201` Bernardo Quilang (Panelist + PIT Lead 3rd Year), `202` Lourdes Tabañag (Panelist + Adviser), `203` Danilo Estorque (Panelist), `204` Maribel Cañete (PIT Lead 2nd Year), `205` Efren Dalisay (no roles) |
| Users — Students | `2001`–`2005` (4th Year team), `2006` (DefenSYS), `2007`–`2008` (AgriNode), `2009`–`2012` (BlockChain), `2013`–`2016` (PitNode), `2017`–`2020` (SmartLib) |
| Teams | DefenSYS (4th Yr Capstone, Approved), AgriNode (3rd Yr PIT, Pending), BlockChain (4th Yr Capstone, Failed), EcoTrack (3rd Yr Capstone Entry), NexaCore (4th Yr Extended), PitNode + SmartLib (2nd Yr PIT) |
| Defense Stages | Concept Proposal → Project Proposal → Final Defense (all active) |
| Schedules | Concept Proposal — DefenSYS (done), Project Proposal — AgriNode (scheduled), Final Defense — DefenSYS (scheduled) |
| Rubrics | 5 published: Concept Proposal (Panel/Adviser/Peer), Project Proposal (Panel), Final Defense (Panel), 2nd Year PIT (Panel) |
| Grades | DefenSYS: 93.7 (Published), AgriNode: Pending, BlockChain: 66.0 (Failed) |
| Audit Files | DefenSYS manuscript (Approved), AgriNode draft (Needs Revision), BlockChain proposal (Failed) |
| Academic Years | 2026-2027 (1st Semester active), 2025-2026, 2024-2025 |
| Student Academic Records | 20 records across all teams, all 2026-2027 1st Semester |
