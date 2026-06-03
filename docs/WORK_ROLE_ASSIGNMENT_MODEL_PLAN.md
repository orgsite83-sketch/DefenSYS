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

- Assign roles
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

## Recommended Import Responsibility

The best default responsibility split is:

```text
Admin = can import/manage all users and teams
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

If PIT Lead already exists, reuse it and make the assigned year level meaningful for team import and management permissions.

The app should be able to answer:

```text
Can this PIT Lead import or manage PIT teams for this year level?
```

The answer should be yes when:

```text
faculty is PIT Lead for that year level
```

### 4. Team Access Helper

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

### 5. Admin Management UI

Admin needs a way to assign PIT Instructors to sections.

Minimum useful flow:

- Select academic period
- Select PIT section
- Select faculty instructor
- Save assignment
- View current section instructor assignments
- Edit or deactivate assignment

### 6. Faculty PIT View Filtering

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
- A PIT Lead can import or manage PIT teams only for assigned year levels.
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

1. Locate the existing role, faculty assignment, section, and team ownership patterns.
2. Add the `PIT Instructor` contextual role or assignment type using the existing pattern.
3. Add PIT section instructor assignments.
4. Reuse existing PIT Lead year-level assignment for scoped PIT team import and management.
5. Add access helper logic for PIT team ownership through section assignment and PIT Lead year-level assignment.
6. Add or update admin UI for assigning instructors to PIT sections.
7. Update faculty PIT screens to show assigned-section teams for PIT Instructors and assigned-year teams for PIT Leads.
8. Add validation for duplicate or inactive assignments.
9. After this is stable, continue with dynamic grade categories.

## Open Questions

- Can one PIT section have multiple instructors?
- Can one PIT Instructor handle multiple sections?
- Is PIT Lead already implemented, or does the existing Admin role cover that workflow?
- Should section instructor assignment be tied to academic period?
- Should changing a team's section immediately transfer PIT Instructor access?
- Should PIT Instructor be able to grade, manage submissions, approve deliverables, or only view/monitor until grading is implemented?
- Should PIT Instructor eventually be allowed to import teams for assigned sections, or should import stay with Admin and PIT Lead only?

## Decision Summary

Implement the missing `PIT Instructor` role first.

The rest of the role system should be reused where it already exists. PIT Lead should also be allowed to reduce Admin workload by importing and managing PIT teams for assigned year levels.

The key behaviors are:

```text
Admin -> all PIT year levels and sections
PIT Lead -> assigned year level
PIT Instructor -> assigned section -> PIT teams in that section
```

Once that is in place, dynamic grading can safely use `PIT Instructor` as a submitter role for PIT grade categories.
