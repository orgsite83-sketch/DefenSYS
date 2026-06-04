# PIT Cohort Rollover Plan

## Purpose

PIT cohorts are tied to year level, semester, section, and instructor responsibility. Once a PIT Lead has already imported or maintained a cohort, the system should not force the admin to recreate the same student academic records every semester.

The rollover workflow should let a scoped PIT Lead continue their assigned cohort into the next valid academic period while preserving admin control over official academic periods.

```text
Official class list import = source of truth when a school file is available.
PIT cohort rollover = fast continuation when the same cohort moves forward.
```

The goal is to reduce repeated admin work without allowing PIT users to bypass academic-period, role, or Capstone source-of-truth boundaries.

## Core Idea

The PIT Lead can preview and apply a rollover for their assigned year level only.

Examples:

```text
3rd Year, 1st Semester, A.Y. 2026-2027
-> 3rd Year, 2nd Semester, A.Y. 2026-2027

2nd Year, 2nd Semester, A.Y. 2026-2027
-> 3rd Year, 1st Semester, A.Y. 2027-2028
```

The admin still owns academic-period setup. The rollover should only target an existing valid next period, or the currently active period if it matches the expected next step.

## Source Of Truth Model

The rollover should create or update student academic context only.

It can roll over:

- Student academic records.
- Program.
- Section.
- Year level, when moving across a school-year boundary.
- Semester and school year.
- PIT cohort membership implied by the academic records.

It should not roll over by default:

- Grades.
- Rubric scores.
- Defense schedules.
- Defense panel assignments.
- Repository deliverables.
- Dynamic grade categories.
- Capstone adviser assignments.
- Capstone team assignments.

Those records represent workflow activity, evaluation history, or Capstone-specific responsibility, so copying them automatically would create audit and correctness risks.

## PIT Lead UX Shape

The PIT Lead `Cohort` screen can include:

```text
CSV Template
Import Official Class List
Rollover Preview
```

`Rollover Preview` should open a confirmation view before anything is committed.

The preview should show:

- Source academic period.
- Target academic period.
- Source year level and target year level.
- Number of students to roll over.
- Sections affected.
- Students that will be created in the target period.
- Students already present in the target period.
- Students blocked by validation issues.
- Optional instructor assignment carry-over status.

This keeps the action transparent and avoids accidental duplicate records.

## Rollover Behavior

When a PIT Lead starts a rollover, the system should:

1. Resolve the PIT Lead's assigned PIT year level.
2. Resolve the source period from the current cohort context.
3. Resolve the target period from the next valid academic period.
4. Validate that the PIT Lead is allowed to roll over only their assigned scope.
5. Find all student academic records in the source period for that year level.
6. Group records by section.
7. Preview what will be created or skipped.
8. On confirmation, create missing target academic records.
9. Preserve section and program unless changed later by official class list import.
10. Apply year-level promotion only when the target period begins a new school year.

The rollover should be idempotent. Running it twice should not duplicate student academic records.

## Semester And Year-Level Rules

Recommended rule:

```text
Same school year:
1st Semester -> 2nd Semester, same year level

New school year:
2nd Semester -> 1st Semester, next year level
```

Examples:

```text
1st Year, 1st Semester, A.Y. 2026-2027
-> 1st Year, 2nd Semester, A.Y. 2026-2027

1st Year, 2nd Semester, A.Y. 2026-2027
-> 2nd Year, 1st Semester, A.Y. 2027-2028
```

If the target academic period does not exist, the PIT Lead should see a clear message:

```text
No valid target academic period is available. Ask an admin to create or activate the next academic period.
```

PIT Lead should not create academic periods from this workflow.

## Instructor Assignment Rollover

PIT instructor assignment should be optional in the preview.

Recommended option:

```text
Carry previous PIT Instructor assignments
```

When enabled:

- Existing PIT Instructor assignments can be copied from source period to target period.
- Copy only assignments within the PIT Lead's assigned year level and sections.
- Do not create faculty accounts.
- Do not copy inactive or invalid faculty assignments without warning.

When disabled:

- Student academic records roll over.
- Sections can be marked as needing PIT Instructor assignment.
- Official class list import can later assign or correct instructors.

This supports schools where the same instructor continues with a section, while still handling cases where faculty assignments change per semester.

## Interaction With Official Class List Import

Rollover and official class list import should work together.

Recommended priority:

```text
Rollover creates continuity.
Official class list import corrects truth.
```

If a class list is imported after rollover:

- Student details can be updated.
- Section can be corrected.
- Year level and semester can be validated against the target period.
- Instructor assignment can be updated if a confident faculty match exists.
- Missing students from the official list can be added.

If a rollover already created target records, the import should update those records rather than duplicating them.

## Validation Rules

The rollover should reject or block confirmation when:

- The user has no assigned PIT year level.
- The source period has no student academic records in scope.
- The target period cannot be resolved.
- The target year level is outside the PIT Lead's allowed scope.
- A student has conflicting target academic records.
- The source records have no section and section is required for PIT access.

The rollover should warn but allow confirmation when:

- Some students already exist in the target period.
- Some source records are missing optional email/contact data.
- Instructor assignments are not carried forward.
- Instructor assignments cannot be carried forward because faculty are inactive or no longer valid.
- Section names are inconsistent but still usable.

## Access Boundaries

PIT Lead can:

- Preview rollover for their assigned PIT year level.
- Apply rollover for students within their assigned PIT scope.
- Preserve section context.
- Optionally carry PIT Instructor assignments for sections they manage, if allowed.

PIT Lead cannot:

- Create school years or semesters.
- Roll over students outside their assigned PIT scope.
- Promote arbitrary students into unrelated year levels.
- Copy Capstone advisers or Capstone teams.
- Copy grades, rubric scores, schedules, or deliverables.
- Create faculty accounts.

Admin can:

- Create and activate academic periods.
- Run or correct rollovers across year levels.
- Oversee all student academic records.
- Correct PIT Instructor assignments.
- Use official class list import as the source-of-truth correction path.

## Recommended Phase 1

Build the smallest useful version first:

1. Add `Rollover Preview` to PIT Lead `Cohort`.
2. Scope rollover to the PIT Lead's assigned year level.
3. Resolve the target period from existing academic periods.
4. Create missing student academic records for the target period.
5. Preserve section and program.
6. Promote year level only across school-year boundary.
7. Do not copy grades, schedules, deliverables, rubric scores, or Capstone data.
8. Make instructor assignment carry-over optional, or defer it to Phase 2.
9. Make the action idempotent so repeated rollover does not duplicate records.
10. Let official class list import update or correct records after rollover.

## Open Decisions

- Should PIT Lead rollover always use the active semester, or should it use the next chronological academic period?
- Should instructor assignment carry-over be included in Phase 1 or delayed?
- Should sections with missing instructor assignment remain flagged on the cohort screen?
- Should students with incomplete or failed status be excluded from automatic year-level promotion?
- Should rollover preserve PIT teams, or should teams be recreated per semester?
- Should Admin have a broader version of the same rollover preview from `Student Records`?
- Should rollover support a dry-run export for audit before confirmation?
