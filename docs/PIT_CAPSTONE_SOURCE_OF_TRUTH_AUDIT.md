# PIT And Capstone Source-Of-Truth Audit

## Why This Audit Exists

This audit traces the PIT and Capstone flows as they exist in the codebase, with special focus on the PIT Lead 3rd Year case during a 3rd Year 2nd Semester Capstone intake term.

The important distinction is:

- PIT is event-based.
- Capstone is defense-stage-based.
- A Capstone intake term may close active PIT roster/scheduling writes for a PIT Lead, but it should not turn the PIT Lead workspace into a Capstone scheduler experience.

## High-Level Finding

The backend already has a clear PIT term mode source of truth for the cohort/team flow:

- `student_teams.term_scope.pit_lead_operating_mode()`
- `student_teams.term_scope.term_scope_payload()`
- `student_teams.views.options_payload()`
- `StudentTeamsScreen(mode: TeamListMode.pitLead)`

That is why the Cohort/Student Teams screens can show the correct message:

> Capstone intake term - your PIT roster for this year is historical only.

The Defense Scheduler screen does not consume the same PIT operating-mode source of truth. Instead, the frontend scheduler keeps a local `_scope` value that defaults to `capstone`, then tries to switch to `pit` after reading the faculty dashboard role snapshot.

That creates a UI source-of-truth conflict:

- The sidebar says the user is `PIT Lead - 3rd Year`.
- The cohort screen says PIT is historical/audit-only.
- The scheduler can still render the Capstone stage-based form if local `_scope` remains `capstone`.

Backend guards reduce data damage, but the UI can still mislead the user into thinking a PIT Lead is operating the Capstone scheduler.

## Flow Model

### PIT Flow

PIT is event-based.

Core identity:

- `DefenseSchedule.scope = pit`
- `DefenseSchedule.event_name`
- `PitEventGradingConfig.event_name`
- `TeamGrade.scope = pit`
- `TeamGrade.pit_event_config`
- `TeamGrade.stage_label` as a display snapshot of the PIT event name

Expected lifecycle:

1. PIT Lead manages a PIT cohort/team roster for the assigned year.
2. PIT Lead creates or generates schedules for a PIT event.
3. Schedule creation/schedule confirmation syncs PIT `TeamGrade` rows for that event.
4. Rubrics and grading rules are attached through `PitEventGradingConfig`.
5. Peer evaluation must resolve to one explicit PIT event context.
6. Published PIT results can feed Repository Vault upload/audit workflows.

PIT should not use `DefenseStage` as its source of truth.

### Capstone Flow

Capstone is defense-stage-based.

Core identity:

- `DefenseStage`
- `StageDeliverable`
- `TeamStageProgress`
- `DefenseSchedule.scope = capstone`
- `DefenseSchedule.defense_stage`
- `TeamGrade.scope = capstone`
- `TeamGrade.defense_stage`
- `TeamGrade.stage_label` as a display snapshot of the stage label

Expected lifecycle:

1. Admin configures Capstone defense stages and deliverables.
2. Capstone teams progress through explicit `TeamStageProgress` rows.
3. Admin schedules a defense for a stage.
4. Schedule creation/schedule confirmation syncs Capstone `TeamGrade` rows.
5. Published grade updates stage progress and downstream deliverable/repository state.

Capstone should not use PIT event names as its source of truth.

## Source-Of-Truth Map

| Concern | Source of truth | Important consumers | Notes |
| --- | --- | --- | --- |
| Faculty role | `User.role`, `User.is_pit_lead`, `User.is_adviser`, `User.pit_lead_year` | dashboards, scheduler, team scopes | PIT Lead year must be enforced on backend writes, not only frontend filters. |
| Active semester | `Semester.is_active`, `Semester.label`, `Semester.school_year`, `Semester.capstone_program_phase` | teams, scheduler, grade center, repository | Active semester describes the calendar term. It should not by itself decide whether PIT UI becomes Capstone UI. |
| Capstone mode | `academic_period_management.capstone_mode.capstone_operating_mode()` | student teams, academic period transition logic | Defines Capstone intake/continuation behavior. |
| PIT operating mode | `student_teams.term_scope.pit_lead_operating_mode()` | PIT cohort/team screens | Defines whether PIT Lead roster is active or audit/historical. Scheduler does not currently use this enough. |
| Team visibility | `authentication_access_control.scopes.visible_teams_for()` | APIs that list teams | Shared backend visibility filter. |
| Schedule visibility | `authentication_access_control.scopes.visible_schedules_for()` | scheduler/board APIs | Shared backend schedule filter. |
| Grade visibility | `authentication_access_control.scopes.grade_records_for()` | grade center APIs | Shared backend grade filter. |
| Capstone stage identity | `DefenseStage` and `TeamStageProgress` | scheduler, grade center, deliverables | Authoritative for Capstone progress. |
| PIT event identity | `PitEventGradingConfig` plus `DefenseSchedule.event_name` | scheduler, grade center, peer evaluation | Authoritative for PIT event grading. |
| Display label | `stage_label` on schedules/grades/vault entries | reports, UI labels | Snapshot only. Do not use as authoritative identity when a real FK exists. |
| Repository PIT completion | `repository.audit.services.completed_pit_events()` | Repository Vault | Currently depends partly on event names/year hints. This is fragile if event config lacks explicit year. |

## Endpoint Map

### Faculty Dashboard And PIT Cohort

| Endpoint | Backend view | Purpose |
| --- | --- | --- |
| `GET /api/dashboards/faculty/` | `FacultyDashboardView.get()` | Returns faculty workspace data and role flags used by the frontend shell. |
| `GET /api/dashboards/pit-lead/cohort/` | `PitLeadCohortView.get()` | Returns PIT Lead cohort data. |
| `GET /api/student-teams/` | `StudentTeamListCreateView.get()` | Lists teams/students/options with term metadata. |
| `POST /api/student-teams/` | `StudentTeamListCreateView.post()` | Creates teams when allowed by term and role. |
| `GET /api/student-teams/<team_id>/` | `StudentTeamDetailView.get()` | Reads one team. |
| `DELETE /api/student-teams/<team_id>/` | `StudentTeamDetailView.delete()` | Deletes a team when allowed. |
| `GET /api/student-teams/<team_id>/adviser-history/` | `TeamAdviserHistoryView.get()` | Reads adviser history. |

Important functions:

- `student_teams.views.options_payload()`
- `student_teams.term_scope.term_scope_payload()`
- `student_teams.term_scope.pit_lead_operating_mode()`
- `student_teams.term_scope.pit_roster_student_ids()`
- `student_teams.term_scope.assert_active_semester_for_create()`
- `student_teams.term_scope.assert_team_writable()`

### Defense Scheduler

| Endpoint | Backend view | Purpose |
| --- | --- | --- |
| `GET /api/defense/schedules/` | `DefenseScheduleListCreateView.get()` | Lists visible schedules and scheduler options. |
| `POST /api/defense/schedules/` | `DefenseScheduleListCreateView.post()` | Creates a manual schedule. |
| `GET /api/defense/schedules/pit-event-config/` | `PitEventConfigLookupView.get()` | Reads PIT event grading config for an event. |
| `POST /api/defense/schedules/pit-event-config/` | `PitEventConfigLookupView.post()` | Creates/updates PIT event grading config. |
| `POST /api/defense/schedules/generate-plan/` | `DefenseScheduleGeneratePlanView.post()` | Generates a schedule plan without saving final schedules. |
| `POST /api/defense/schedules/confirm-plan/` | `DefenseScheduleConfirmPlanView.post()` | Saves generated schedule slots. |
| `DELETE /api/defense/schedules/<schedule_id>/` | `DefenseScheduleDetailView.delete()` | Cancels/deletes a schedule. |

Important functions:

- `defense.scheduler.serializers.schedule_options_payload()`
- `DefenseScheduleWriteSerializer._resolve_team()`
- `DefenseScheduleWriteSerializer._validate_pit_team_scope()`
- `DefenseScheduleGeneratePlanSerializer._ready_teams()`
- `DefenseScheduleConfirmPlanSerializer.validate()`

Frontend functions:

- `DefenseSchedulerScreen._scope`
- `DefenseSchedulerScreen.initState()`
- `DefenseSchedulerScreen._buildStepOne()`
- `DefenseSchedulerScreen._generatePlan()`
- `DefenseSchedulerScreen._confirmPlan()`
- `DefenseSchedulerScreen._showManualDialog()`
- `DefenseSchedulerScreen._teamsForScope()`
- `DefenseSchedulerProvider.fetchSchedules()`
- `DefenseSchedulerProvider.generatePlan()`
- `DefenseSchedulerProvider.confirmPlan()`
- `DefenseSchedulerProvider.createSchedule()`
- `DefenseSchedulerProvider.fetchPitEventConfig()`

### Defense Board And Panelist Grading

| Endpoint | Backend view | Purpose |
| --- | --- | --- |
| `GET /api/defense/schedules/panelist-assignments/` | `PanelistAssignmentsView.get()` | Lists assigned defenses for panelists. |
| `GET /api/defense/schedules/panelist-results/` | `PanelistResultsView.get()` | Lists panelist results. |
| `POST /api/defense/schedules/submit-grades/` | `PanelistGradeSubmissionView.post()` | Submits panelist grades. |
| `GET /api/defense/schedules/guest-assignments/` | `GuestPanelistAssignmentsView.get()` | Lists guest panelist assignments. |
| `GET /api/defense/schedules/guest-panelist-results/` | `GuestPanelistResultsView.get()` | Lists guest panelist results. |
| `POST /api/defense/schedules/guest-submit-grades/` | `GuestPanelistGradeSubmissionView.post()` | Submits guest panelist grades. |

### Grade Center And Peer Evaluation

| Endpoint | Backend view | Purpose |
| --- | --- | --- |
| `GET /api/grading/grades/` | `GradeCenterListView.get()` | Lists grade records and options. |
| `POST /api/grading/grades/sync/` | `GradeCenterSyncView.post()` | Syncs schedule/team state into grade records. |
| `GET/POST /api/grading/grades/evaluation-settings/` | `CapstoneEvaluationSettingsView` | Reads/writes Capstone evaluation settings. |
| `GET/POST /api/grading/grades/group-settings/` | `GradeCenterGroupSettingsView` | Reads/writes group grading settings. |
| `GET /api/grading/grades/<grade_id>/` | `GradeCenterDetailView.get()` | Reads one grade record. |
| `POST /api/grading/grades/<grade_id>/publish/` | `GradeCenterPublishView.post()` | Publishes grade and triggers downstream updates. |
| `POST /api/grading/grades/peer-evaluations/` | `StudentPeerEvaluationSubmitView.post()` | Submits peer evaluation. |

Important functions:

- `grading.grades.views.options_payload()`
- `GradeContextService.get_for_current_student_peer_context()`
- `StageCompletionService`
- `update_group_settings()`
- `peer_criteria_payload()`
- `peer_submissions_for_evaluator()`

### Repository Audit

| Endpoint | Backend view | Purpose |
| --- | --- | --- |
| `GET /api/repository/audit/` | `RepositoryAuditListView.get()` | Lists repository audit entries. |
| `POST /api/repository/audit/upload-pit/` | `RepositoryAuditUploadPitView.post()` | Uploads PIT repository file. |
| `POST /api/repository/audit/upload-capstone/` | `RepositoryAuditUploadCapstoneView.post()` | Uploads Capstone repository file. |
| `POST /api/repository/audit/override-status/` | `RepositoryAuditOverrideStatusView.post()` | Overrides repository audit status. |
| `GET /api/repository/audit/trail/` | `RepositoryAuditTrailView.get()` | Reads repository audit trail. |
| `GET /api/repository/audit/export/` | `RepositoryAuditExportView.get()` | Exports repository audit data. |

Important functions:

- `repository.audit.services.completed_pit_events()`
- `repository.audit.services.pit_vault_upload_queue()`
- `repository.audit.services.repository_scope()`
- `repository.audit.grouping.options_payload()`

## Risk Findings

### 1. Scheduler UI Has A Local Scope Conflict

Location:

- `frontend/lib/screens/web/admin/defense_scheduler_screen.dart`

The scheduler initializes:

- `_scope = 'capstone'`

Then, after the first frame, it reads dashboard role data:

- if `roles['pit_lead'] == true && roles['adviser'] != true`, set `_scope = 'pit'`

Why this is dangerous:

- If dashboard role data is stale, empty, late, or shaped differently than expected, the scheduler keeps the Capstone default.
- The PIT Lead can see Capstone stage fields even though the current workspace is PIT Lead.
- A Capstone intake term can look like it changed the PIT Lead's scheduling interface into Capstone scheduling.

Good fix direction:

- Scheduler mode should come from the scheduler/options backend payload, not from a frontend default and not only from dashboard role state.
- For a PIT Lead-only user, backend scheduler options should explicitly return `scheduler_mode = pit`.
- It should also return `pit_operating_mode = audit` when PIT scheduling is closed for the term.

### 2. PIT Audit Mode Exists But Is Not Shared With Scheduler UI

Location:

- `backend/modules/student_teams/term_scope.py`
- `frontend/lib/screens/web/admin/student_teams_screen.dart`
- `frontend/lib/screens/web/admin/defense_scheduler_screen.dart`

The team/cohort flow already understands PIT audit mode. The scheduler screen does not mirror it.

Why this is dangerous:

- Different PIT screens can tell different stories in the same session.
- Cohort says historical-only, while Scheduler shows active Capstone controls.
- Users may think PIT Lead permissions were upgraded or moved to Capstone.

Good fix direction:

- Reuse `pit_lead_operating_mode()` in `schedule_options_payload()`.
- Expose a scheduler-specific closed-state message.
- Render a PIT event-based scheduler shell with disabled creation controls or history-only state when mode is audit.

### 3. Backend Options Partly Protect PIT Leads, But UI Can Still Render Wrong Fields

Location:

- `backend/modules/defense/scheduler/serializers.py`
- `frontend/lib/screens/web/admin/defense_scheduler_screen.dart`

`schedule_options_payload()` already limits some returned options for PIT Lead users. For example, PIT Lead users should not receive Capstone defense stages.

Why this is dangerous:

- If the frontend remains in Capstone scope, it can render an empty Capstone stage dropdown.
- Empty dropdowns look like missing data, not a role/scope problem.
- This hides the real issue: the scheduler mode was wrong before the user interacted with the form.

Good fix direction:

- Add explicit mode flags to scheduler options:
  - `scheduler_mode`
  - `can_schedule_pit`
  - `can_schedule_capstone`
  - `pit_operating_mode`
  - `operating_message`

### 4. Active Semester And User Track Are Separate Truths

The active semester may be Capstone intake, but the user's workspace is still PIT Lead.

Why this matters:

- Active semester determines whether new PIT assignments/schedules are open.
- User track determines whether the scheduler UI is PIT/event-based or Capstone/stage-based.

Dangerous interpretation:

- "Current term is Capstone, therefore the PIT Lead scheduler should show Capstone form."

Correct interpretation:

- "Current term is Capstone intake, therefore PIT Lead 3rd Year scheduling may be audit/closed, but the PIT Lead scheduler remains PIT/event-based."

### 5. Scope Filtering Is Duplicated Across Frontend And Backend

Locations:

- `authentication_access_control.scopes.visible_teams_for()`
- `authentication_access_control.scopes.visible_schedules_for()`
- `DefenseScheduleGeneratePlanSerializer._ready_teams()`
- `DefenseSchedulerScreen._teamsForScope()`

Why this is dangerous:

- Backend and frontend can drift.
- The UI may show teams that backend rejects, or hide teams backend would allow.
- The frontend can accidentally infer Capstone/PIT from team level strings.

Good fix direction:

- Keep backend as the enforcement layer.
- Let frontend use backend-provided mode, allowed actions, and filtered options.
- Use frontend filtering only as presentation convenience.

### 6. PIT Peer Evaluation Must Not Depend On "Latest Grade"

This was previously dangerous because PIT is event-based and a team can have multiple PIT events.

Bad behavior:

- Student peer evaluation resolves the target event by latest PIT grade.

Danger:

- Peer answers can attach to the wrong PIT event.
- Published event results can become mixed.

Good direction:

- Resolve an explicit event context.
- If multiple PIT events exist and no single open peer-grading context is clear, fail closed instead of guessing.

### 7. Repository PIT Event Detection Is Fragile

Location:

- `repository.audit.services.completed_pit_events()`

The repository audit flow groups completed PIT events. It currently relies partly on event naming/year hints because `PitEventGradingConfig` does not appear to carry a fully explicit year-level identity.

Why this is dangerous:

- Event names can be inconsistent.
- "PIT Expo", "3rd Year PIT Expo", and renamed events can be treated differently.
- Repository upload queues may omit or include the wrong PIT event.

Good fix direction:

- Add an explicit `year_level` or cohort scope field to `PitEventGradingConfig` in the future.
- Keep event names as labels, not identity.

## Redundant Or Legacy-Looking Pieces

| Code/data | Status | Recommendation |
| --- | --- | --- |
| `StudentTeam.ready_for_stage` | Compatibility mirror | Do not treat as Capstone source of truth. Prefer `TeamStageProgress`. Keep until all UI/report consumers are migrated. |
| `StudentTeam.current_defense_stage` | Compatibility/display mirror | Same as above. Useful for dashboard display, not authoritative stage progression. |
| `DefenseSchedule.stage_label` | Snapshot label | Keep for display/report history. Do not use as identity when `defense_stage` or `pit_event_config` exists. |
| `TeamGrade.stage_label` | Snapshot label | Same. It is useful for reports but dangerous as the only selector for event/stage identity. |
| `DefenseSchedulerScreen._teamsForScope()` | Frontend duplicate of backend filtering | Keep only as presentation helper. Backend must remain source of truth. |
| `DefenseSchedulerScreen._scope` defaulting to `capstone` | Risky local default | Replace with backend-provided scheduler mode. |
| `completed_pit_events(year_level)` event-name filtering | Fragile workaround | Replace eventually with explicit event/cohort/year identity. |
| Multiple active-semester helpers | Mild duplication | Acceptable for now, but scheduler should reuse the same term-mode payload semantics as teams. |

## Recommended Fix Shape

Do not change PIT into Capstone. Do not change Capstone into PIT. Fix the mode handoff.

Recommended backend payload addition in scheduler options:

```json
{
  "scheduler_mode": "pit",
  "pit_operating_mode": "audit",
  "operating_message": "Capstone intake term - PIT scheduling is historical only for this year.",
  "can_schedule_pit": false,
  "can_schedule_capstone": false
}
```

For a PIT Lead-only user:

- `scheduler_mode` should be `pit`.
- If `pit_lead_operating_mode()` returns `audit`, PIT create/generate/confirm controls should be disabled or hidden behind a clear closed-state message.
- Capstone stage fields should not render.

For an admin:

- `scheduler_mode` may default to `capstone`.
- Admin may still be allowed to manually select PIT/Capstone if the existing flow requires that.

For a dual-role faculty member:

- The backend should explicitly describe allowed scheduler scopes.
- The frontend should not infer allowed scheduler scope from one boolean snapshot.

## What Not To Change

- Do not make PIT depend on `DefenseStage`.
- Do not use Capstone stage selection for PIT events.
- Do not let active Capstone term alone decide PIT Lead UI track.
- Do not remove `stage_label`, `ready_for_stage`, or `current_defense_stage` until every dashboard/report/export consumer is migrated.
- Do not rely on frontend filtering as permission enforcement.

## Practical Next Step

The safest next code change is narrow:

1. Extend `schedule_options_payload(user)` to include scheduler mode and PIT operating metadata.
2. Initialize `DefenseSchedulerScreen._scope` from that payload instead of defaulting to `capstone`.
3. When a PIT Lead is in audit mode, render the PIT scheduler as event-based but closed/read-only.
4. Keep the backend PIT lead year and event-context guards in place.

That preserves the existing flow while removing the misleading Capstone interface for PIT Lead users during Capstone intake terms.
