# Design: DefenSYS Interactive Prototype

## Overview

The DefenSYS Interactive Prototype converts the existing static HTML/CSS design mockups in `DefenSYS_design_copy/` into a fully navigable, client-side prototype. No backend is required. All interactivity is driven by a JavaScript navigation controller and an in-memory mock data layer that persists state within a single browser session via `sessionStorage`.

The prototype must support three distinct user personas — Admin, Faculty, and Student — each with their own sidebar navigation, dashboard, and accessible feature set. A role-based login screen routes each persona to the correct starting screen. Every screen reachable from the sidebar must be wired; screens not yet designed show a "Coming Soon" toast instead of a dead link.

The goal is a demo-ready prototype that a stakeholder can click through end-to-end without hitting broken links or blank pages.

---

## Architecture

The prototype is a pure client-side single-page-style application built on top of the existing multi-file HTML structure. Rather than converting everything to a true SPA, the architecture uses a **shared navigation controller** that is loaded on every page and intercepts link clicks to swap the `main-content` region via `fetch` + `innerHTML` injection — the same pattern already sketched in `admin_dashboard.html`.

```
DefenSYS_design_copy/
├── templates/          ← existing screens (Admin role)
│   ├── login_screen.html
│   ├── admin_dashboard.html
│   ├── academic_periods.html
│   ├── user_management.html
│   ├── manage_teams.html
│   ├── create_team.html
│   ├── role_assignment.html
│   ├── rubric_engine.html
│   ├── evaluation_results.html
│   ├── repository_audit.html
│   └── curriculum_analytics.html
│
│   [NEW — to be created]
│   ├── faculty_dashboard.html
│   ├── faculty_grade_center.html
│   ├── student_dashboard.html
│   └── student_peer_eval.html
│
├── js/
│   ├── sidebar.js          ← existing dropdown logic (keep as-is)
│   ├── nav.js              ← NEW: navigation controller (fetch-swap + history)
│   ├── mock-data.js        ← NEW: shared mock data store (sessionStorage-backed)
│   └── prototype.js        ← NEW: per-screen interaction handlers
│
└── css/                    ← existing stylesheets (no changes needed)
```

### Navigation Controller (`nav.js`)

Intercepts all `<a>` clicks within `.nav-links` and `.main-content`. On click:
1. Fetches the target HTML file.
2. Extracts the `.main-content` innerHTML from the response.
3. Injects it into the current page's `.main-content`.
4. Updates `window.history.pushState`.
5. Re-runs `sidebar.js` dropdown logic and `prototype.js` screen init for the new content.
6. Marks the correct sidebar `<li>` as `active`.

The sidebar and shell (`<aside>`, top nav) are never replaced — only `.main-content` swaps. This keeps the sidebar persistent across navigation without a full page reload.

### Mock Data Layer (`mock-data.js`)

A single global `MockDB` object holds all prototype state. It is initialized from hardcoded seed data on first load and serialized to `sessionStorage` so state survives content swaps within the same tab session.

```
MockDB = {
  currentUser: { id, name, role },   // set at login
  academicPeriods: [...],
  users: [...],
  teams: [...],
  rubrics: [...],
  grades: [...],
  auditFiles: [...],
  analytics: { trends, chart, suggestions }
}
```

### Per-Screen Handlers (`prototype.js`)

After each content swap, `prototype.js` inspects the newly loaded content and attaches the correct event listeners for that screen. Each screen has a named `init` function (e.g., `initRubricEngine()`, `initGradeCenter()`). A dispatch map keyed by URL path routes to the right init function.

---

## Components and Interfaces

### 1. Login Screen

**File:** `login_screen.html`

The existing form `action` attribute points to `admin_dashboard.html`. This is replaced with a JS submit handler that reads the entered credentials against a hardcoded persona map:

| Username | Password | Role | Redirect |
|---|---|---|---|
| `admin` | `admin123` | Admin | `admin_dashboard.html` |
| `faculty` | `faculty123` | Faculty | `faculty_dashboard.html` |
| `student` | `student123` | Student | `student_dashboard.html` |

On successful match, `MockDB.currentUser` is set and the browser navigates to the role's home screen. On failure, an inline error message is shown beneath the form.

### 2. Admin Sidebar

**Screens:** All existing admin templates.

The Admin sidebar contains:
- Overview (admin_dashboard.html)
- Academic Periods
- User Management (dropdown: Users, Student Teams)
- Grade Center
- Rubric Engine
- Repository Audit
- Curriculum Analytics

The existing sidebar HTML and `sidebar.js` dropdown logic are kept intact. `nav.js` adds the fetch-swap behavior on top.

### 3. Admin Dashboard

**File:** `admin_dashboard.html`

Mock stats (142 active students, 38 vault archives, 12 grade locks) are rendered from `MockDB`. The "Configure Now" alert button navigates to `rubric_engine.html`.

### 4. Academic Period Management

**File:** `academic_periods.html`

- "Add Year" button opens an inline form row in the School Years table (mock only — appends a new row to the DOM and to `MockDB.academicPeriods`).
- "Add Semester" button does the same for the Semesters table.
- The active semester toggle fires a mock confirmation dialog, then updates the badge in the top nav to reflect the new active semester label.
- "Manage" buttons on past years show a "Coming Soon" toast.

### 5. User Management

**File:** `user_management.html`

- Role filter cards (All / Faculty / Students) filter the visible table rows client-side.
- Search input filters rows by name, ID, or email in real time.
- "Bulk Import CSV" button opens a mock file-picker dialog; on file selection it shows a success toast ("Import simulated — 12 users added") and appends mock rows to the table.
- "Add Single User" button opens an inline modal with name/email/role fields; on submit it appends a new row to the table and to `MockDB.users`.
- The edit icon in each row navigates to `role_assignment.html` with the user's ID in the URL hash.

### 6. Student Team Management

**File:** `manage_teams.html`

- Level filter dropdown filters table rows client-side.
- "Create New Team" navigates to `create_team.html`.
- Edit icon opens an inline edit state for the row (mock).
- Eye icon shows a team detail modal with members list.

**File:** `create_team.html`

- Project name and level fields are wired.
- Student search input filters `MockDB.users` (students only) and shows a dropdown of matches; clicking a result adds the student card to the roster.
- First student added is auto-assigned as Team Leader (crown icon).
- Faculty search filters `MockDB.users` (faculty only) for the adviser slot.
- "Save Group Configuration" appends the new team to `MockDB.teams`, shows a success toast, and navigates back to `manage_teams.html`.

### 7. Role Assignment

**File:** `role_assignment.html`

- The three toggle cards (Panelist, PIT Lead, Adviser) are wired to JS state.
- PIT Lead year-level select and Adviser capstone-phase select are enabled/disabled based on their toggle state.
- "Save Role Configuration" updates the matching user in `MockDB.users` and shows a success toast.
- The page reads the user ID from the URL hash to pre-populate the header with the user's name.

### 8. Rubric Engine

**File:** `rubric_engine.html`

- "Add New Criterion" appends a new criterion row to the criteria list.
- Criterion delete buttons remove the row.
- Max Score inputs update a live "Total Points" counter.
- "Save as Draft" saves the current rubric state to `MockDB.rubrics` with `status: 'draft'` and shows a toast.
- "Publish & Lock Rubric" sets `status: 'published'`, disables all inputs on the page, and shows a lock confirmation toast.
- "Import Previous Template" shows a "Coming Soon" toast.

### 9. Grade Center (Admin view)

**File:** `evaluation_results.html`

- Type filter (Capstone / PIT) and status filter (All / Fully Graded / Pending) filter table rows client-side.
- "View Breakdown" button opens a modal showing the per-criterion score breakdown for that team, drawn from `MockDB.grades`.
- "Export Grading Sheet" shows a "Coming Soon" toast.

### 10. Repository Audit & Digital Vault

**File:** `repository_audit.html`

- Search input and filter dropdowns filter the file table client-side.
- "View Audit Trail" (clock icon) opens a modal showing a mock timeline of file events (uploaded, revised, approved).
- "Override Status" (unlock/gavel icon) opens a confirmation dialog; on confirm it updates the row's status badge in the DOM and in `MockDB.auditFiles`.
- "Export ISO Audit Log" shows a "Coming Soon" toast.
- Pagination buttons are wired to show/hide mock page rows (client-side pagination of the mock data).

### 11. Curriculum Analytics

**File:** `curriculum_analytics.html`

- Trend cards and bar chart are rendered from `MockDB.analytics` on page load.
- DSS suggestion cards are rendered from `MockDB.analytics.suggestions`.
- "Generate Curriculum Proposal" shows a "Coming Soon" toast.
- Year filter dropdown re-renders the bar chart with a different mock dataset.

### 12. Faculty Dashboard & Grade Center

**Files:** `faculty_dashboard.html`, `faculty_grade_center.html` (new)

Faculty sidebar contains:
- Overview (faculty_dashboard.html)
- My Teams
- Grade Center
- Digital Vault

Faculty dashboard shows assigned teams and a "Submit Grades" CTA. The grade center flow lets the faculty panelist click into a team, see the rubric criteria, enter mock scores, and click "Submit Grades" — which updates `MockDB.grades` and shows a confirmation toast.

"My Teams" and "Digital Vault" show "Coming Soon" toasts.

### 13. Student Dashboard & Peer Evaluation

**Files:** `student_dashboard.html`, `student_peer_eval.html` (new)

Student sidebar contains:
- Dashboard
- My Team
- Peer Evaluation
- Digital Vault

Student dashboard shows the student's team name, project title, current team result (Pending / Approved / Failed), and latest defense context — all from `MockDB`.

Peer Evaluation screen shows a list of teammates with a rubric form per teammate. On submit it saves to `MockDB` and shows a confirmation toast.

"My Team" detail and "Digital Vault" show "Coming Soon" toasts.

### 14. Toast Notification System

A lightweight toast component is injected into the page shell once by `nav.js`. Any module can call `Toast.show(message, type)` where `type` is `'success'`, `'info'`, or `'warning'`. Toasts auto-dismiss after 3 seconds.

---

## Data Models

All data lives in `MockDB` (in-memory, `sessionStorage`-backed). These are plain JS objects — no schema enforcement.

### User
```js
{
  id: "FAC-2023-01",
  name: "Janice Doe",
  email: "j.doe@ustp.edu.ph",
  role: "admin" | "faculty" | "student",
  facultyRoles: {
    panelist: false,
    pitLead: false, pitLeadYear: null,
    adviser: false, adviserPhase: null
  },
  teamId: null  // for students
}
```

### AcademicPeriod
```js
{
  id: "ay-2026-2027",
  schoolYear: "2026-2027",
  semesters: [
    { id: "sem-1", label: "1st Semester", active: true },
    { id: "sem-2", label: "2nd Semester", active: false }
  ]
}
```

### Team
```js
{
  id: "team-defensys",
  name: "Team DefenSYS",
  projectTitle: "Capstone & PIT Management System",
  level: "4th Year Capstone",
  leaderId: "STU-2026-88",
  memberIds: ["STU-2026-88", "STU-2026-89", "STU-2026-90"],
  adviserId: "FAC-2023-01",
  status: "Pending" | "Approved" | "Failed"
}
```

### Rubric
```js
{
  id: "rubric-capstone-panel",
  level: "4th Year Capstone",
  evaluationType: "panel" | "adviser" | "peer",
  status: "draft" | "published",
  criteria: [
    { id: "c1", name: "System Functionality", maxScore: 40, description: "" },
    { id: "c2", name: "UI/UX Design", maxScore: 30, description: "" }
  ]
}
```

### GradeRecord
```js
{
  teamId: "team-defensys",
  panelist: { total: 46.5, max: 50, breakdown: [{ criteriaId, score }] },
  adviser:  { total: 28.0, max: 30 },
  peer:     { total: 19.2, max: 20 },
  finalGrade: 93.7,
  status: "published" | "pending"
}
```

### AuditFile
```js
{
  id: "file-001",
  title: "DefenSYS_Final_Manuscript.pdf",
  teamId: "team-defensys",
  version: "v3.0 (Final)",
  status: "approved" | "needs-revision" | "failed",
  lastModified: "Feb 28, 2026",
  auditTrail: [
    { date: "Jan 10, 2026", event: "Uploaded by Alyssa Gomez" },
    { date: "Feb 15, 2026", event: "Revised — v2.0 submitted" },
    { date: "Feb 28, 2026", event: "Approved by Admin" }
  ]
}
```

### Analytics
```js
{
  trends: [
    { label: "Most Adopted Framework", value: "Django (Python)", change: "+15%" },
    { label: "Top Mobile Technology",  value: "Flutter",         change: "+22%" },
    { label: "Declining Technology",   value: "Vanilla PHP",     change: "-18%" }
  ],
  chart: [
    { tech: "Django / Python", pct: 85 },
    { tech: "Flutter / Dart",  pct: 72 },
    { tech: "React / Next.js", pct: 60 },
    { tech: "Laravel / PHP",   pct: 35 }
  ],
  suggestions: [
    { type: "critical", title: "Curriculum Update Recommended", body: "..." },
    { type: "info",     title: "Infrastructure Shift Noticed",  body: "..." }
  ]
}
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Login routing correctness

*For any* valid (username, password) pair in the persona map, the login handler should set `MockDB.currentUser.role` to the matching role and redirect to that role's home screen.

**Validates: Requirements 1.1**

---

### Property 2: Invalid credentials do not navigate

*For any* credential pair not present in the persona map, the login handler should leave the current URL unchanged and render an error message in the DOM.

**Validates: Requirements 1.2**

---

### Property 3: Navigation swaps only main-content

*For any* sidebar link click, the DOM node reference of the `<aside>` sidebar element should be identical before and after the swap, while the `.main-content` innerHTML should differ.

**Validates: Requirements 2.1**

---

### Property 4: Active sidebar item tracks current screen

*For any* navigation action to a screen, exactly one `<li>` in `.nav-links` should carry the `active` class, and its descendant `<a>` href should match the navigated URL.

**Validates: Requirements 2.2**

---

### Property 5: Sidebar links are role-scoped

*For any* logged-in role, the set of `href` values in the sidebar should be a subset of the links defined for that role, and should contain no links from other roles' exclusive sets.

**Validates: Requirements 2.3**

---

### Property 6: Academic period toggle updates top-nav badge

*For any* semester toggle action that activates a semester, the text content of the `.active-sem` badge in the top nav should equal the label of the newly activated semester.

**Validates: Requirements 4.1**

---

### Property 7: Add school year round-trip

*For any* new school year label submitted via the inline form, `MockDB.academicPeriods` should contain an entry with that label, and the School Years table should have one more row than before the submission.

**Validates: Requirements 4.2**

---

### Property 8: User table role filter correctness

*For any* role filter selection (All / Faculty / Students), every visible table row's role badge text should satisfy the filter predicate (or all rows are visible when "All" is selected).

**Validates: Requirements 5.1**

---

### Property 9: User search filter correctness

*For any* non-empty search string entered in the user search input, every visible table row should contain that string (case-insensitive) in at least one of: User ID, Full Name, or Email Address cells.

**Validates: Requirements 5.2**

---

### Property 10: Add single user round-trip

*For any* valid user form submission (name, email, role), `MockDB.users` should contain a new entry matching the submitted fields, and the user table row count should increase by exactly 1.

**Validates: Requirements 5.4**

---

### Property 11: Create team round-trip

*For any* valid team configuration (name, level, at least one member), saving the team should add exactly one new entry to `MockDB.teams` with matching fields, and navigate to `manage_teams.html`.

**Validates: Requirements 6.1**

---

### Property 12: First roster member is auto-assigned as Team Leader

*For any* team creation flow, the first student added to the roster should have the leader crown element rendered and the `Team Leader` role tag, regardless of the student's identity.

**Validates: Requirements 6.2**

---

### Property 13: Role assignment toggle round-trip

*For any* user and any combination of Panelist / PIT Lead / Adviser toggle states, saving the role configuration should update `MockDB.users[id].facultyRoles` to exactly match the submitted toggle states.

**Validates: Requirements 7.1**

---

### Property 14: Dependent select disabled state mirrors toggle

*For any* state of the PIT Lead toggle, the PIT Lead year-level `<select>` element's `disabled` property should equal `!toggle.checked`. The same invariant applies to the Adviser capstone-phase select.

**Validates: Requirements 7.2**

---

### Property 15: Rubric total points invariant

*For any* set of criteria in the rubric builder, the displayed "Total Points" value should equal the arithmetic sum of all `maxScore` inputs at all times (including after add, delete, or edit of any criterion).

**Validates: Requirements 8.1**

---

### Property 16: Published rubric locks all inputs

*For any* rubric that has been published, every `<input>`, `<textarea>`, `<select>`, and `<button>` within the criteria builder section should have `disabled = true`.

**Validates: Requirements 8.2**

---

### Property 17: Draft save round-trip

*For any* rubric state (criteria list, level, evaluation type), saving as draft should result in `MockDB.rubrics` containing an entry whose `criteria` array matches the current builder state and whose `status` is `'draft'`.

**Validates: Requirements 8.3**

---

### Property 18: Grade Center filter correctness

*For any* combination of type filter (Capstone / PIT) and status filter (All / Fully Graded / Pending), every visible grade table row should satisfy both filter predicates simultaneously.

**Validates: Requirements 9.1**

---

### Property 19: Grade breakdown modal data matches MockDB

*For any* team row in the Grade Center, clicking "View Breakdown" should open a modal whose displayed per-criterion scores match `MockDB.grades[teamId].panelist.breakdown`.

**Validates: Requirements 9.2**

---

### Property 20: Audit trail modal matches MockDB event history

*For any* file row in the Repository Audit table, clicking the audit trail icon should open a modal whose event list matches `MockDB.auditFiles[id].auditTrail` in order and content.

**Validates: Requirements 10.1**

---

### Property 21: Override status round-trip

*For any* file and any new status value selected in the override dialog, confirming the override should update both the row's status badge class in the DOM and `MockDB.auditFiles[id].status` to the new value.

**Validates: Requirements 10.2**

---

### Property 22: Analytics bar widths match MockDB percentages

*For any* analytics dataset loaded from `MockDB.analytics.chart`, each bar element's CSS `width` percentage should equal the corresponding `pct` value in the dataset.

**Validates: Requirements 11.1**

---

### Property 23: Faculty grade submission round-trip

*For any* faculty grade form submission for a team, `MockDB.grades[teamId]` should be updated with the submitted criterion scores and the grade status should transition to `'pending'` or `'published'` as appropriate.

**Validates: Requirements 12.1**

---

### Property 24: Peer evaluation submission round-trip

*For any* student peer evaluation form submission, `MockDB` should contain the submitted peer scores keyed by the evaluator's student ID and the evaluated teammate's ID.

**Validates: Requirements 13.1**

---

### Property 25: Toast auto-dismiss timing

*For any* toast shown via `Toast.show()`, the toast element should be absent from the DOM (or have `display: none`) after 3000ms have elapsed, as measured by a fake timer.

**Validates: Requirements 14.1**

---

### Property 26: Coming Soon links show toast and do not navigate

*For any* link or button designated as "Coming Soon", clicking it should trigger a toast notification and leave `window.location.href` and `.main-content` unchanged.

**Validates: Requirements 14.2**

---

### Property 27: MockDB state survives content swaps

*For any* state mutation to `MockDB` followed by a navigation swap to a different screen and back, the mutated values should still be present in `MockDB` (verified via `sessionStorage` round-trip).

**Validates: Requirements 15.1**

---

## Error Handling

**Login errors:** Invalid credentials render an inline `<p class="login-error">` beneath the form. No alert dialogs.

**Navigation fetch failures:** If `fetch()` for a template fails (e.g., file not found), `nav.js` falls back to `window.location.href` assignment so the user still reaches the target page via a full reload.

**Missing MockDB keys:** All MockDB accessors use optional chaining (`?.`) and provide empty-array / null defaults so screens render gracefully even if a data key is absent.

**Form validation:** Required fields (team name, user name/email) show a native HTML5 `required` validation message. No custom validation library is needed for a prototype.

**Unimplemented screens:** Any `<a>` or `<button>` that points to a screen not yet built calls `Toast.show('Coming Soon', 'info')` and calls `event.preventDefault()`.

---

## Testing Strategy

### Dual Testing Approach

Both unit tests and property-based tests are used. Unit tests cover specific examples and integration points; property tests verify universal behaviors across generated inputs.

### Unit Tests

Focus areas:
- Login routing: one test per persona (3 examples).
- Toast component: show, dismiss, type classes.
- MockDB initialization: seed data structure matches expected shape.
- Nav controller: fetch-swap replaces `.main-content` and preserves sidebar.
- Specific screen interactions: "Add Year" appends a row, "Publish & Lock" disables inputs.

### Property-Based Tests

**Library:** [fast-check](https://github.com/dubzzz/fast-check) (JavaScript, browser-compatible via CDN or npm).

**Configuration:** Minimum 100 runs per property (`numRuns: 100`).

Each property test is tagged with a comment in the format:
```
// Feature: defensys-interactive-prototype, Property N: <property_text>
```

**Key property tests:**

- **Property 1 & 2** — Generate arbitrary strings as credentials; verify routing only occurs for exact persona matches.
- **Property 8 & 9** — Generate arbitrary user lists and filter strings; verify filter/search predicates hold for all generated inputs.
- **Property 15** — Generate arbitrary arrays of `{ maxScore: integer }` criteria; verify the displayed total always equals `sum(maxScore)`.
- **Property 18** — Generate arbitrary grade records with random type/status values; verify filter combinations always produce correct subsets.
- **Property 22** — Generate arbitrary `{ tech, pct }` arrays; verify rendered bar widths match pct values.
- **Property 27** — Generate arbitrary MockDB mutations; verify sessionStorage round-trip preserves all mutated values.

### Test Runner

**Vitest** (run with `vitest --run` for single-pass CI execution). Tests live in `DefenSYS_design_copy/js/__tests__/`.

Property tests import `fast-check` and the module under test directly. DOM-dependent tests use `jsdom` (Vitest's default environment).
