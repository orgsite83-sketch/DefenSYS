# Requirements Document

## Introduction

The DefenSYS Interactive Prototype converts the existing static HTML/CSS design mockups into a fully navigable, client-side clickable simulation of the DefenSYS academic defense management system. No backend is required. All interactivity is driven by a JavaScript navigation controller and an in-memory mock data layer persisted within a single browser session via `sessionStorage`. The prototype supports three user personas — Admin, Faculty, and Student — each with role-scoped sidebar navigation, a home dashboard, and an accessible feature set. The goal is a demo-ready prototype that a stakeholder can click through end-to-end without hitting broken links or blank pages.

## Glossary

- **Prototype**: The client-side, fully navigable simulation described in this document.
- **MockDB**: The global in-memory JavaScript object that holds all prototype state, seeded with hardcoded data and backed by `sessionStorage`.
- **Nav_Controller**: The `nav.js` module that intercepts sidebar link clicks and performs fetch-swap navigation.
- **Screen_Handler**: The per-screen initialisation logic in `prototype.js` that attaches event listeners after each content swap.
- **Toast**: The lightweight notification component used to surface success, info, and warning messages.
- **Admin**: The administrator persona with credentials `admin` / `admin123`.
- **Faculty**: The faculty persona with credentials `faculty` / `faculty123`.
- **Student**: The student persona with credentials `student` / `student123`.
- **Sidebar**: The persistent `<aside>` navigation panel rendered per role.
- **Main_Content**: The `.main-content` DOM region that is swapped on navigation without replacing the Sidebar.
- **Coming_Soon**: A toast-based placeholder shown for any screen or action not yet implemented.

---

## Requirements

### Requirement 1: Role-Based Login

**User Story:** As a stakeholder, I want to log in with a role-specific credential, so that I am routed to the correct persona dashboard and see only that role's navigation.

#### Acceptance Criteria

1. WHEN a user submits the username `admin` and password `admin123`, THE Prototype SHALL set `MockDB.currentUser.role` to `"admin"` and navigate to `admin_dashboard.html`.
2. WHEN a user submits the username `faculty` and password `faculty123`, THE Prototype SHALL set `MockDB.currentUser.role` to `"faculty"` and navigate to `faculty_dashboard.html`.
3. WHEN a user submits the username `student` and password `student123`, THE Prototype SHALL set `MockDB.currentUser.role` to `"student"` and navigate to `student_dashboard.html`.
4. IF a user submits a username and password combination that does not match any persona, THEN THE Prototype SHALL render an inline error message beneath the login form and leave the current URL unchanged.
5. THE Prototype SHALL NOT use `alert()` dialogs for login error feedback.

---

### Requirement 2: Persistent Sidebar Navigation

**User Story:** As a user, I want the sidebar to remain visible and active while I navigate between screens, so that I can move between sections without losing context.

#### Acceptance Criteria

1. WHEN a sidebar link is clicked, THE Nav_Controller SHALL replace only the `.main-content` innerHTML with the fetched screen content, leaving the `<aside>` sidebar DOM node unchanged.
2. WHEN navigation to a screen completes, THE Nav_Controller SHALL mark exactly one `<li>` in `.nav-links` with the `active` class, corresponding to the navigated screen.
3. THE Sidebar SHALL contain only the navigation links defined for the currently logged-in role and SHALL NOT display links belonging to other roles.
4. IF a `fetch()` call for a template file fails, THEN THE Nav_Controller SHALL fall back to a full-page `window.location.href` assignment so the user still reaches the target screen.
5. WHEN navigation completes, THE Nav_Controller SHALL re-run the `sidebar.js` dropdown logic and the `Screen_Handler` init function for the newly loaded content.

---

### Requirement 3: Admin Dashboard

**User Story:** As an Admin, I want to see a summary of system activity on my dashboard, so that I can quickly assess the current state of the department.

#### Acceptance Criteria

1. WHEN the Admin dashboard loads, THE Prototype SHALL render mock statistics sourced from `MockDB`: 142 active students, 38 vault archives, and 12 grade locks applied.
2. WHEN the "Configure Now" button in the System Status alert is clicked, THE Nav_Controller SHALL navigate to `rubric_engine.html`.

---

### Requirement 4: Academic Period Management

**User Story:** As an Admin, I want to manage school years and semesters, so that I can define the active academic context used across the system.

#### Acceptance Criteria

1. WHEN an Admin activates a semester toggle, THE Prototype SHALL update `MockDB` to reflect the new active semester and update the `.active-sem` badge text in the top navigation to match the newly activated semester label.
2. WHEN an Admin submits the "Add Year" inline form, THE Prototype SHALL append a new entry to `MockDB.academicPeriods` with the submitted label and add one new row to the School Years table.
3. WHEN an Admin submits the "Add Semester" inline form, THE Prototype SHALL append a new semester entry to the relevant academic period in `MockDB` and add one new row to the Semesters table.
4. WHEN an Admin clicks a "Manage" button on a past school year, THE Prototype SHALL display a Coming_Soon toast.

---

### Requirement 5: User Management

**User Story:** As an Admin, I want to view, filter, search, and add users, so that I can maintain an accurate roster of students and faculty.

#### Acceptance Criteria

1. WHEN a role filter card (All / Faculty / Students) is selected, THE Prototype SHALL show only the table rows whose role badge matches the selected filter, or all rows when "All" is selected.
2. WHEN text is entered in the search input, THE Prototype SHALL show only the table rows where the User ID, Full Name, or Email Address cell contains the entered string (case-insensitive).
3. WHEN the "Bulk Import CSV" button is clicked and a file is selected, THE Prototype SHALL display a success toast reading "Import simulated — 12 users added" and append mock rows to the user table.
4. WHEN an Admin submits the "Add Single User" modal form with a valid name, email, and role, THE Prototype SHALL append a new entry to `MockDB.users` and add exactly one new row to the user table.
5. WHEN the edit icon for a user row is clicked, THE Nav_Controller SHALL navigate to `role_assignment.html` with the user's ID in the URL hash.

---

### Requirement 6: Student Team Management

**User Story:** As an Admin, I want to create and view student teams for PIT and Capstone, so that I can organise students into project groups with assigned leaders and advisers.

#### Acceptance Criteria

1. WHEN an Admin saves a valid team configuration (project name, level, and at least one member), THE Prototype SHALL append exactly one new entry to `MockDB.teams` with the submitted fields and navigate to `manage_teams.html`.
2. WHEN the first student is added to the team roster during team creation, THE Prototype SHALL render the leader crown icon and "Team Leader" role tag on that student's card, regardless of the student's identity.
3. WHEN the level filter dropdown on the Manage Teams screen is changed, THE Prototype SHALL show only the table rows matching the selected level.
4. WHEN the eye icon for a team row is clicked, THE Prototype SHALL open a team detail modal displaying the team's member list sourced from `MockDB.teams`.

---

### Requirement 7: Role Assignment

**User Story:** As an Admin, I want to assign and toggle faculty roles (Panelist, PIT Lead, Adviser) for a user, so that faculty members gain access to the correct workflows for the semester.

#### Acceptance Criteria

1. WHEN an Admin saves a role configuration, THE Prototype SHALL update `MockDB.users[id].facultyRoles` to exactly match the submitted toggle states for Panelist, PIT Lead, and Adviser.
2. WHILE the PIT Lead toggle is off, THE Prototype SHALL keep the PIT Lead year-level `<select>` element disabled; WHEN the PIT Lead toggle is turned on, THE Prototype SHALL enable the year-level select.
3. WHILE the Adviser toggle is off, THE Prototype SHALL keep the Adviser capstone-phase `<select>` element disabled; WHEN the Adviser toggle is turned on, THE Prototype SHALL enable the capstone-phase select.
4. WHEN the Role Assignment page loads with a user ID in the URL hash, THE Prototype SHALL pre-populate the page header with the matching user's name from `MockDB.users`.

---

### Requirement 8: Rubric Engine

**User Story:** As an Admin, I want to configure rubric criteria with weighted scores, save drafts, and publish rubrics, so that panelists and evaluators have a locked scoring guide for each defense stage.

#### Acceptance Criteria

1. WHEN any criterion's Max Score input is changed, added, or removed, THE Prototype SHALL update the displayed "Total Points" counter to equal the arithmetic sum of all current `maxScore` inputs.
2. WHEN "Publish & Lock Rubric" is clicked, THE Prototype SHALL set the rubric's `status` to `"published"` in `MockDB.rubrics`, disable all `<input>`, `<textarea>`, `<select>`, and `<button>` elements within the criteria builder section, and display a lock confirmation toast.
3. WHEN "Save as Draft" is clicked, THE Prototype SHALL save the current criteria list and rubric metadata to `MockDB.rubrics` with `status: "draft"` and display a success toast.
4. WHEN "Import Previous Template" is clicked, THE Prototype SHALL display a Coming_Soon toast.

---

### Requirement 9: Grade Center (Admin View)

**User Story:** As an Admin, I want to monitor evaluation status and view grade breakdowns for all teams, so that I can track grading progress across the semester.

#### Acceptance Criteria

1. WHEN a type filter (Capstone / PIT) or status filter (All / Fully Graded / Pending) is applied, THE Prototype SHALL show only the grade table rows that satisfy both filter predicates simultaneously.
2. WHEN the "View Breakdown" button for a team row is clicked, THE Prototype SHALL open a modal displaying per-criterion scores that match `MockDB.grades[teamId].panelist.breakdown`.
3. WHEN "Export Grading Sheet" is clicked, THE Prototype SHALL display a Coming_Soon toast.

---

### Requirement 10: Repository Audit

**User Story:** As an Admin, I want to audit archived project files, view their event history, and override file statuses, so that I can maintain the integrity of the Digital Vault.

#### Acceptance Criteria

1. WHEN the audit trail icon for a file row is clicked, THE Prototype SHALL open a modal displaying the event list from `MockDB.auditFiles[id].auditTrail` in chronological order.
2. WHEN an Admin confirms a status override for a file, THE Prototype SHALL update the row's status badge in the DOM and set `MockDB.auditFiles[id].status` to the selected new value.
3. WHEN the search input or filter dropdowns are used, THE Prototype SHALL filter the file table rows client-side to match the entered criteria.
4. WHEN pagination buttons are clicked, THE Prototype SHALL show or hide the appropriate mock page rows client-side.
5. WHEN "Export ISO Audit Log" is clicked, THE Prototype SHALL display a Coming_Soon toast.

---

### Requirement 11: Curriculum Analytics

**User Story:** As an Admin, I want to view technology adoption trends and DSS suggestions, so that I can make informed curriculum update decisions.

#### Acceptance Criteria

1. WHEN the Curriculum Analytics screen loads, THE Prototype SHALL render trend cards, bar chart bars, and DSS suggestion cards from `MockDB.analytics`.
2. WHEN a bar chart bar is rendered, THE Prototype SHALL set its CSS `width` percentage to equal the corresponding `pct` value in `MockDB.analytics.chart`.
3. WHEN the year filter dropdown is changed, THE Prototype SHALL re-render the bar chart using the mock dataset for the selected year.
4. WHEN "Generate Curriculum Proposal" is clicked, THE Prototype SHALL display a Coming_Soon toast.

---

### Requirement 12: Faculty Grade Center

**User Story:** As a Faculty panelist, I want to view my assigned teams and submit criterion scores, so that I can complete my grading responsibilities for a defense.

#### Acceptance Criteria

1. WHEN the Faculty dashboard loads, THE Prototype SHALL display the faculty member's assigned teams and a "Submit Grades" call-to-action sourced from `MockDB`.
2. WHEN a Faculty member submits a grade form for a team, THE Prototype SHALL update `MockDB.grades[teamId]` with the submitted criterion scores and display a confirmation toast.
3. WHEN "My Teams" or "Digital Vault" sidebar links are clicked from the Faculty role, THE Prototype SHALL display a Coming_Soon toast.

---

### Requirement 13: Student Dashboard and Peer Evaluation

**User Story:** As a Student, I want to see my team's current status and submit peer evaluations for my teammates, so that I can participate in the defense grading process.

#### Acceptance Criteria

1. WHEN the Student dashboard loads, THE Prototype SHALL display the student's team name, project title, current team result (Pending / Approved / Failed), and latest defense context sourced from `MockDB`.
2. WHEN a Student submits a peer evaluation form, THE Prototype SHALL save the submitted peer scores to `MockDB` keyed by the evaluator's student ID and the evaluated teammate's ID, and display a confirmation toast.
3. WHEN "My Team" detail or "Digital Vault" sidebar links are clicked from the Student role, THE Prototype SHALL display a Coming_Soon toast.

---

### Requirement 14: Toast Notification System

**User Story:** As a user, I want brief, non-blocking notifications for actions and placeholders, so that I receive feedback without losing my current context.

#### Acceptance Criteria

1. WHEN `Toast.show(message, type)` is called, THE Prototype SHALL display a toast element in the DOM; WHEN 3000ms have elapsed, THE Prototype SHALL remove or hide the toast element.
2. WHEN a Coming_Soon link or button is clicked, THE Prototype SHALL call `event.preventDefault()`, display a Coming_Soon toast, and leave `window.location.href` and `.main-content` unchanged.
3. THE Toast SHALL support the types `"success"`, `"info"`, and `"warning"`, applying a distinct CSS class for each type.

---

### Requirement 15: Prototype State Consistency

**User Story:** As a demo presenter, I want mock data mutations to persist across screen navigations within the same browser session, so that the prototype behaves consistently throughout a demo.

#### Acceptance Criteria

1. WHEN any `MockDB` value is mutated and the user navigates to a different screen and back, THE Prototype SHALL retain the mutated values in `MockDB` via `sessionStorage` round-trip.
2. WHEN the Prototype first loads in a new browser session, THE Prototype SHALL initialise `MockDB` from hardcoded seed data.
3. THE Prototype SHALL use optional chaining (`?.`) and empty-array or null defaults for all `MockDB` accessors so that screens render without errors even when a data key is absent.
