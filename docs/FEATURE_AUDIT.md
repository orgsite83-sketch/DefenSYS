# DefenSYS Prototype — Feature Audit

> Comprehensive audit of all roles, modules, and features developed in the prototype.

---

## System Architecture

```
Web Admin (HTML/JS) ↔ Python Bridge Server (port 8080) ↔ Flutter Mobile (Dart)
                                  ↕
                          mock_database.json
```

- Bridge Server serves static web files + REST API on port 8080
- Flutter fetches assignments, validates guest codes, submits grades
- Web syncs role changes, vault archives, schedules to server
- Both apps fall back to local data if bridge is offline

---

## Roles & Access

| Role | Base | Access |
|---|---|---|
| **Admin** | `admin` | Full system access |
| **PIT Lead** | `faculty` + `pitLead` flag | PIT teams for assigned year level (1st–3rd Year 1st Sem) |
| **Adviser** | `faculty` + `adviser` flag | Advised Capstone teams only |
| **Panelist** | `faculty` + `panelist` flag | Grade Center, assigned teams |
| **Repo Assistant** | `faculty` + `repoAssistant` flag | Document upload only |
| **Student** | `student` | Mobile app only (Team, Repository, Peer Eval) |
| **Guest Panelist** | Guest code | Temporary panelist access via `DEF-XXXXXX` code |
| **Unassigned Faculty** | `faculty` (no flags) | Overview + Digital Vault only |

---

## Module 1 — Authentication & Access Control

| Feature | Status |
|---|---|
| Login with ID + Password | Done |
| Admin shortcut (`admin` / `admin123`) | Done |
| Dynamic user lookup from MockDB | Done |
| Student redirect to mobile-only message | Done |
| Role-based dashboard routing | Done |
| Multi-role gateway (role switcher) | Done |
| Guest panelist code login (Flutter) | Done |
| RBAC session (sessionStorage) | Done |
| Page-level route guards | Done |
| Element-level role visibility | Done |
| Logout clears session | Done |
| Reset Demo button | Done |

---

## Module 2 — Academic Period Management

| Feature | Status |
|---|---|
| Add school year (YYYY-YYYY format) | Done |
| Add semesters per school year | Done |
| Toggle active semester (one at a time) | Done |
| Active semester badge across all pages | Done |
| Read-only mode for inactive semesters | Done |

---

## Module 3 — User Management (Admin)

| Feature | Status |
|---|---|
| View all users with role chips | Done |
| Filter by role (Admin, Faculty, Student) | Done |
| Search by ID, name, email | Done |
| Bulk Import CSV (faculty + students) | Done |
| Add Single User modal | Done |
| Edit user details | Done |
| Role Assignment (Panelist, PIT Lead, Adviser) | Done |
| PIT Lead year level assignment | Done |
| Adviser capstone phase assignment | Done |
| Generate Guest Panelist Code | Done |
| Revoke guest code | Done |
| Admin profile + successor designation | Done |
| Transfer admin role to successor | Done |
| Sync users to server (Flutter access) | Done |

---

## Module 4 — Student Academic Records

| Feature | Status |
|---|---|
| View records with school year + semester + year level | Done |
| Filter by school year dropdown | Done |
| Filter by semester dropdown (defaults to active) | Done |
| Search by student name or ID | Done |
| Add record manually | Done |
| Edit record (year level, semester) | Done |
| Delete record | Done |
| Rollover Preview modal | Done |
| Promote / Retain / Drop per student | Done |
| Semester-aware promotion (1st → 2nd → next year) | Done |
| 4th Year extended retry (stays 4th Year) | Done |
| Capstone team auto-advance on rollover | Done |
| Archive old PIT schedules on rollover | Done |
| Duplicate check (year + semester) | Done |

---

## Module 5 — Student Teams

| Feature | Status |
|---|---|
| View all teams with stat cards | Done |
| Filter by level (Capstone, PIT by year, All) | Done |
| 2nd Semester hides 3rd Year PIT by default | Done |
| Search by project title, leader, adviser | Done |
| Team detail modal (members, adviser, defense context) | Done |
| Create team manually | Done |
| Edit team (name, level, members, adviser) | Done |
| Import teams via CSV (with adviser_id column) | Done |
| CSV template download | Done |
| Duplicate check (name + level) | Done |
| Active semester used for team semester field | Done |
| Capstone team advancement (3rd Yr 2nd Sem → 4th Yr 1st Sem) | Done |
| Extended capstone handling (4th Yr 2nd Sem → retry) | Done |
| Deliverable file count badge on team row | Done |
| Deliverable submissions view in team modal | Done |

---

## Module 6 — Defense Stages

| Feature | Status |
|---|---|
| Default stages seeded (Concept Proposal, Project Proposal, Final Defense) | Done |
| Per-stage deliverable checklist (admin add/edit/delete; empty by default) | Done |
| Add custom stage | Done |
| Edit stage name + description | Done |
| Activate / Deactivate stage | Done |
| Previous stage chain display | Done |
| Stage order management | Done |

---

## Module 7 — Rubric Engine

| Feature | Status |
|---|---|
| List all rubrics (name, scope, evaluation type, status; no weight column) | Done |
| Filter by Capstone / PIT scope | Done |
| Search by rubric name or academic year | Done |
| Create rubric (Scope Capstone/PIT + Semester + Evaluation Type + Defense Stage for Capstone) | Done |
| Add/remove criteria rows | Done |
| Scale options (5-Point, 10-Point, 100-Point) | Done |
| Save as Draft | Done |
| Publish and Lock Rubric | Done |
| Edit published rubric | Done |
| Weight Config modal (Capstone: via Defense Stages) | Done |
| PIT rubrics: criteria only; no weight column (split on Defense Scheduler per event) | Done |
| PIT Lead: no defense stage; no adviser eval or weight slot; event name only on scheduler | Done |
| PIT Lead: hides Adviser eval type | Done |
| Admin: Scope dropdown on create/edit; inherits PIT from list filter | Done |
| Demo: Seed Rubrics (Panel + Adviser + Peer for Project Proposal + Final Defense) | Done |

---

## Module 8 — Defense Scheduler

| Feature | Status |
|---|---|
| Step 1: Stage, Rubric, Date, Time, Room, Slot Duration (date/time calendar pickers) | Done |
| Panel Set search + selection | Done |
| Validation badges (Stage, Ready Teams, Blocked, Scheduled) — Capstone only | Done |
| Ready Teams check (endorsement-based for Capstone) | Done |
| PIT Step 1: no readiness/blocked badge strip (all eligible PIT teams schedulable) | Done |
| Generate Schedule Plan → Step 2 preview | Done |
| Remove individual slots | Done |
| Confirm and save schedule | Done |
| Manual Schedule Form | Done |
| Existing Schedules view | Done |
| PIT Lead: event name instead of stage | Done |
| PIT Step 1: event name + panel rubric + peer rubric + panel%/peer% (`PitEventGradingConfig`) | Done |
| PIT event config lookup (prefill weights/rubrics for existing event) | Done |
| Sync schedules to server (Flutter access) | Done |
| Mobile panelist: `panelist-assignments` returns scope, event weights, panel rubric per schedule | Done |

---

## Module 9 — Defense Board

| Feature | Status |
|---|---|
| View all schedules with stat cards | Done |
| Filter by stage, status, search | Done |
| Status badges (Scheduled, Done, Cancelled, Archived) | Done |
| Delete schedule | Done |

---

## Module 10 — Grade Center (Admin)

| Feature | Status |
|---|---|
| All teams table (Panelist, Adviser, Peer, Final Grade, Status) | Done |
| Filter by year level and status | Done |
| Auto-sync grades from server on load | Done |
| Peer column reads peerPerStudent from server | Done |
| Final grade calculation (Panel + Adviser + Peer weights) | Done |
| View Breakdown modal (per-criterion scores) | Done |
| Published / Pending / Awaiting Peers status badges | Done |
| Demo: Auto-Fill Capstone Grades (adviser + peer) | Done |
| Export Grading Sheet button | Done |

---

## Module 11 — PIT Grade Center (PIT Lead)

| Feature | Status |
|---|---|
| Scoped to PIT Lead's assigned year level | Done |
| Event-based view (select defense event) | Done |
| Per-team: panelist score + peer per member | Done |
| Expand members row | Done |
| View Breakdown modal | Done |
| Auto-sync grades from server | Done |
| Export Grading Sheet | Done |
| Demo: Auto-Fill Peer Evals | Done |

---

## Module 12 — Capstone Deliverables (Adviser)

**Runtime policy:** Each defense stage’s required deliverables come only from `StageDeliverable` rows configured in **Defense Stages** (admin UI). Fresh installs and cleared stages start **empty**; there is no hardcoded fallback checklist at upload/list time.

| Feature | Status |
|---|---|
| Deliverable Submissions modal per team | Done |
| Stage tabs (Concept Proposal, Project Proposal, Final Defense) | Done |
| Pre-Defense Requirements section (D1–D14) | Done |
| Post-Defense Vault Submissions section (D4.1, D10, D15–D19) | Done |
| Vault section locked until defense is done | Done |
| Upload file per deliverable (simulated — stores filename + metadata) | Done |
| Replace / Remove uploaded file | Done |
| Endorse for Defense (activates when all required uploaded) | Done |
| Vault items auto-added to repository on upload | Done |
| Sync deliverable files to server | Done |
| Demo: Auto-Fill Deliverables button | Done |
| View Team modal (grades + member breakdown) | Done |

---

## Module 13 — Repository Audit (Admin)

| Feature | Status |
|---|---|
| Unified view: PIT + Capstone deliverables | Done |
| Filters: Type, Team, Stage, Year Level, AY, Status, Semester | Done |
| PIT entries: filename, course, semester, status | Done |
| Capstone entries: deliverable label, team, stage | Done |
| Status badges: Pending AI, Pre-Defense, Vault Submission, Approved | Done |
| Override status (PIT only) | Done |
| Audit trail button | Done |
| Export CSV | Done |
| Demo Fill modal (PIT by year level + Capstone by stage) | Done |
| PIT fill works without imported teams (uses sample data) | Done |

---

## Module 14 — PIT Repository Audit (PIT Lead)

| Feature | Status |
|---|---|
| Scoped to PIT Lead's year level | Done |
| Upload Deliverable modal (batch PDF upload) | Done |
| Filename gatekeeper validation | Done |
| Team auto-matching from filename | Done |
| File preview with match status | Done |
| Remove file from preview | Done |
| Upload to vault + server sync | Done |
| Classify button (brain icon) → marks file as Approved | Done |
| Export Log | Done |
| Filters: Status, Academic Year, Semester | Done |

---

## Module 15 — Digital Vault (All Roles)

| Feature | Status |
|---|---|
| Read-only view of published deliverables | Done |
| PIT files (all years 1st–3rd Year 1st Sem) | Done |
| Capstone visible: D4.1, D10, D17, D18, D19 | Done |
| Capstone restricted: D15 (source code), D16 (full manuscript) | Done |
| Filter: Type, Year Level, Stage, Academic Year | Done |
| Search by filename, team, deliverable | Done |
| Secure viewer sheet (read-only notice) | Done |
| Dynamic AY dropdown from real data | Done |
| Accessible by: Admin, Faculty, Student | Done |

---

## Module 16 — Curriculum Analytics (Admin)

| Feature | Status |
|---|---|
| Trend stat cards (most/least uploaded tech, top AY) | Done |
| Capstone Tech Stack Distribution bar chart | Done |
| Year-over-year snapshot grid | Done |
| DSS System Suggestions panel | Done |
| Adoption Breakdown legend | Done |
| Tech Stack Adoption 3-Year Trend (Chart.js, bar/line toggle) | Done |
| Curriculum Insights panel | Done |
| ML Document Classifier (Naive Bayes + TF-IDF simulation) | Done |
| 4-stage pipeline animation | Done |
| Domain classification + confidence % + keywords | Done |
| Similar Projects in Vault search | Done |
| Generate Curriculum Proposal button | Done |

---

## Module 17 — Flutter Mobile App

### Student
| Feature | Status |
|---|---|
| Login with student ID | Done |
| Team tab (team info, members, adviser, schedule) | Done |
| Repository tab (browse vault, filter by AY, search) | Done |
| Peer Eval tab (score teammates, submit + lock) | Done |
| Edit profile | Done |

### Panelist
| Feature | Status |
|---|---|
| Login with faculty ID | Done |
| Guest code login | Done |
| Assignments tab (real teams from server, isGraded flag) | Done |
| Grade Sheet tab (sliders per criterion, post grades; panel rubric fixed per schedule, no rubric picker) | Done |
| Results tab (cached on login, no reload) | Done |
| Posted badge locks grade sheet | Done |
| Grades sync to server on submit | Done |

### PIT Lead (Dev Panelist)
| Feature | Status |
|---|---|
| Same as Panelist scoped to PIT teams | Done |

---

## API Endpoints Summary

### GET
| Endpoint | Purpose |
|---|---|
| `/api/users/<id>` | User profile + role |
| `/api/sync-pull` | Full DB sync (rate-limited 3s) |
| `/api/vault` | Vault archives |
| `/api/grades` | All grades |
| `/api/panel-results/<id>` | Panelist results |
| `/api/peer-grades/<teamId>` | Peer grades for team |
| `/api/student-data/<id>` | Student team + grades |
| `/api/guest-code/<code>` | Validate guest code |
| `/api/defense/schedules/panelist-assignments/` | Mobile panelist teams + scope-aware grade weights |

### POST
| Endpoint | Purpose |
|---|---|
| `/api/reset` | Wipe DB to seed defaults |
| `/api/users` | Create/update user |
| `/api/assign-role` | Save role changes |
| `/api/submit-grades` | Panelist or adviser grades |
| `/api/submit-peer-grade` | Student peer eval |
| `/api/sync-peer-grades` | Admin demo-fill peer data |
| `/api/sync-schedules` | Push schedules + teams |
| `/api/sync-peer-eval` | Toggle peer eval setting |
| `/api/vault/sync` | Push vault archives |
| `/api/guest-codes` | Create guest code |
| `/api/guest-codes/revoke` | Revoke guest code |

---

## Capstone Deliverables

| ID | Name | Stage | Type |
|---|---|---|---|
| D1 | Advisers Acceptance Form | Concept Proposal | Pre-Defense |
| D2 | Nomination of Panel Members | Concept Proposal | Pre-Defense |
| D3 | Approved Concept Hearing Form | Concept Proposal | Pre-Defense |
| D4 | Concept Paper and Pitch Deck | Concept Proposal | Pre-Defense |
| D5 | Signed Minutes (Concept) | Concept Proposal | Pre-Defense |
| D4.1 | Approved Concept Paper | Concept Proposal | Vault |
| D6 | Weekly Accomplishment Report | Project Proposal | Pre-Defense |
| D7 | Chapter 1 | Project Proposal | Pre-Defense |
| D8 | Chapter 2 | Project Proposal | Pre-Defense |
| D9 | Chapter 3 | Project Proposal | Pre-Defense |
| D11 | Approved Proposal Defense Form | Project Proposal | Pre-Defense |
| D12 | Signed Minutes (Proposal) | Project Proposal | Pre-Defense |
| D13 | Signed Matrix of Revision | Project Proposal | Pre-Defense |
| D10 | Chapters 1–3 (Complete) | Project Proposal | Vault |
| D14 | Final Manuscript (Chapters 1–3) | Final Defense | Pre-Defense |
| D15 | Software System & Source Code | Final Defense | Vault (Restricted) |
| D16 | Full-Length Technical Manuscript | Final Defense | Vault (Restricted) |
| D17 | 7-Page Executive Journal | Final Defense | Vault |
| D18 | Project Poster | Final Defense | Vault |
| D19 | Promotional Video | Final Defense | Vault |

---

## Demo Auto-Fill Features

| Button | Location | What it does |
|---|---|---|
| Reset Demo | Login page | Wipes all data, restores seed |
| Demo: Seed Rubrics | Rubric Engine | Creates 6 rubrics (Panel+Adviser+Peer × 2 stages) |
| Demo: Auto-Fill Deliverables | Adviser Dashboard | Fills all pre-defense docs for advised teams |
| Demo: Auto-Fill Peer Evals | PIT Grade Center | Generates peer scores for all PIT teams |
| Demo: Auto-Fill Capstone Grades | Admin Grade Center | Fills adviser grades + peer evals for Capstone |
| Demo Fill (PIT) | Repository Audit | Adds sample PIT files (works without teams) |
| Demo Fill (Capstone) | Repository Audit | Fills deliverables by stage with endorse option |
| Classify (brain icon) | PIT Repository Audit | Marks file as Approved (simulates ML) |

---

## Grade Weight Configuration

| Program | Panel | Adviser | Peer |
|---|---|---|---|
| PIT (1st–3rd Year 1st Sem) | 80% | 0% | 20% |
| Capstone (3rd Year 2nd Sem+) | 50% | 30% | 20% |

Pass threshold: **≥ 75**

---

*Generated: April 2026 · DefenSYS Prototype v1.0*
