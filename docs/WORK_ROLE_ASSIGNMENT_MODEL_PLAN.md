# PIT Instructor Role Integration Plan

## Purpose

This plan narrows the prerequisite work before dynamic grade composition.

Most work roles already exist in DefenSYS. The missing connected requirement from the client is:

- PIT must also have instructors.
- A PIT Instructor handles teams through assigned sections.
- This should be implemented before dynamic grading because future grade categories need to know which instructor is responsible for which PIT teams.

## Scope

This is not a full rewrite of the role system.

Existing roles and workflows should be reused where possible:

- Admin
- Adviser
- Peer / Team Member
- Existing Capstone ownership flows
- Existing student team membership flows

The primary new capability is:

- Add and support the `PIT Instructor` contextual role.

## Non-Destructive Implementation Rule

This work must be additive.

Do not destroy, replace, or casually rewrite the current working system flows. The implementation should preserve existing behavior first, then add only the missing PIT Instructor and PIT Lead scoped user-import capabilities.

Existing flows that must remain intact:

- Admin user management
- Admin faculty import and role assignment
- Admin assignment of PIT Lead by year level
- Admin assignment of Defense Panelist capability
- Admin assignment of Project Adviser
- Admin assignment of Repository Assistant
- PIT Lead year-level team import
- PIT Lead year-level team management
- PIT Lead scheduling and panel selection from eligible panelists
- Capstone adviser ownership and grading flows
- Student team membership flows
- Existing audit/history behavior

When adding PIT-specific behavior:

- Reuse existing providers, serializers, permission helpers, audit logging, and UI patterns where possible.
- Add new scoped permissions instead of weakening Admin-only permissions globally.
- Keep Admin as the full override/oversight role.
- Keep PIT Lead limited to the assigned PIT year level.
- Keep PIT Instructor limited to assigned sections.
- Add tests around preserved behavior before changing shared role, import, or team-access code.

The guiding rule:

```text
Preserve the current flow, then layer the missing PIT-scoped behavior on top.
```

## Current System Audit Findings

The current system already supports PIT Lead as a real operational role.

Existing implementation:

- `User` has `is_pit_lead` and `pit_lead_year`.
- Admin can assign PIT Lead and choose a PIT Lead year level.
- Faculty dashboard has a PIT Lead workspace.
- PIT Lead has a Student Teams workspace.
- PIT Lead can bulk import PIT teams.
- PIT Lead team import is scoped to `pit_lead_year`.
- PIT Lead cannot import Capstone teams.
- User bulk import is currently Admin-only.
- Admin team management is currently Capstone-focused.
- Row-level visibility already gives Admin all teams and PIT Lead PIT teams for their assigned year.

Important gap:

- There is no implemented `PIT Instructor` role yet.
- There is no clear team `section_id` or section-scoped instructor ownership model in the current team code.
- Current PIT scoping is based on `year_level` and PIT/Capstone `level`, not section.

So the next implementation should not rebuild PIT Lead import. It should add the missing instructor/section layer.

## Authority Model

Use this split to avoid confusion:

```text
Admin = source of truth for global accounts and global faculty capabilities
PIT Lead = source of truth for PIT operations inside assigned year level
```

Admin controls broad system authority:

- Create/import faculty accounts
- Create/import admin accounts
- Create/import student accounts across all year levels
- Assign PIT Lead
- Assign Defense Panelist capability
- Assign Project Adviser
- Assign Repository Assistant

PIT Lead uses assigned authority inside the PIT year level:

- Import student users for assigned PIT year level
- Import/manage PIT teams for assigned PIT year level
- Assign PIT Instructor to sections inside assigned PIT year level
- Select eligible panelists for PIT events/schedules inside assigned PIT year level

Important panel rule:

```text
Admin marks faculty as eligible Defense Panelists.
PIT Lead chooses from those eligible panelists when scheduling PIT events.
```

The PIT Lead should not create global panelists. They only choose which already-eligible panelists serve on a PIT event or section.

## Core Distinction

The important difference is how team responsibility is assigned.

```text
PIT Instructor = section-scoped responsibility
PIT Lead = year-level-scoped PIT coordination
Capstone Adviser = explicit team-scoped responsibility
```

For PIT:

```text
Faculty -> PIT Lead assignment -> Year level -> PIT sections in year level
Faculty -> PIT Instructor assignment -> Section -> Teams in section
```

For Capstone:

```text
Faculty -> Adviser assignment -> Explicit teams
```

## PIT Instructor Rule

A PIT Instructor is assigned to one or more sections.

The instructor automatically handles all PIT teams in those sections.

Example:

```text
Faculty A is PIT Instructor for BSIT 3A.
Team 1, Team 2, and Team 3 belong to BSIT 3A.
Faculty A can access and manage those PIT teams.
```

If a PIT team moves to another section, instructor access should follow the new section assignment.

## Adviser Rule Already Exists

The Capstone Adviser behavior should stay as-is unless the current system is missing a validation rule.

Expected adviser rule:

```text
Faculty -> Adviser -> Assigned teams
```

The client distinction is:

- Adviser handles assigned teams only.
- Adviser can handle up to 4 teams.
- Adviser teams can come from different sections depending on admin assignment.

This is different from PIT Instructor because adviser ownership is not inherited from section.

## Admin And PIT Lead Import Ownership

Admin should remain the highest-level owner.

Admin can:

- Assign global roles and faculty capabilities
- Import users
- Import or manage teams across all sections and year levels
- Oversee all PIT and Capstone workflows
- Correct assignments when needed

PIT Lead should reduce admin workload without becoming a full admin.

Recommended rule:

```text
PIT Lead -> assigned year level -> can import and manage PIT teams for that year level
```

Example:

```text
Faculty A is PIT Lead for 3rd Year.
Faculty A can import PIT teams for 3rd Year sections.
Faculty A cannot import PIT teams for 4th Year unless also assigned as PIT Lead for 4th Year.
```

This matches the current role assignment idea shown in the admin UI:

```text
PIT Lead: 3rd Year
```

This is a good middle ground:

- Admin still oversees everything.
- PIT Lead can handle operational PIT setup for their assigned year level.
- PIT Instructors can focus on their own sections.
- The system avoids making every PIT import task dependent on Admin.

Audit note:

This is already mostly implemented. The backend and frontend already support PIT Lead bulk team import by assigned year level. The main work now is to preserve that behavior while adding PIT Instructor section ownership underneath it.

## PIT Lead User Import Ownership

PIT Lead should also be allowed to reduce Admin workload for student user setup.

Recommended rule:

```text
PIT Lead -> assigned year level -> can import student users for that PIT year level
```

This should reuse the Admin bulk-import workflow where possible, but with stricter permissions.

PIT Lead can:

- Import student users only.
- Import students only into the PIT Lead's assigned year level.
- Attach imported students to the active semester through `StudentAcademicRecord`.
- Use a simplified CSV template that does not expose faculty/admin role assignment or year-level selection.

PIT Lead should not:

- Import faculty users.
- Import admin users.
- Assign faculty roles.
- Change another user's system role.
- Import students into a different year level.
- Manage students outside the assigned PIT year level.
- Choose the target year level manually.
- Use the Faculty / General Users import mode.

Example:

```text
Faculty A is PIT Lead for 3rd Year.
Faculty A can bulk import 3rd Year PIT students.
Imported students receive StudentAcademicRecord(year_level = 3rd Year).
Faculty A cannot import 2nd Year, 4th Year, faculty, or admin users.
```

Admin still keeps full oversight:

```text
Admin -> can import all users and review all imported students
PIT Lead -> can import student users for assigned PIT year level only
```

Implementation note:

The current user bulk import endpoint is Admin-only. This can be implemented either by extending that endpoint with PIT Lead scoped permissions, or by adding a separate PIT Lead student-import endpoint. A separate scoped endpoint is cleaner if we want to avoid weakening Admin user-management permissions.

## Recommended Import Responsibility

The best default responsibility split is:

```text
Admin = can import/manage all users and teams
PIT Lead = can import student users for assigned year level only
PIT Lead = can import/manage PIT teams for assigned year level
PIT Instructor = can manage assigned-section teams after they exist
```

Optional later enhancement:

```text
PIT Instructor = can import teams only for assigned section
```

For the first implementation, PIT Lead import is cleaner because the UI already has year-level PIT Lead assignment and it reduces Admin workload while keeping control centralized enough.

## What Needs To Be Added

### 1. PIT Instructor Role Value

Add a new contextual faculty role or assignment type:

```text
PIT Instructor
```

This should not necessarily become a global login role. A user can remain a normal faculty account while being assigned as a PIT Instructor for specific sections.

### 2. Section Assignment

Admin should be able to assign faculty members as PIT Instructors for PIT sections.

Possible assignment shape:

```text
faculty_user_id
role = PIT Instructor
track = PIT
academic_period_id
section_id
is_active
created_by
created_at
```

The exact schema should follow the existing project patterns.

### 3. PIT Lead Year-Level Import Scope

PIT Lead already exists and the assigned year level is already meaningful for team import and management permissions.

The app should be able to answer:

```text
Can this PIT Lead import or manage PIT teams for this year level?
```

The answer should be yes when:

```text
faculty is PIT Lead for that year level
```

This should be kept as-is unless implementation details need cleanup.

### 4. PIT Lead Student Import Scope

Add PIT Lead scoped student import.

The app should be able to answer:

```text
Can this PIT Lead import student users for this year level?
```

The answer should be yes when:

```text
faculty is PIT Lead for that year level
```

The import should force:

```text
role = student
year_level = PIT Lead assigned year level
semester = active semester
```

PIT Lead student import UI should be a simplified version of Admin bulk import:

- No Import Batch Type dropdown.
- No Faculty / General Users option.
- No Batch Year Level dropdown.
- Year level is displayed as locked text from `pit_lead_year`.
- Target semester should default to the active semester.
- If target semester selection remains visible, it should be locked or limited to the active semester unless a future historical import flow is explicitly needed.

### 5. Team Access Helper

Add or update permission logic so the app can answer:

```text
Can this faculty member access this PIT team?
```

The answer should be yes when:

```text
faculty is PIT Instructor for the team's section
```

For PIT Lead, the answer should also be yes when:

```text
faculty is PIT Lead for the team's year level
```

The PIT Lead part already exists. The new part is PIT Instructor by section.

### 6. Admin Management UI

Admin can retain override access, but the primary PIT Instructor assignment flow should live in the PIT Lead workspace.

PIT Lead needs a PIT-focused role assignment interface for assigning instructors to sections inside the assigned year level.

Minimum useful flow:

- Select academic period
- Select PIT section
- Select faculty instructor
- Save assignment
- View current section instructor assignments
- Edit or deactivate assignment

This interface can reuse the current role-assignment card pattern, but it should only show one PIT-focused row:

```text
PIT Instructor
```

It should not show global role toggles such as:

- Defense Panelist
- PIT Lead
- Project Adviser
- Repository Assistant

Those remain Admin-managed global capabilities.

### 7. Faculty PIT View Filtering

When a faculty user is acting as PIT Instructor, their PIT view should show teams from assigned sections.

They should not need manual team-by-team assignment.

When a faculty user is acting as PIT Lead, their PIT view should show PIT teams from their assigned year level.

The PIT Lead should have import/manage tools for that year-level scope if the user has that role active.

## Validation Rules

Suggested rules:

- A PIT Instructor assignment must reference a faculty user.
- A PIT Instructor assignment must reference a PIT section.
- A PIT Instructor can be assigned to one or more sections.
- A PIT section can have one instructor by default unless the client wants co-instructors.
- If co-instructors are allowed later, the model should support multiple active instructors per section.
- A PIT Lead assignment should reference a year level.
- A PIT Lead can import student users only for assigned year levels.
- A PIT Lead can import or manage PIT teams only for assigned year levels.
- A PIT Lead can assign PIT Instructor only inside assigned year levels.
- A PIT Lead can select only existing eligible Defense Panelists for PIT schedules/events.
- A PIT Lead cannot grant Defense Panelist capability.
- A PIT Lead cannot grant PIT Lead, Project Adviser, or Repository Assistant.
- Admin can import or manage PIT teams for all year levels.
- Inactive assignments should not grant access.
- Team access should update when team section changes.

## Relationship To Dynamic Grading

This should be implemented before dynamic grade composition.

Later, a grade category can reference PIT Instructor as the submitter:

```text
Category: PIT Instructor Evaluation
Submitter role: PIT Instructor
Allowed teams: Teams in assigned PIT sections
```

Without PIT Instructor assignments, the grading system cannot reliably know who should submit instructor-based PIT grades.

## Recommended Implementation Order

1. Add regression tests or manual verification notes for existing Admin and PIT Lead flows.
2. Preserve the existing Admin and PIT Lead team import behavior.
3. Add PIT Lead scoped student user import for assigned year level.
4. Decide or implement the PIT section source of truth.
5. Add the `PIT Instructor` contextual role or assignment type using the existing role-assignment pattern.
6. Add PIT Lead UI for assigning PIT Instructors to sections in the assigned year level.
7. Add access helper logic for PIT team ownership through section assignment.
8. Keep Admin override ability for PIT Instructor assignments if needed.
9. Add PIT Instructor faculty workspace or a filtered Student Teams mode for assigned-section teams.
10. Add validation for duplicate or inactive assignments.
11. Re-run targeted backend/frontend checks to confirm existing flows still work.
12. After this is stable, continue with dynamic grade categories.

## Open Questions

- Can one PIT section have multiple instructors?
- Can one PIT Instructor handle multiple sections?
- Is PIT Lead already implemented, or does the existing Admin role cover that workflow?
- Should section instructor assignment be tied to academic period?
- Should changing a team's section immediately transfer PIT Instructor access?
- Should PIT Instructor be able to grade, manage submissions, approve deliverables, or only view/monitor until grading is implemented?
- Should PIT Instructor eventually be allowed to import teams for assigned sections, or should import stay with Admin and PIT Lead only?
- What field or model represents a PIT section in the current system?
- If sections are not stored yet, should section be added to student academic records, teams, or both?
- Should PIT Lead student import create new student accounts only, or also update existing student academic records for that year level?
- Should PIT Lead imported students require Admin review/approval before they can log in?
- Should Admin override for PIT Instructor assignment be exposed in the Admin UI immediately, or can it be deferred until needed?

## Decision Summary

Implement the missing `PIT Instructor` role first.

The rest of the role system should be reused where it already exists. PIT Lead already reduces Admin workload by importing and managing PIT teams for assigned year levels.

The key behaviors are:

```text
Admin -> all PIT year levels and sections
PIT Lead -> assigned year level user import, team import, PIT Instructor assignment, and PIT event panel selection
PIT Instructor -> assigned section -> PIT teams in that section
```

Once that is in place, dynamic grading can safely use `PIT Instructor` as a submitter role for PIT grade categories.
