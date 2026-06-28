# Official Class List Import and PIT Instructor Assignment Plan

## Purpose

The client has an existing school-issued class list file that already contains the students, class section, year level, subject, semester, and assigned faculty. Instead of forcing users to manually rebuild that information in DefenSYS, the system should treat the official class list as the source of truth for student academic context.

The import should be useful for both PIT and Capstone, but the workflow effects should be different:

```text
Official class list import = truth for student academic records.
PIT instructor assignment = section-based extension.
Capstone adviser assignment = team-based extension.
```

The import should create the cohort. It should not become the source of truth for Capstone adviser/team assignment unless a future school file explicitly includes team and adviser data.

This plan is intentionally additive. It should preserve the current admin user management, role assignment, student import, student team, and scheduling flows. The goal is to add a PIT-focused workflow without replacing the admin source-of-truth behavior already working in the system.

## Source Of Truth Model

The official class list should become the shared source of truth for:

```text
student identity
semester
school year
year level
program
section
enrollment/cohort membership
```

It should not be the shared source of truth for:

```text
Capstone adviser assignment
Capstone team assignment
panel assignment
defense schedules
rubric evaluators
dynamic grade categories
```

Those remain workflow-specific records layered on top of the imported academic records.

## PIT Lead UX Shape

Mirror the admin user management pattern, but scope it to the PIT Lead's assigned year level.

```text
PIT Lead Sidebar

User Management
- Cohort
- Student Teams
```

The separate `Import Students` sidebar item should be removed. Student import should become an action inside the `Cohort` screen, similar to how admin import actions live at the top of admin user management.

`PIT Instructors` should not be a separate sidebar item. Instructor status should appear inside `Cohort` by section, with a shield/action button for manual assignment when a section needs correction.

Admin can also use the same official class list import concept from admin user management, but with broader controls across year levels and sections.

## PIT Cohort Screen Actions

The PIT Lead `Cohort` screen should show students for the PIT Lead's assigned year level and active semester.

Top actions:

```text
CSV Template
Import Official Class List
```

The import action should be PIT-specific:

- Accept `.csv` and `.xlsx` official class list files.
- Student-only import.
- No faculty/general-user import option.
- No year-level dropdown if the PIT Lead already has an assigned PIT year.
- Section should come from the official class list.
- Semester should resolve to the active semester unless the imported file clearly includes a matching semester.
- Imported rows should create or update student accounts and student academic records.

## Official Class List Data

The school file can include header-level metadata and student rows.

Expected header metadata:

```text
Subject Code
Subject Title
Academic Units
Class Section
Year Level
Schedule(s)
Instructor
Semester / School Year
```

Expected student row data:

```text
Student Number
Full Name
Program
Gender
Level
OR No.
Validation Date
Email
Contact
```

Minimum required data for DefenSYS import:

```text
Student Number
Full Name
Program
Class Section
Year Level
Instructor
Semester
```

Email/contact can remain optional if the official school list does not always include them.

## Import Behavior

When an official class list is imported, the system should:

1. Parse the class-level metadata.
2. Confirm the class section and year level.
3. Validate scope based on importer:
   - PIT Lead can import only for their assigned PIT year.
   - Admin can import for any valid year level.
4. Import or update student accounts.
5. Create or update each student's academic record for the resolved semester.
6. Attach each student academic record to the detected section.
7. Treat the imported academic records as the cohort source for later PIT or Capstone workflows.

If the import is being used for PIT:

8. Detect the instructor name from the file and try to match it to an existing faculty account.
9. If matched, create or update the `PIT Instructor` assignment for that faculty, year level, semester, and section.
10. If not matched, import the students anyway and mark the section as needing instructor assignment.
11. If a PIT team is created later from those students, team section should follow the students' academic section.

If the import is being used for Capstone:

8. Do not assign adviser automatically from the class-list instructor field.
9. Keep adviser assignment in the existing Capstone team/adviser workflow.
10. If a Capstone team is created later from those students, the team can retain section context for filtering/reporting, but access should still follow adviser/team assignment.

This keeps the import universal for student academic records while preserving the different PIT and Capstone responsibility models.

## Workflow Effects

### PIT

PIT uses section-based instructor responsibility.

```text
Official class list import
-> creates/imports students
-> creates/updates student academic records
-> assigns section
-> detects class-list instructor
-> creates PIT Instructor assignment when faculty match is confident
-> PIT teams are created/managed inside that section context
```

Access model:

```text
PIT Lead sees all sections in assigned PIT year.
PIT Instructor sees students/teams in assigned sections.
Admin sees all.
```

### Capstone

Capstone uses team-based adviser responsibility.

```text
Official class list import
-> creates/imports students
-> creates/updates student academic records
-> assigns section
-> does not assign adviser automatically
-> Capstone teams and advisers continue through existing system flow
```

Access model:

```text
Adviser sees assigned teams.
Admin oversees adviser/team assignment.
Section remains useful for filtering and reporting.
```

## PIT Instructor Assignment Rule

For PIT, the official class list can be the primary way to assign PIT Instructor context.

Example:

```text
Instructor: Daga-ang, Jubilee S.
Class Section: BSIT-1A
Year Level: 1st Year
```

If `Daga-ang, Jubilee S.` matches an existing faculty account, the system can assign that faculty as:

```text
PIT Instructor
Semester: Active semester
Year Level: 1st Year
Section: BSIT-1A
```

This should not automatically create a new faculty account unless the system has a deliberate, admin-approved faculty import flow. Automatic faculty creation from class-list text is risky because names may be formatted inconsistently.

For Capstone, the class-list instructor should not become the project adviser automatically. Capstone adviser assignment remains team-based and should follow the current system behavior.

## Manual Fallback

The admin-style shield/action button should remain available for PIT Instructor assignment.

Recommended behavior:

- PIT Lead can click the shield/action button for a section row inside `Cohort`.
- The PIT Lead assignment screen should show only `PIT Instructor`.
- The selected section should be prefilled when the shield action opens the assignment screen.
- The PIT Lead can assign existing faculty to sections within their assigned PIT year.
- Admin can still oversee and correct all assignments.

This gives the system two paths:

```text
Primary path:
Import official class list, auto-detect instructor and section.

Fallback path:
Use shield/action button to manually assign or correct PIT Instructor.
```

## Faculty Matching

Faculty matching should be conservative.

Suggested matching order:

1. Exact normalized full-name match.
2. Exact email match, if the imported file includes faculty email.
3. Admin/PIT Lead manual selection if multiple possible matches exist.
4. No assignment if no confident match exists.

If there is no confident match, the import should not fail the whole class list. It should complete the student import and show a warning:

```text
Students imported. Instructor could not be matched. Please assign PIT Instructor manually.
```

## Section-Centered View

The `Cohort` screen should make sections visible because instructor access depends on section.

Useful display options:

- Default `Sections` view with compact section rows.
- Secondary `Students` view with a `Section` column.
- Filter sections by instructor status.
- Instructor status per section:

```text
BSIT-1A - Instructor assigned
BSIT-1B - Needs instructor assignment
```

This helps the PIT Lead quickly see whether every imported section has an instructor.

## Boundaries

PIT Lead can:

- Import official class lists for their assigned PIT year.
- Import students from those class lists.
- Assign existing faculty as PIT Instructor for sections in their assigned PIT year.
- View faculty already created/imported by admin.
- Manage PIT cohort and teams within their assigned year.

PIT Lead cannot:

- Import faculty/general users.
- Create global faculty accounts from class-list text.
- Assign panelist, adviser, PIT Lead, documenter, or admin-level roles.
- Import or manage students outside their assigned PIT year.
- Override admin source-of-truth controls.

Admin can:

- Import and manage all users.
- Import official class lists across year levels.
- Create faculty accounts.
- Assign global/modular roles.
- Oversee and correct PIT Instructor assignments.
- Manage all years, sections, teams, and records.

Capstone adviser flow can:

- Use imported student academic records as student source data.
- Continue assigning advisers by team.
- Preserve current Capstone team/adviser behavior.
- Use section context for filtering/reporting without changing adviser access rules.

## Validation Rules

The import should reject or require confirmation when:

- The file year level does not match the PIT Lead's assigned PIT year.
- The file has no class section.
- The file has no student number column.
- The same student appears multiple times in the same import.
- The semester cannot be resolved and there is no active semester.

The import should warn but still continue when:

- Instructor name cannot be matched to an existing faculty account.
- Email/contact is missing.
- Some optional row fields are blank.
- Student already exists and will be updated.

## Implementation Notes

This should be implemented as an additive official class list import path. It can be exposed differently for Admin and PIT Lead, but should write to the same student academic-record source of truth.

Suggested backend pieces:

- Parser for official class list files.
- Preview endpoint before commit.
- Commit endpoint after PIT Lead confirms parsed section/year/semester.
- Reuse existing student creation/update helpers where possible.
- Reuse `StudentAcademicRecord.section`.
- Reuse `PitInstructorAssignment`.
- Add import result warnings for unmatched instructors and skipped/updated rows.
- Keep Capstone adviser/team assignment separate from class-list instructor import.

Suggested frontend pieces:

- Move PIT student import into `Cohort`.
- Add `Import Official Class List` action.
- Support both CSV and XLSX uploads by parsing either format into the same metadata/student payload.
- Add import preview modal/page.
- Show parsed metadata before final import.
- Show post-import result summary.
- Keep manual PIT Instructor assignment available from faculty shield/action button.
- For admin, consider adding the same import action to user management with admin-wide scope.

## Open Decisions

- Should the PIT Lead be allowed to choose a semester manually if the file semester is missing?
- Should section names be normalized, for example `BSIT 1A` to `BSIT-1A`?
- Should the system store subject/schedule metadata now, or only use section/year/instructor/student data for this phase?
- Should unmatched instructor warnings appear on the cohort screen until resolved?
- Should Admin and PIT Lead use the same preview UI with different available controls?
- Should Capstone screens display imported section context even though adviser access remains team-based?

## Recommended Phase 1

Build the smallest useful version first:

1. Put import inside PIT Lead `Cohort`.
2. Treat official class list import as student academic-record import.
3. Parse/import students with year level and section.
4. Lock PIT Lead import to PIT Lead's assigned year.
5. Match instructor only if an existing faculty account is confidently found.
6. Auto-create `PIT Instructor` assignment only for PIT and only on confident match.
7. Do not auto-assign Capstone adviser from class-list instructor.
8. Show warning and manual assignment path if PIT faculty is unmatched.
9. Keep admin and Capstone flows unchanged except for using imported student academic records.
