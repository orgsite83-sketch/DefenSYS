# Dangerous Runtime Fallback Audit

Date: 2026-06-06

## Scope

Scanned runtime code under `backend/modules` and `frontend/lib` for hardcoded values that can override, hide, or misrepresent admin-configured data. Excluded tests, migrations, static/media files, and explicit seed commands unless the same value is used at runtime.

This audit focuses on fallbacks like the old deliverables `Concept Proposal` issue: values that look harmless but can silently replace the real source of truth.

## Summary

The highest-risk findings were the runtime fallbacks that invented `Concept Proposal` when a Capstone team had no recorded stage. Those have been fixed because Defense Stages is admin-managed now; any UI/API that recreates old stage names can confuse scheduling, deliverables, and readiness decisions.

There are also lower-risk defaults around grade placeholders, route parameters, and analytics labels. Some are intentional, but they should be treated carefully because they can hide missing configuration.

## High Priority

### 1. Dashboard Capstone current stage falls back to `Concept Proposal`

Status: Fixed on 2026-06-06. Dashboard team payloads now return `None` when no real Capstone stage is recorded.

File: `backend/modules/dashboards/views.py:142`

Current behavior:

```python
'currentStage': team.current_defense_stage or team.ready_for_stage or ('Concept Proposal' if team.is_capstone else None)
```

Fixed behavior:

```python
'currentStage': team.current_defense_stage or team.ready_for_stage or None
```

Why it is dangerous:

- It shows a stage even when the team has no real `current_defense_stage` or `ready_for_stage`.
- It can contradict the admin-created Defense Stages. If the admin renamed or misspelled the stage, the dashboard still says `Concept Proposal`.
- It makes missing stage data look valid, so admins/advisers may think a team is already tied to a stage when it is not.

Recommended fix:

- Do not invent a stage label.
- Return `None`, `''`, or a display-only label like `Not assigned`.
- If a default stage is truly needed, derive it from the first active `DefenseStage`, but mark it as inferred so it is not confused with real team progress.

### 2. Student team defense context falls back to `Concept Proposal`

Status: Fixed on 2026-06-06. Team defense context now returns `None` when no real Capstone stage is recorded.

File: `backend/modules/student_teams/serializers.py:152`

Current behavior:

```python
'current_stage': obj.current_defense_stage or obj.ready_for_stage or 'Concept Proposal'
```

Fixed behavior:

```python
'current_stage': obj.current_defense_stage or obj.ready_for_stage or None
```

Why it is dangerous:

- This payload feeds team-management UI context.
- It can show a Capstone team as belonging to `Concept Proposal` even if the admin configured only another active stage.
- It can affect human decisions around roster readiness and scheduling because the UI looks confidently populated.

Recommended fix:

- Same as the dashboard: return no stage unless the team actually has one.
- Prefer a `defense_stage_id`/progress-based source instead of raw label fallback.

## Medium Priority

### 3. Manual Defense Scheduler room defaults to `Room 301`

Status: Fixed on 2026-06-06. Manual room starts empty, stays required, and import default room is explicit instead of prefilled.

File: `frontend/lib/screens/web/admin/defense_scheduler_screen.dart:29`

Current behavior:

```dart
final _roomController = TextEditingController(text: 'Room 301');
```

Fixed behavior:

```dart
final _roomController = TextEditingController();
```

Why it matters:

- This can create official schedules in `Room 301` even when the admin did not explicitly choose that room.
- It is especially risky now that schedule import may carry room/date/time data from the admin template. A fallback room can hide a parsing/import issue.

Recommended fix:

- Keep the field required, but start it empty.
- For manual scheduling, let the admin explicitly enter a room/default room.
- For imports, use the template room when present and block rows with no room unless the admin explicitly applies a default.

### 4. Grade records use `Unscheduled` as a real stored fallback

Status: Fixed on 2026-06-06. Grade Center payloads now hide stale `Unscheduled` placeholders when a real grade row exists for the same team/semester/scope; explicit sync still repairs/deletes the stale database row.

Files:

- `backend/modules/grading/grades/models.py:49`
- `backend/modules/grading/grades/services.py:514`
- `frontend/lib/screens/web/admin/grade_center_shared.dart:44`

Current behavior:

```python
stage_label = models.CharField(max_length=120, default='Unscheduled')
```

Why it matters:

- This appears intentional because Grade Center supports unscheduled Capstone teams.
- But it has already needed cleanup support: `backend/modules/grading/management/commands/dedupe_stale_team_grades.py` mentions stale `Unscheduled` rows beside real stage rows.
- If a team later gets a real defense stage, stale `Unscheduled` grade rows can duplicate or confuse grade groups.

Recommended fix:

- Keep the visible `Unscheduled` group if the workflow needs it.
- Avoid treating `Unscheduled` as a normal stage label in persisted business logic.
- Prefer `defense_stage_id = null` plus an explicit placeholder flag/status.
- Keep or strengthen dedupe tests around transition from unscheduled to scheduled.

### 5. Schedule API defaults missing scope to Capstone

Status: Fixed on 2026-06-06. Schedule write/generate/confirm payloads now require `scope`; missing scope returns validation error instead of becoming Capstone.

File: `backend/modules/defense/scheduler/serializers.py:183`

Current behavior:

```python
scope = serializers.ChoiceField(..., default=DefenseSchedule.SCOPE_CAPSTONE)
```

Fixed behavior:

```python
scope = serializers.ChoiceField(...)
```

Why it matters:

- If a client forgets `scope`, the backend assumes Capstone.
- Validation usually catches missing Capstone fields, but the API is still guessing a business context.
- With bulk imports, a missing or malformed scope should be rejected clearly rather than converted.

Recommended fix:

- Require `scope` for schedule create/update payloads.
- Let the UI choose a default visually, but send the selected value explicitly.

### 6. Rubric API defaults missing scope to Capstone

Status: Fixed on 2026-06-06. Rubric create/update payloads now require `scope`; missing scope returns validation error instead of becoming Capstone.

File: `backend/modules/grading/rubrics/serializers.py:115`

Current behavior:

```python
scope = serializers.ChoiceField(..., default=Rubric.SCOPE_CAPSTONE)
```

Fixed behavior:

```python
scope = serializers.ChoiceField(...)
```

Why it matters:

- A malformed or incomplete rubric create request can become Capstone by default.
- If a request includes a Capstone stage by accident, the record can be created in the wrong evaluation context.

Recommended fix:

- Require `scope` in API payloads.
- Keep role-based overrides where needed, but do not silently infer scope from an omitted field.

### 7. Mobile panelist UI infers missing scope from `is_capstone`

Status: Fixed on 2026-06-06. Mobile panelist assignments now treat missing/invalid scope as `unknown`, show a warning, hide schedule weights, and block grade posting instead of guessing Capstone or PIT.

File: `frontend/lib/screens/app/panelist_dashboard.dart:125`

Current behavior:

```dart
scope: (team['scope'] ?? (isCapstone ? 'capstone' : 'pit')).toString()
```

Fixed behavior:

```dart
final rawScope = team['scope']?.toString().trim() ?? '';
final scope = rawScope == 'capstone' || rawScope == 'pit'
    ? rawScope
    : 'unknown';
```

Why it matters:

- If the backend payload is missing `scope`, the UI guesses.
- That guess affects displayed grading weights, labels, and workflow assumptions.
- A PIT record with incomplete data can look like Capstone or vice versa.

Recommended fix:

- Treat missing `scope` as invalid/unknown in UI.
- Show a clear warning instead of guessing.

## Low Priority / Watchlist

### 8. Grade Center event route defaults missing scope to Capstone

Status: Fixed on 2026-06-06. Grade Center event routes now derive missing scope from the `groupKey`; if neither scope is valid or the query scope conflicts with the group key scope, the route shows an error instead of defaulting to Capstone.

File: `frontend/lib/navigation/route_pages.dart:78`

Current behavior:

```dart
final scope = params['scope'] ?? 'capstone';
```

Fixed behavior:

```dart
final routeScope = _validGradeScope(params['scope']);
final groupScope = _validGradeScope(_scopeFromGroupKey(groupKey));
final scope = routeScope ?? groupScope;
```

Why it matters:

- Deep links or malformed route pushes can open a group as Capstone when the intended scope was PIT.
- It is mostly navigation/display risk, but it can confuse grade review.

Recommended fix:

- Derive scope from the `groupKey`, or require the route param.
- If missing, show a route error instead of defaulting.

### 9. PIT schedule label falls back to generic `PIT Event`

Status: Fixed on 2026-06-06. Scheduled PIT team context now returns the actual schedule label or a blank string; it no longer invents `PIT Event` for corrupted/missing event names.

File: `backend/modules/student_teams/serializers.py:168`

Current behavior:

```python
'event_label': schedule.stage_label or 'PIT Event'
```

Fixed behavior:

```python
'event_label': (schedule.stage_label or '').strip()
```

Why it matters:

- This is display-only and lower risk.
- But if `schedule.stage_label` is blank, showing `PIT Event` hides a data bug. PIT schedules should have an event name.

Recommended fix:

- Return blank/unknown and log or surface the missing event name.

### 10. Repository Vault filter options depend on deliverables stage options

Status: Fixed on 2026-06-06. Repository Vault now reads active `DefenseStage` labels directly and merges them with existing visible vault/submission stage labels, so current admin stages and historical uploaded stages both remain filterable.

File: `backend/modules/repository/vault/services.py:165`

Current behavior:

```python
'stage_options': sorted(set(STAGE_OPTIONS + stages))
```

Fixed behavior:

```python
'stage_options': sorted(set(active_defense_stage_options() + stages))
```

Why it matters:

- After the deliverables fix, `STAGE_OPTIONS` is dynamic, so this is not currently hardcoded.
- The coupling is still fragile: Repository Vault stage filters are borrowing the deliverables service's stage option provider.

Recommended fix:

- Read active `DefenseStage` records directly in the vault module.
- Include existing submitted/vault stages separately so historical records remain filterable.

### 11. Curriculum Analytics falls back to `Django / Python`

Status: Fixed on 2026-06-06. Curriculum Analytics now returns `Unclassified` for entries with no reliable tech signal, low-confidence category mapping, or only a PIT course code; it uses a neutral color for that bucket and prevents short keywords like `ar` from matching inside unrelated words.

File: `backend/modules/curriculum_analytics/services.py:198`

Current behavior:

```python
return 'Django / Python'
```

Fixed behavior:

```python
return UNCLASSIFIED_TECH_STACK
```

Why it matters:

- This is analytics-only, not scheduling/grading state.
- It can still skew charts if unknown projects all collapse into one tech stack.

Recommended fix:

- Return `Unknown` or `Unclassified` when confidence is low.
- Keep guessed stack and confidence separate.

## Not Flagged As Dangerous

These were found but do not appear to be runtime source-of-truth problems:

- `backend/modules/repository/deliverables/deliverable_templates.py`: explicitly documented as tests/optional templates only, not runtime source of truth.
- Migrations and seed commands with `Concept Proposal`, `Project Proposal`, and `Final Defense`: bootstrap/seed data, not live fallback behavior.
- `Pending`, `Approved`, `Failed`, year levels, and semester labels: mostly enum/domain values, not hidden replacement of admin-configured stage data.
- `N/A`, `Unknown`, `Unassigned`, `No project`: display placeholders only.

## Recommended Fix Order

1. Fixed: `currentStage` in dashboard payloads.
2. Fixed: `current_stage` in student team serializer payloads.
3. Fixed: stale `Unscheduled` placeholders are hidden from Grade Center payloads when a real grade exists; explicit sync still repairs database rows.
4. Fixed: remove `Room 301` as an implicit schedule value.
5. Fixed: schedule and rubric payloads now require explicit `scope`.
6. Fixed: mobile panelist UI now treats missing assignment scope as invalid/unknown.
7. Fixed: Grade Center event routes no longer default missing scope to Capstone.
8. Fixed: PIT schedule labels are no longer invented as `PIT Event`.
9. Fixed: Repository Vault owns its stage filter options and preserves historical vault stages.
10. Fixed: Curriculum Analytics now reports `Unclassified` instead of inventing `Django / Python`.
11. Clean up lower-risk UI/navigation guesses.
