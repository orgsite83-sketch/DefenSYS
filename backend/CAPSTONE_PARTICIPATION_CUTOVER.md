# Capstone participation and term migration cutover

Date: 2026-10-29 (Asia/Manila).

This is the implementation and removal inventory for the agreed
`directives/capstone_participation_and_term_migration_final_plan.md`.
The repository ignores `directives/` and `docs/`; this tracked record preserves the deployed
rules and the evidence for retiring the former recovery policy.

## Live rules

- Academic-period activation exclusively moves academically eligible normal
  Capstone 1 teams into the consecutive Capstone 2 term. Missing destination
  enrollment does not prevent that movement. Conflicting enrollment remains a
  review issue. Student rollover enrolls students and reconciles the section of
  an already migrated team after all member enrollments agree; it does not move
  teams, reopen failed work, or allocate participation numbers.
- PIT teams and section rosters stay in their original semester. Activation never
  moves or copies them; each new semester needs fresh PIT roster formation/import.
  Unfinished PIT grading remains an outgoing-semester closure safeguard. Enabled
  Capstone evaluation switches do not require manual closure: inactive-term
  availability guards close submissions when the canonical switch commits.
  Preserve saved grading settings and incomplete requirements; only actual
  unfinished academic work blocks the switch.
- `student_teams/participation.py` owns student intake identity, eligibility,
  confirmation, placement history, number previews, and returning-student rules.
  Database constraints and period/student locks protect confirmation and retries.
- A participation number belongs to a student and a specific regular Capstone 1
  intake. Roster confirmation allocates it. Account import, enrollment, drafts,
  previews, same-intake placement changes, and normal Capstone 2 continuation
  do not allocate another number. Mixed rosters can contain first and returning
  students, including students with different official third/fourth-year enrollment.
- Finalized Failed work stays closed. Returning students enter a later regular
  Capstone 1 intake through roster confirmation. Direct Capstone 2 entry and
  same-intake failure bypasses are rejected. Ordinary re-defense before final
  failure remains supported, with hearing history distinct from participation.
- Dynamic requirement IDs, order, source assessments, deliverables, and captured
  term requirements determine clearance. Source prerequisites through the last
  evidenced/endorsed stage must be cleared. Calendar overrides preserve unresolved
  work; they never manufacture a result or restart permission.
- Student Teams retains Active and History. Members show their own participation
  number. Admins open student history for information and use the existing Import
  Teams flow to place returning/irregular students into a later Capstone 1 intake.
  There is no Copy members / Reuse roster action, dialog, or endpoint. Import
  previews allocate nothing; a successful import creates the separate team/context
  and each student's appropriate participation. Old evidence stays with its original
  team. All Capstone import commits are atomic.
- Existing shadcn components and DefenSYS tokens style the focused UI changes.
  Semester switching now has Review teams and Confirm, with green readiness,
  explicit failed/history/review statuses, expected switch effects in the neutral
  summary, and a separate attention section for unfinished PIT/Capstone work.

## Removal inventory

| Former symbol, control, or path | Former callers | Final treatment |
| --- | --- | --- |
| `authorize_retake`, `authorize_new_concept`, `keep_blocked` | Grade Center controls and `grades/defense_workflow.py` | Controls, forms, handler branches, and authorization writes removed. Direct requests fail. Remaining workflow actions are revision clearance, compliance review, and legitimate re-defense verification. |
| Replacement `project_title` workflow input/audit field | Grade workflow POST and action function | Removed from the function contract and audit writer. Unsupported workflow fields are rejected. |
| `recovery_for`, `replacement_for`, `_consume_recovery_authorization` | Grading, readiness, concept/deliverable permission checks | Removed; no stored grant can make a closed participation editable, ready, or schedulable. |
| `TeamRecoveryAuthorization` live model | Lifecycle, grading, fixtures | Replaced by `HistoricalCapstoneRecovery`; the original table and original migration graph remain. Runtime save/delete are forbidden. Its old field names represent audit evidence only. |
| `CapstoneJourney` allowance policy | Lifecycle, rollover, audit/demo tools | Replaced by `HistoricalCapstoneJourney`. Original cohort evidence is retained for mapping/history; extension deadlines and allowances confer no permission. |
| `EXTENSION_POLICY`, `extension_eligibility`, `authorize_recovery`, `carry_recovery_authority`, `cohort_context`, `ensure_journey`, recovery decisions | `capstone_lifecycle.py` and period activation | Removed. Shared participation rules and canonical activation replace them. |
| `continue_enrolled_normal_team`, `advance_capstone_teams`, `sync_capstone_flags_after_rollover` | Enrollment rollover/import paths | Removed. Activation owns movement; enrollment reconciliation cannot revive or move an excluded team. |
| `returning-teams`, late returning review, Returning wizard step | Academic Periods URL/view, provider, overview/detail dialogs | Route/view/modes removed. Former route returns 404. No project-choice or extension decision is collected during switching. |
| Activation `decisions`, returning-mode parameters | Activation/create-and-activate serializers, provider, dialogs | Removed. Strict activation input rejects obsolete fields. The status endpoint still routes activation aliases through the canonical review. |
| `PHASE_EXTENDED`, `STATUS_DELAYED`, active Extended controls | Team choices, filters, badges, scheduler hints | Removed from active choices and UI. Historical persisted contexts are preserved and mapped to review instead of being silently restarted. |
| Project-version/hearing-number editability shortcuts | Grade/deliverable services | Removed as permission overrides. A version or hearing number cannot reopen a finalized failure. |
| Separate Capstone roster copier | History/team controls, copy API, helper functions, team-copy link | Removed following the final user clarification. Import Teams handles the new intake; the former copy route returns 404. Migration 0022 removes its unused team-link field. |
| Lifetime prior-team rejection | Roster/import eligibility and student options | Replaced by current-placement conflicts and student/intake history, allowing valid returning students without mutating the old team. |

Remaining matches are deliberately limited to:

1. Historical migrations, read-only archive models, their mapping/audit safeguards,
   and negative tests that prove retired requests fail.
2. `project_choice` in the PIT current-roster workspace and its faculty screen.
   This is the independent PIT decision to carry/change an event project; it is
   unrelated to failed Capstone recovery and is preserved.
3. `validate_decisions` in concept/shared-system panel decisions, legitimate
   concept correction/re-defense, file replacement, grade correction,
   report hearing numbers, and `GradeAttemptHistory`. These preserve hearing/file
   evidence within their existing authority; they do not allocate student intakes.
4. Demo rebasing rejects Extended/replacement evidence requiring historical
   reconciliation. It cannot create an old allowance or authorization.

No compatibility authorizer, hidden old-flow feature flag, or enrollment-driven
team-migration writer remains.

## Existing-data mapping

Migrations `student_teams.0019`–`0022` were applied to the local database after a
read-only audit. They preserve old tables and evidence, add the participation
ledger/placement constraints, and remove active extension choices.

The before/after audit preserved these counts:

| Evidence | Before | After |
| --- | ---: | ---: |
| Teams | 56 | 56 |
| Memberships | 223 | 223 |
| Team grades | 64 | 64 |
| Hearing history rows | 0 | 0 |
| Deliverable submissions | 304 | 304 |
| Deliverable files | 369 | 369 |
| Concept rounds | 16 | 16 |
| Recorded team terms | 16 | 16 |
| Historical recovery grants | 0 | 0 |
| Historical cohort records | 16 | 16 |

The mapping created 63 evidenced student participation records and 63 placements
across 16 Capstone teams. There were zero intake-provenance review exceptions in
this local dataset. This is not a claim that all teams have cleared their academic
requirements. No semester was activated and no student enrollment, credential,
grade, file, or project outcome was changed to exercise the flow.

Unknown intakes receive no invented participation number. Persisted Extended,
replacement, overlapping, or consumed-recovery contexts require review rather
than renewed authority. A consumed historical grant is evidence for review only;
an unused grant cannot create another participation.

## Verification

- The full migration graph replayed on the separate
  `test_defensys_capstone_replay` database; all six mapping tests passed.
- All 28 focused Flutter tests passed, covering semester review/confirmation,
  per-student history, absence of copy controls, removal of recovery
  controls, existing period entry points, and narrow/light/dark rendering.
- Dart analysis of the changed lifecycle widgets, screens, provider, and tests
  passed without issues. Captured 320/390/1100/1200-pixel screens were visually
  reviewed using the existing DefenSYS theme.
- The consolidated Django regression passed 566 tests before the final removal
  of the separate copy path. The final import-only follow-up passed all 71 backend
  tests. All six mapping tests also pass with the 0022 cleanup applied. The full debug
  JavaScript web build passed; its Wasm compatibility probe reports existing
  dependency notices. Django checks and migration consistency checks are clean.

Useful read-only commands from `backend/`:

```powershell
.\venv\Scripts\python.exe manage.py audit_capstone_lifecycle --pre-cutover
.\venv\Scripts\python.exe manage.py audit_capstone_lifecycle
.\venv\Scripts\python.exe manage.py makemigrations --check --dry-run --noinput
.\venv\Scripts\python.exe manage.py migrate --check
```

Test writes use Django's isolated test databases. Temporary logs, test settings,
and rendered previews remain regenerable under `.tmp/`.

## Enrollment guard follow-up, 2026-10-29

Explicit roster creation, member updates, imports, and formation now share
`student_teams/roster_enrollment.py`. Each member must have enrollment in the
actual destination semester and academic year. A past record alone cannot
authorize current placement. Preview/validation reports all missing students by
name and student ID, names the required semester, and explains the enrollment
action. The client retains all errors and import row/team context.

Confirmation locks/rechecks enrollment before roster changes, including when a
record disappears after preview. Rejection preserves old records and creates no
membership, placement, or new participation number. Existing role, section,
year-level, and intake checks still apply. Canonical semester activation remains
separate: eligible existing teams migrate before enrollment rollover without
this explicit roster guard. No copy/reuse action or recovery authorization was
reintroduced.

Final verification passed 131 focused Django tests and 14 Flutter provider/detail
tests. Coverage includes past-semester/academic-year rejection, named multi-member
errors, legacy/manual and prepared imports, save-time revalidation, per-student
count integrity, normal migration before enrollment, and rollover regressions.
Dart analysis, Django system checks, migration consistency, and whitespace checks
passed. This follow-up needs no schema migration and makes no development data
or credential changes.

## PIT semester isolation clarification, 2026-10-29

Migration already selects only Capstone teams. The confirmation now distinguishes
Capstone continuation from the outgoing PIT roster notice: PIT teams stay in the
old semester and the administrator creates new PIT rosters next semester. The
combined outgoing-team row is removed. API impact counts distinguish PIT and
Capstone, and PIT-only terms no longer trigger Capstone evaluation-switch checks.
PIT grading/completion checks remain, including preserved unresolved state after
a calendar override.

All 109 focused backend tests passed across academic periods, participation, and
enrollment rollover. Added cases cover all three PIT year levels and section
rosters, mixed Capstone/PIT terms, both regular switch directions, and forced
switching with open PIT grading. All nine semester-dialog tests passed, including
narrow/light/dark rendering; Dart analysis is clean. The updated confirmation
capture was visually reviewed. No schema or development-data change is needed.

## Detailed confirmation and submission availability, 2026-10-29

The preview separates expected `effects` from actionable `issues`. Semester
activation shows a detailed shadcn summary with term identities, Capstone
movement/history, PIT isolation, submission access, and enrollment. Only actual
unfinished work appears in the amber attention container with review actions
and the existing override/reason controls. Confirm is visually and functionally
disabled while those blockers apply; PIT information has no review action.

Enabled Capstone peer/adviser settings are no longer activation blockers.
Existing inactive-term submission guards close outgoing access automatically.
Activation preserves saved source/target settings and all grade requirements,
scores, and unresolved states. It does not waive missing assessments or publish
grades. Forms refresh only after transaction commit; duplicate requests and
failed transactions do not send a spurious refresh. The old boolean-window
blocker helper is removed. PIT workflow/completion safeguards remain.

All 157 focused backend tests passed across periods, participation, rollover,
grading availability, PIT peer access, weighted scoring, and realtime behavior.
All nine final semester widget tests passed, including action/summary separation,
disabled confirmation, override reasons, and responsive light/dark rendering.
Dart analysis and whitespace checks passed. Desktop and narrow-screen captures
were visually reviewed. No schema or development-data changes were needed.

## Semester-direction cards, 2026-10-29

The approved confirmation now uses separate Outgoing semester and Next active
semester shadcn cards. Source PIT counts and Capstone history stay on the left;
eligible Capstone continuation appears on the right with green emphasis. Each
card identifies its academic term. Fresh Capstone 1 intake and fresh PIT rosters
have explicit destination wording. Cards stack with a downward arrow on narrow
screens. The attention container and confirmation/override guards are retained.

All ten final semester widget tests and Dart analysis passed. Captures at desktop
and narrow widths in light/dark themes, plus a fresh Capstone 1 intake, were
visually reviewed. Source/destination count placement, history preservation in
the summary, and blocked confirmation are covered. This follow-up changes only
frontend presentation; the previous backend rules and verification remain valid.
