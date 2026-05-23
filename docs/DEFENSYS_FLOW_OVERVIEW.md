# DefenSYS Flow Overview

For a single visual map of the full system, see [DEFENSYS_SYSTEM_FLOW_DIAGRAM.md](DEFENSYS_SYSTEM_FLOW_DIAGRAM.md).

## Purpose

This document explains the current end-to-end operational flow of DefenSYS in plain language.

It is meant to answer:

- what each major module does
- who uses each page or workflow
- how PIT and Capstone differ
- how a defense moves from setup to grading to history
- how team progression and repository publishing fit into the full system

This is a flow guide for the current prototype state of the system. It is not a database spec and it is not a replacement for lower-level model documentation.

## 1. System at a Glance

DefenSYS is a Django-based academic workflow system for:

- academic period management
- user and faculty assignment management
- student team management
- defense scheduling
- panel, adviser, and peer grading
- grade summary and stage progression
- secure project archiving in the Digital Vault

The main apps are:

- `users` -> users, academic periods, faculty assignments, teams, student academic records
- `evaluations` -> defense stages, rubrics, schedules, grading, summaries
- `vault` -> repository/archive of approved project files

## 2. Main Roles and Entry Points

### Admin

Admin is the main system configurator. Admin manages:

- school years and semesters
- defense stages
- users and bulk imports
- faculty assignments
- rubrics and criteria
- defense schedules
- grade summaries
- repository audit and vault content

### Faculty

Faculty can act in different semester-based roles:

- PIT Lead
- Adviser
- Panelist

Primary faculty entry points:

- `Grade Center` for panel grading
- `My Teams` for adviser team context and adviser grading
- `Defense Scheduler` for admin or PIT Lead scheduling work
- `Digital Vault` for repository browsing

### Student

Students mainly use:

- student dashboard
- team/project context
- peer evaluation flow
- Digital Vault browsing

## 3. Academic Structure Flow

Everything starts with the academic structure:

1. Admin creates a `SchoolYear`.
2. Admin creates one or more `Semester` records under that school year.
3. One semester is made active.
4. `YearLevel` records belong to a semester and define the academic context used by teams, rubrics, assignments, and schedules.

Important rule:

- `StudentAcademicRecord` is the source of truth for a student's semester-based academic context.
- `CustomUser` does not permanently store year level.

## 4. Student Academic Record Flow

DefenSYS uses semester-based student academic records to keep user accounts separate from changing academic level.

The normal flow is:

1. Admin imports or creates student users.
2. Admin creates or rolls over `StudentAcademicRecord` rows for the active semester.
3. Each record stores:
   - student
   - semester
   - year level
4. Team creation, Capstone eligibility, and many validation rules use these records.

This matters because:

- a student can move across semesters without rewriting the user account
- team eligibility is checked against academic records
- bulk imports can safely prepare grouped student batches for the correct semester/year level

## 5. User Import Flow

The bulk user import keeps the CSV template simple and adds batch context at the form level.

Current flow:

1. Admin opens `Bulk Import Users`.
2. Admin uploads the standard CSV template.
3. Admin chooses the batch mode:
   - `Student Batch`
   - `Faculty / General Users`
4. If the import is a student batch, the form also captures:
   - batch year level
   - target semester or active semester
5. Student-batch imports can create the initial student academic context for imported student rows.
6. Faculty/general imports ignore student-only options and remain separate.

This keeps:

- one CSV template
- student context captured safely at import time
- faculty imports unaffected

## 6. Faculty Assignment Flow

Faculty accounts are generic by default. Role behavior comes from semester-based assignments.

Typical admin flow:

1. Create or import faculty users.
2. Assign faculty roles for the active semester and year level.
3. Roles then unlock the correct pages and actions.

Examples:

- a panelist can grade in Grade Center
- an adviser can grade advised teams in My Teams
- a PIT Lead can help manage teams and scheduling for assigned scope

## 7. Team Management Flow

Teams are created after students already have valid academic records for the semester.

General team flow:

1. Admin or PIT Lead opens `Teams`.
2. A team is created with:
   - project title
   - leader
   - members
   - year-level snapshot
   - adviser when applicable
3. Validation checks:
   - students belong to the correct academic context
   - members share the same year-level context
   - adviser eligibility rules are respected

### PIT vs Capstone Boundary

Lower-year PIT logic remains available for:

- 1st Year, both semesters
- 2nd Year, both semesters
- 3rd Year, 1st semester

Capstone team creation is restricted to:

- 3rd Year, 2nd semester
- 4th Year, 1st semester

That restriction is scoped to the Capstone team creation path. PIT logic elsewhere is intentionally left untouched.

## 8. Team Status Meaning

`Team.status` is currently the stage gate for multi-stage Capstone progression:

- `Pending` -> awaiting final posted result for the current stage
- `Approved` -> current stage passed and the team may proceed
- `Failed` -> current stage did not pass and revisions are needed

Important boundary:

- this is not the same thing as Grade Center workflow status
- Grade Center tracks grading completion
- `Team.status` tracks the progression result used by the team flow

Current rule:

- when the authoritative posted Capstone stage score is complete:
  - `>= 75` -> `Approved`
  - `< 75` -> `Failed`
- draft saves do not update `Team.status`

## 9. Defense Stage and Rubric Architecture

DefenSYS uses dynamic defense stages plus one standard rubric model with an `evaluation_type`.

### Defense Stages

Admin manages `DefenseStage` records for stage-driven workflows such as:

- Concept Proposal
- later Capstone stages
- Final stage

The `color` field still exists in the model, but it is hidden from the custom stage create/edit UI to keep the screen simpler.

### Standard Rubric Path

The standard `Rubric` model now carries:

- `stage`
- `evaluation_type`

Supported evaluation types:

- `panel`
- `adviser`
- `peer`

This means the system can resolve a rubric by:

- defense stage
- evaluation type

### Separated Runtime Boundary

The architecture is intentionally separated:

- panel rubric path -> standard `Rubric`
- adviser rubric path -> standard `Rubric`
- peer rubric path -> standard `Rubric` for Capstone, with legacy `PeerRubric` fallback where still needed

This keeps rubric resolution consistent in Capstone while still preserving older fallback behavior for lower-year or legacy paths.

## 10. Rubric Creation Flow

Rubrics are managed from the Rubric Engine.

Admin flow:

1. Open `Rubric Engine`.
2. Create a rubric for a semester and year level.
3. Choose stage and evaluation type.
4. Add weighted criteria.
5. Configure panel/adviser/peer weights as needed.

Important current rule:

- adviser rubric creation/editing is restricted to Capstone-valid semester/year-level combinations
- panel and peer rubric flows are still kept generic unless a later phase narrows them further

## 11. Defense Scheduling Flow

The Defense Scheduler is the event-centered scheduling screen.

Scheduler flow:

1. Admin or PIT Lead chooses:
   - stage
   - panel rubric
   - date and time
   - venue details if needed
   - assigned panelists
2. The scheduler creates a `DefenseSchedule`.
3. The scheduler also creates or links the matching `Evaluation` context used for grading.

Important current scheduler rules:

- only panel rubrics are offered in the scheduler
- adviser and peer are not scheduled as separate defense events
- adviser and peer are treated as follow-up grading windows tied to the same stage evaluation

### Existing Schedules vs Defense History

On the scheduler page:

- `Existing Schedules` now shows non-completed rows
- `Defense History` shows rows where `DefenseSchedule.status == "Completed"`

For this page, history is event-based, not grading-based.

### Automatic Schedule Completion

When the linked evaluation becomes fully grading-complete for that defense context, the matched schedule is automatically marked `Completed`.

This allows finished defenses to move into Defense History without relying on manual schedule edits.

## 12. Live Defense Detection Flow

The system now treats a defense as live when the current local time is inside the scheduled window:

- start time is inclusive
- end time is exclusive

This is used so the faculty dashboard and Grade Center can correctly recognize:

- upcoming slots
- live/current slots
- past slots

The dashboard logic and evaluation status logic were aligned so live scheduled defenses can be recognized consistently.

## 13. Evaluation Creation and Matching Flow

Every scheduled defense works through an `Evaluation` context.

Current behavior:

1. A schedule is created.
2. The system creates or links the related evaluation.
3. Shared matching logic connects evaluation records back to the schedule using the team/stage/rubric context.
4. That match is reused by:
   - faculty dashboard live-slot behavior
   - panelist visibility
   - Grade Center status
   - schedule completion sync

Important boundary:

- Capstone detection uses the semantic Capstone rule, not raw `YearLevel.is_capstone`
- this prevents stale flag mismatches from breaking runtime matching

## 14. Follow-up Setup Flow

After the defense event is scheduled, adviser and peer follow-up settings are configured on the evaluation.

The current setup page is `Follow-up Setup`.

It allows admin to manage:

- `allow_adviser_grading`
- `allow_peer_evaluation`
- `adviser_deadline`
- `peer_deadline`

Current meaning:

- panel = live defense event
- adviser = deadline-based follow-up
- peer = deadline-based follow-up

## 15. Panel Grading Flow

Panel grading is the main defense-event grading flow.

Runtime flow:

1. Assigned panelist reaches the evaluation through `Grade Center`.
2. The page loads the stage-aware panel rubric:
   - `Rubric(stage + evaluation_type='panel')`
3. The panelist scores each criterion.
4. The panelist can save draft scores.
5. When grades are posted, the panel submission becomes locked.
6. Grade Center and Grade Summary update using the posted records.

Current status behavior:

- before start time -> can remain `Not Started`
- during live schedule window -> becomes `In Progress`
- after all required grading is finished -> `Grading Complete`

## 16. Adviser Grading Flow

Adviser grading is now Capstone-standard and rubric-driven.

Primary adviser path:

- advisers enter through `My Teams`
- a team row can expose an `Adviser Grade` action when adviser grading is enabled for that evaluation

Current Capstone runtime:

1. The adviser page resolves:
   - `Rubric(stage + evaluation_type='adviser')`
2. The adviser enters criterion scores using the standard rubric criteria.
3. The system computes the derived adviser total automatically.
4. That derived total is stored back into `AdviserRating.score` for compatibility with existing summary logic.

Current UI direction:

- Capstone-standard mode is rubric-driven
- the old manual 0-100 adviser input is no longer shown there
- fallback single-score behavior remains only where legacy/fallback is still actually needed

## 17. Peer Evaluation Flow

Peer evaluation is also stage-aware in Capstone.

Current Capstone runtime:

1. The system resolves:
   - `Rubric(stage + evaluation_type='peer')`
2. That standard rubric acts as the actual source for Capstone peer criteria.
3. A runtime bridge feeds the existing `PeerEvaluation` and `PeerRating` save flow.

Important boundary:

- Capstone uses the standard peer rubric path
- lower-year and legacy peer flows can still fall back to legacy `PeerRubric` behavior where needed

## 18. Deadlines on Adviser and Peer Pages

Adviser and peer follow-up pages now show deadline visibility cues:

- `Open`
- `Closed`
- `Not set`

These are display-only in the current phase.

They do not hard-block submission yet. They are there to make the follow-up window visible before stricter enforcement is considered.

## 19. Grade Center Flow

Grade Center is mainly the evaluation workflow hub for panel grading and evaluation monitoring.

It shows:

- grading workflow status
- team and stage context
- live or matched schedule context
- access to grade sheets and summaries

Important meaning:

- `Grading Complete` means the evaluation/grading workflow is complete for that evaluation context
- it does not automatically mean the team passed the stage

This distinction matters in multi-stage Capstone.

## 20. Grade Summary Flow

Grade Summary is the place where the full evaluation result is reviewed.

It brings together:

- panel totals
- adviser totals
- peer totals
- weighted overall grade
- follow-up setup entry points
- stage/team context

For Capstone-standard adviser grading, Grade Summary can also show the adviser criterion breakdown so the derived adviser total is auditable.

## 21. Team Progression Flow

For multi-stage Capstone, progression is intentionally separate from grading workflow completion.

Current progression idea:

1. A defense is scheduled for a stage.
2. Panel, adviser, and peer grading happen as configured.
3. Once the authoritative posted stage score is complete:
   - the team is marked `Approved` or `Failed`
4. That `Team.status` acts as the stage gate for the next stage.

Student/team wording now reflects this more clearly:

- `Grading Status` = evaluation workflow state
- `Team Result` = progression/result gate

## 22. Student-Facing Flow

From the student side, the typical flow is:

1. Log in to the student dashboard.
2. See current team/project context.
3. See team result and latest defense context.
4. Complete peer evaluation when enabled.
5. Browse the Digital Vault when appropriate.

Important current limitation:

- student pages can safely show latest stage/session context and team result
- a fully separate per-stage verdict model does not yet exist
- the current student-side result still depends on `Team.status`

## 23. Digital Vault Flow

The vault is the secure archive/repository side of DefenSYS.

High-level vault flow:

1. Approved or finalized project content is prepared for archive.
2. Admin or authorized faculty uploads project assets and documents.
3. The project becomes browsable in the Digital Vault.
4. Students and faculty can browse allowed repository content.
5. Admin can inspect historical files through Repository Audit.

The vault is intentionally separate from the live grading workflow. It is the repository/archive destination, not the grading engine.

## 24. Current Status Meaning Cheatsheet

### Grading Status

Used in Grade Center and evaluation summaries.

Examples:

- `Not Started`
- `In Progress`
- `Grading Complete`

Meaning:

- where the evaluation workflow currently stands

### Team Result

Used on team/student-facing pages.

Examples:

- `Pending`
- `Approved`
- `Failed`

Meaning:

- whether the team is still awaiting the final posted stage result
- whether the team may proceed
- whether revisions are required before proceeding

### Schedule Status

Used by the scheduler page.

Examples:

- `Scheduled`
- `Ongoing`
- `Completed`
- `Cancelled`

Meaning:

- the event/schedule state of the defense session itself

## 25. Recommended End-to-End Mental Model

The cleanest way to understand DefenSYS is:

1. Academic periods define scope.
2. Student academic records define semester-based student context.
3. Teams group students for PIT or Capstone work.
4. Defense stages define the stage structure.
5. Standard rubrics define stage-specific scoring rules by evaluation type.
6. The scheduler creates the defense event and linked evaluation.
7. Panel grading happens through the live defense flow.
8. Adviser and peer grading happen as follow-up flows on that same evaluation.
9. Grade Summary composes the full stage result.
10. `Team.status` becomes the stage gate for progression.
11. Completed defenses move into Defense History.
12. Approved/finalized outputs can later be archived in the Digital Vault.

## 26. Current Design Boundaries

To avoid confusion while the prototype continues to evolve, keep these boundaries in mind:

- panel -> Grade Center and scheduled defense flow
- adviser -> My Teams and follow-up grading flow
- peer -> student peer flow, with standard-rubric Capstone runtime
- schedule completion -> event history concept
- grading completion -> evaluation workflow concept
- team result -> progression concept

Those are related, but they are not identical, and the current system deliberately keeps them separate.

