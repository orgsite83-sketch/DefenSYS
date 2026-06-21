# Admin Template Roster And Panel Schedule Import Plan

## Short Answer

Yes, we can make the admin's suggestion real.

The right improvement is not to replace the current Student Teams bulk import or Defense Scheduler flow. Those already work and should remain available. The improvement should be an additional import-assisted path that accepts the admin's existing Excel-style template, previews what DefenSYS understood, then creates or links the same system records that the current flow creates manually.

Recommended product direction:

```text
Keep current flow:
Admin/PIT Lead can still create teams and schedules in the system.

Add new flow:
Admin uploads the school's roster/schedule template.
DefenSYS maps it to teams, schedules, and panel assignments.
Admin reviews and confirms before anything is saved.
```

This matches what the admin is asking for: the system should adapt to the template she already prepares, instead of forcing her to recreate the same template every defense cycle.

## What The Admin Is Really Asking For

From the screenshots and feedback, there are two related but different imports.

### 1. Roster Import

The first template is a team roster:

```text
Team Name
Capstone Project
Adviser
Team Members
```

The admin said the current bulk import for team roster is now good because that is what the system already does. The missing part is template compatibility. Her file uses a human-readable roster layout where one team spans multiple member rows, often with merged cells in Excel.

What the system should do:

- Accept the admin's roster template shape.
- Fill down repeated team-level values from merged cells.
- Group multiple member rows into one team.
- Match students by full name or student ID, as the current bulk import already supports.
- Match adviser by full name or faculty ID, as the current bulk import already supports.
- Reuse the current team import preview and validation behavior.

### 2. Schedule And Panel Import

The second template extends the roster with schedule and panel columns:

```text
Time
Team Name
Capstone Project
Adviser
Team Members
Chair
Panel Member 1
Panel Member 2
Panel Member 3
Documenter
```

This is the bigger workflow improvement. The admin creates a defense schedule for a stage and assigns panel members per team in that sheet. She wants to import that work into DefenSYS, so each team gets its schedule and assigned panel without recreating it team-by-team in the scheduler.

What the system should do:

- Admin uploads the schedule template.
- DefenSYS reads the defense stage, date, room/default room, semester, and schedule details from the uploaded file when those values are present.
- Admin only confirms the detected context or fills missing/ambiguous values.
- DefenSYS parses each team block.
- DefenSYS matches each team to an existing `StudentTeam`.
- DefenSYS matches Chair/Panel Member/Documenter names to faculty users.
- DefenSYS creates `DefenseSchedule` rows.
- DefenSYS creates panel assignments tied to each schedule.
- Existing scheduler conflict validation still applies.
- Admin sees a review table before final confirmation.

## Current System Fit

The current system already has most of the foundation.

Existing team import:

- `backend/modules/student_teams/bulk_import.py`
- Supports full-name matching for students and advisers.
- Builds team payloads for `StudentTeam`.
- Provides preview rows and readable validation issues.
- Frontend has a bulk import review table and persistent draft behavior.

Existing schedule creation:

- `backend/modules/defense/scheduler/models.py`
- `DefenseSchedule` stores semester, team, defense stage or PIT event, date, start time, duration, room, status, rubric, and creator.
- `SchedulePanelist` links schedule to faculty/admin users marked as `is_panelist`.
- Current serializers already validate:
  - active semester
  - capstone stage requirement
  - PIT event requirement
  - published panel rubric requirement
  - room overlap
  - panelist overlap
  - duplicate team schedule for the same stage/event
  - PIT Lead scope rules
  - team readiness for Capstone stages

So the import should not bypass scheduler logic. It should feed parsed rows into the same validation rules.

## Important Scope Decision

The current flow should remain as-is.

This import should be additive:

```text
Defense Scheduler
  - Manual schedule create
  - Generate plan
  - Confirm generated plan
  - Import admin schedule template
```

The import path should create the same records as the manual/generate path. That means the panel is still tied to the schedule, which is correct. The difference is that the admin can bulk-create those schedule-panel links from her prepared file.

## Template Compatibility Strategy

The admin should not have to rebuild a DefenSYS-specific spreadsheet every time.

Recommended approach:

1. Add an "Import From School Template" action.
2. Support the admin's current layout as a built-in import profile.
3. Let the system remember the mapping profile after first setup.
4. Provide a preview table where parsed rows can be fixed before import.

The parser should handle:

- `.xlsx` files with merged cells.
- CSV fallback, if the admin exports the sheet.
- Team-level columns that appear once per merged block.
- Member rows where only `Team Members` changes.
- Faculty names in short form, such as last name only, with warnings when ambiguous.
- Time ranges like `9:00AM-9:30AM`.

The system can still offer "Download DefenSYS CSV Template" for users who want the clean system format, but the admin's real working template should be supported directly.

## Recommended Import Modes

### Mode A: Roster Template Import

Purpose:

Create or update teams from the admin's roster sheet.

Required context before upload:

- Scope: Capstone or PIT.
- Semester.
- Year level, if not inferable.
- Whether adviser is required.

Parsed output:

```text
team_name
project_title
adviser
members[]
leader
year_level
section
```

Recommended leader rule:

If the school template does not identify a leader, the preview should require the admin to choose one, or default to the first listed member only after explicit confirmation.

### Mode B: Schedule And Panel Template Import

Purpose:

Create schedule rows and panel assignments for an incoming defense stage.

Context handling:

- The uploaded file should be treated as the primary source for stage, date, time, room, and team-panel assignments.
- If the file includes semester or school year, DefenSYS should detect it and show it in preview.
- If the file does not include semester, DefenSYS should default to the active semester and warn the admin.
- If the file includes defense stage text, DefenSYS should match it to an active `DefenseStage`.
- If the file does not include defense stage text, DefenSYS should ask the admin to choose the stage before confirmation.
- If the file includes room per row, use the row room.
- If the file includes one room for the whole sheet, use that room for all rows.
- If room is missing, ask the admin for a default room before confirmation.
- Panel rubric should be resolved from the selected/detected stage grading configuration, not typed manually every import.
- Slot duration should be parsed from the time range; only ask for a fallback duration when the file has start times without end times.

Parsed output:

```text
team
start_time
end_time or slot_duration
chair
panel_member_1
panel_member_2
panel_member_3
documenter
```

Recommended behavior:

- The schedule import should require teams to already exist by default.
- It may offer an advanced option to create missing teams from the same file, but Phase 1 should avoid combining too many writes in one confirmation.
- If a row references a team that is not ready for the selected stage, block that row.
- If a panelist name matches multiple faculty users, block that row and ask for a specific user.
- If a documenter is not meant to grade, do not add the documenter to `SchedulePanelist` as a grading panelist.

## Panel Role Design

This is the one place where the data model needs careful thought.

Current model:

```text
DefenseSchedule
  -> SchedulePanelist(panelist, order)
```

Current limitation:

- The system knows the ordered list of panelists.
- The system does not know who is Chair.
- The system does not know who is Documenter.
- Every `SchedulePanelist` is treated as a panelist with grading responsibility.

The admin's template has role-specific columns:

```text
Chair
Panel Member 1
Panel Member 2
Panel Member 3
Documenter
```

Recommended Phase 1 model:

Add a role field to `SchedulePanelist`:

```text
role = chair | panelist | documenter
order = 0, 1, 2, 3...
grades_required = true | false
```

Suggested rules:

- Chair: `role = chair`, `grades_required = true`.
- Panel Member 1/2/3: `role = panelist`, `grades_required = true`.
- Documenter: `role = documenter`, `grades_required = false` unless the admin explicitly says documenters also grade.

Why this matters:

If the documenter is stored as a normal panelist today, they may receive panelist grading access and affect grade completion logic. That may be wrong. We need to represent the role cleanly so the schedule can show the documenter without accidentally requiring a grade from them.

Alternative if we want less model impact:

Keep `SchedulePanelist` only for graders and add a separate schedule metadata field or assignment model for documenter. This is safer if documenters never grade.

Recommended decision:

Use a more general assignment model or extend `SchedulePanelist` only if grading logic can respect `grades_required`.

## Proposed User Flow

### Roster Import Flow

1. Admin opens Student Teams.
2. Admin clicks Bulk Import.
3. Admin selects "School roster template".
4. Admin uploads the Excel file.
5. DefenSYS parses and groups the rows.
6. Admin reviews:
   - matched team
   - project title
   - adviser
   - members
   - leader
   - validation issues
7. Admin imports ready rows.

### Schedule And Panel Import Flow

1. Admin opens Defense Scheduler.
2. Admin clicks "Import Schedule".
3. Admin uploads the schedule/panel Excel file.
4. DefenSYS detects stage, date, semester, room, time slots, teams, and panel assignments from the file.
5. DefenSYS asks only for missing or ambiguous context.
6. DefenSYS parses rows into schedule candidates.
7. Admin reviews:
   - time slot
   - team match
   - project title match
   - adviser match
   - chair
   - panel members
   - documenter
   - conflicts and warnings
8. Admin confirms.
9. DefenSYS creates schedules and panel assignments.
10. The created schedules appear in the normal Defense Scheduler and Defense Board.

## Validation And Warnings

Block import when:

- Team cannot be matched.
- Team is not in the selected semester.
- Team is not endorsed or ready for the selected Capstone stage.
- Time cannot be parsed.
- Room is missing and no default room was selected.
- Panelist cannot be matched to an active faculty/admin user.
- Panelist is not marked as eligible `is_panelist`.
- Same room has an overlapping active schedule.
- A selected panelist has an overlapping active schedule.
- Team already has a scheduled or completed defense for that stage.

Warn but allow confirmation when:

- Adviser in the sheet differs from the adviser in DefenSYS.
- Project title in the sheet differs from the stored project title.
- Member list differs from the stored team roster.
- Documenter is not a panelist and will be attached only as non-grading staff.
- Name match used a low-confidence fallback, such as last-name-only match.

Never silently create faculty users from panel names. Faculty accounts and panelist eligibility should still be controlled by Admin user management.

## Data Matching Rules

Team matching priority:

1. Exact team name within selected semester and scope.
2. Exact team name plus project title.
3. Project title match if team name changed, with warning.
4. Manual selection in preview when ambiguous.

Student matching priority:

1. Student ID or username, if present.
2. Exact full display name.
3. Manual selection in preview when ambiguous.

Faculty matching priority:

1. Faculty ID or username, if present.
2. Exact full display name.
3. Exact last name only when unique among active faculty.
4. Manual selection in preview when ambiguous.

Time parsing:

```text
9:00AM-9:30AM -> start_time 09:00, slot_duration 30
9:30AM-10:00AM -> start_time 09:30, slot_duration 30
10:00-10:30 -> start_time 10:00, slot_duration 30
```

The preview should show normalized time before confirmation.

## Recommended Backend Shape

Add schedule import helpers beside the scheduler module:

```text
backend/modules/defense/scheduler/imports/
  admin_template_parser.py
  schedule_import_preview.py
```

Add endpoints:

```text
POST /api/defense/schedules/import-template/preview/
POST /api/defense/schedules/import-template/confirm/
```

Preview endpoint:

- Accepts uploaded file plus optional fallback context for values the file does not contain.
- Parses the file.
- Detects stage, date, semester, room, time slots, teams, and panel assignments where possible.
- Returns normalized rows, matched IDs, warnings, and blocking issues.
- Does not write schedules.

Confirm endpoint:

- Accepts approved preview rows.
- Revalidates everything server-side.
- Creates schedules using the same rules as `DefenseScheduleWriteSerializer` or a shared schedule creation service.
- Creates panel/documenter assignments.
- Returns created count and row-level failures if partial import is allowed.

Important implementation note:

The final write should not trust the preview. It must resolve IDs and re-run conflict checks again because schedules can change between preview and confirm.

## Recommended Frontend Shape

Student Teams:

- Add import source selector:
  - DefenSYS CSV template
  - School roster template
- Reuse the current review table where possible.
- Add grouped team-member display for school-template rows.

Defense Scheduler:

- Add `Import Schedule` action near Generate Plan.
- Use detected file context first, then fallback to selected scheduler context only when the file is missing needed values.
- Add an import review table with row status.
- Keep generated plan workflow untouched.

Review table columns:

```text
Row
Time
Team
Project
Chair
Panel
Documenter
Room
Status
Issues
```

Actions:

- Fix team match.
- Fix faculty match.
- Exclude row.
- Import ready rows only.
- Confirm all ready rows.

## Suggested Implementation Phases

### Phase 1: Document And Parse Template

- Store this plan.
- Add parser tests for the admin's roster and schedule layouts.
- Support filled-down team data from merged-cell style rows.
- Normalize member rows into team groups.
- Normalize time ranges.

### Phase 2: Roster Template Compatibility

- Add roster-template parser.
- Feed parsed rows into existing bulk team preview/import.
- Keep current CSV import working.
- Add tests for adviser/member full-name matching through the school template.

### Phase 3: Schedule Import Preview

- Add preview endpoint for schedule template.
- Match teams and panelists.
- Return row-level issues and warnings.
- Do not write schedules yet.

### Phase 4: Schedule Import Confirm

- Add confirm endpoint.
- Reuse scheduler validation for duplicate schedules, room conflicts, and panelist conflicts.
- Create schedules and assignments.
- Sync grade rows the same way manual schedule creation does.

### Phase 5: Panel Role Support

- Decide whether documenter is a grading panelist.
- Add role support to schedule assignments.
- Update scheduler, board, mobile panelist access, and grade completion logic if needed.

## My Recommendation

Build this as a "school template import adapter" instead of changing the core scheduling flow.

That gives the admin what she wants:

- She keeps using the template she already prepares.
- She does not recreate the same schedule and panel assignment in DefenSYS.
- The system still validates conflicts, ready teams, rubrics, and panel eligibility.
- The current manual scheduler remains available for corrections and one-off cases.

The best first implementation is:

1. Support the roster template inside Student Teams.
2. Add schedule import preview inside Defense Scheduler.
3. Require existing teams for schedule import.
4. Treat Chair and Panel Members as grading panelists.
5. Treat Documenter as non-grading until the admin confirms otherwise.

This keeps the feature useful quickly without creating grade-access mistakes.

## UI Idea If We Implement Now

The UI should feel like an import assistant, not another scheduling form.

The main design principle:

```text
Upload first.
Detect what the file contains.
Ask only for what is missing.
Preview everything before saving.
```

### Entry Point

In `Defense Scheduler`, add the import as a button in the existing page header. Do not add another sidebar tab.

```text
Import Schedule
```

Recommended header actions:

```text
Manual Schedule Form
Import Schedule
```

The current top `Generate Schedule Plan` action can be removed from the header because Step 1 already has the contextual generate action at the bottom of the setup form. Keeping only the bottom generate button is clearer because it stays near the required stage, rubric, date, room, time, and panel inputs.

The header should be for alternate entry points:

- `Manual Schedule Form` for one-off manual schedule creation.
- `Import Schedule` for uploading the admin's prepared Excel schedule.

The setup form itself should keep the bottom `Generate Schedule Plan` action because that is the natural end of the setup step.

Clicking `Import Schedule` opens a full import workflow, either as a large dialog or a dedicated in-page workspace. A dedicated workspace is better if the preview table is wide, because the admin's template has many columns.

Suggested page title:

```text
Import Defense Schedule
```

Suggested top actions:

```text
Upload File
Download Supported Format Notes
Cancel
```

### Step 1: Upload

First screen:

```text
[ Drop Excel file here ]
[ Browse File ]

Accepted:
.xlsx, .csv
```

Do not ask for stage, date, room, rubric, or semester before upload.

After upload, show a parsing state:

```text
Reading schedule template...
Detecting teams, time slots, stage, room, and panel assignments.
```

### Step 2: Detected Context Review

After parsing, show a compact context panel at the top:

```text
Detected Context

Stage: Concept Proposal
Date: June 18, 2026
Semester: 1st Semester, A.Y. 2026-2027
Room: AVR 1
Rubric: Concept Proposal Panel Rubric
Rows detected: 12 teams
Ready to import: 10
Needs attention: 2
```

Each detected item can have one of three states:

```text
Detected
Missing
Needs confirmation
```

Examples:

```text
Stage: Missing -> admin chooses from active defense stages
Room: Missing -> admin enters default room
Semester: Not in file -> defaults to active semester, admin confirms
Rubric: Auto-resolved from stage -> no manual typing
```

This keeps the system from bothering the admin when the file already has the information.

### Step 3: Import Preview Table

Below the detected context, show the parsed rows as the main work area.

Suggested columns:

```text
Status
Time
Team
Project
Adviser
Chair
Panel Members
Documenter
Room
Issues
```

Example row:

```text
Ready | 9:00 AM - 9:30 AM | Team SkyLedger | Alumni Career Tracker | Ricardo Fontanilla | Suarez | Beltran, Corpuz, Villanueva | Magbanua | AVR 1 | -
```

Rows with problems should stay visible and editable:

```text
Needs attention | 10:00 AM - 10:30 AM | Team ByteBridge | Library Seat Finder | Eduardo Padilla | Suarez | Suarez, Corpuz, Macasaet | Buenaventura | AVR 1 | Panelist "Suarez" matched multiple faculty
```

### Row Fixing Behavior

For row issues, use inline fix controls:

- Team mismatch: searchable team selector.
- Faculty ambiguity: searchable faculty selector.
- Missing room: default room field or row room field.
- Missing stage: stage selector in detected context panel.
- Time parsing issue: editable start/end time fields.
- Adviser/project mismatch: warning only unless admin chooses to update team data.

The admin should not have to leave the import screen to fix normal matching issues.

### Preview Filters

Add small filters above the table:

```text
All
Ready
Needs attention
Warnings
Excluded
```

Also add a search field:

```text
Search team, project, panelist...
```

This matters because the real schedule may have many teams.

### Confirmation Area

At the bottom or sticky footer:

```text
10 ready rows
2 rows need attention

[Import Ready Rows]
[Import All Ready Rows And Skip Issues]
[Cancel]
```

If there are blocking issues, disable full confirmation:

```text
Resolve 2 blocking issues before importing all rows.
```

Recommended first implementation:

```text
Import Ready Rows
```

This lets the admin save valid rows while fixing bad rows later.

### Success State

After import:

```text
10 schedules imported.
2 rows were not imported.
```

Then show actions:

```text
View Imported Schedules
Download Issue Report
Continue Fixing Remaining Rows
```

The imported rows should immediately appear in the normal Defense Scheduler and Defense Board, so the admin understands this is not a separate temporary feature.

### Student Teams UI Addition

In `Student Teams > Bulk Import`, add an import source choice:

```text
Import Source

( ) DefenSYS CSV Template
( ) School Roster Template
```

If `School Roster Template` is selected, the system should use the same upload-preview-confirm pattern:

```text
Upload roster
Detect teams and members
Review grouped teams
Import ready teams
```

The preview should group members under each team:

```text
Team SkyLedger
Project: Alumni Career Tracker
Adviser: Ricardo Fontanilla
Members:
- Villar, Marcus
- Ong, Patricia
- Salazar, Ethan
- Castillo, Zoe
Leader: needs selection
```

### Recommended First UI Scope

If we implement now, I would keep Phase 1 UI focused:

1. Defense Scheduler gets `Import Schedule`.
2. Upload `.xlsx` or `.csv`.
3. Detect stage/date/semester/room from file when present.
4. Preview schedule rows.
5. Match teams and faculty.
6. Import ready rows only.
7. Keep documenter as non-grading display/assignment until confirmed otherwise.

I would not add a complicated reusable mapping builder yet. Start with the admin's actual template shape. If later the school changes format, then add saved mapping profiles.

## Open Questions For The Admin

1. Does the documenter also submit grades, or are they only attached for records/minutes?
2. Is the room always the same for one imported file, or can each row have a different room?
3. Will the schedule file always include one date, or can one file contain multiple dates?
4. Does the school template always use the same column names and order?
5. Should importing the schedule also create missing teams, or should teams always be imported first from the roster flow?
6. If the sheet adviser differs from the DefenSYS adviser, should the import only warn, or should it update the team adviser after confirmation?
