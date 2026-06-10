# Dangerous Logic Audit — System-Wide Silent Data Loss & Failure Risks

> **Date**: 2026-06-09
> **Scope**: Full backend audit across all modules
> **Purpose**: Identify patterns where the system silently strips, overwrites, or discards data instead of warning/blocking — like the PIT adviser stripping bug — plus any logic that risks cascading data loss or system-level failure.

---

## 🔴 CRITICAL — Silent Data Loss or Corruption

### 1. PIT Bulk Import Silently Strips Adviser (KNOWN)

**File**: [bulk_import.py L157-161](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py#L157-L161)

```python
if pit_row:
    data = dict(data)
    data['adviser_id'] = ''
    adviser, adviser_status, adviser_name = None, ADVISER_STATUS_NONE, ''
```

**What happens**: When a CSV row is identified as PIT, the `adviser_id` field is silently blanked. The row still reports `ready = True` with no issues. The user's CSV had an adviser column but the system threw it away without any warning.

**Why it's dangerous**: The user sees "Ready" in the preview and imports. The adviser data is silently lost. No error, no warning, no audit trail. The user has no idea their CSV data was discarded.

**Fix needed**: Return a warning like `"Adviser column ignored for PIT teams"` in the `issues` list instead of silently stripping.

---

### 2. `_sync_members` Cascade-Deletes Other Teams' Memberships

**File**: [serializers.py L416-434](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/serializers.py#L416-L434)

```python
def _sync_members(self, team, member_ids, leader_id):
    # Remove old memberships for this team
    team.memberships.all().delete()

    # Remove students from any other teams they might be in
    TeamMembership.objects.filter(student_id__in=member_ids).exclude(team=team).delete()

    # Create new memberships
    ...
```

**What happens**: When saving a team (create or update), this method **first deletes all existing memberships** for the team, **then** silently removes those students from **any other team they belong to** across the entire system. No warning, no audit trail, no notification to the other team's adviser.

**Why it's dangerous**:
- The `validate()` method already checks for duplicate memberships and raises an error (L233-L251). So the cascade delete at L422 is a **redundant safety net** that should never fire — but if it does, it does so **silently**.
- If two requests race (e.g., two admins editing teams concurrently), students could be silently removed from Team A when Team B is saved.
- The `User.objects.filter(pk__in=member_ids).update(team_id=str(team.id))` at L437 updates the user's `team_id` but does **not** clear the `team_id` of students removed from other teams — leaving stale `team_id` values.
- No `log_high_impact_action` call for the silent removal from other teams.

**Fix needed**: Either remove the cascade delete at L422 entirely (relying on the validation at L233-L251 to prevent duplicates), or add an audit log + warning when it fires.

---

### 3. Grade `recalculate()` Silently Unlocks Published Grades

**File**: [grades/models.py L145-167](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/models.py#L145-L167)

```python
def recalculate(self, keep_published=False):
    if self.is_complete:
        ...
        if self.status not in self.LOCKED_STATUSES:
            self.status = self.STATUS_PENDING
        return

    self.final_grade = None
    if self.status in self.LOCKED_STATUSES:
        self.status = self.STATUS_PENDING  # ← Published grade reverts to Pending
```

**What happens**: If a published grade becomes "incomplete" (e.g., a rubric is deleted, a peer evaluation is removed, or an adviser score is nulled), `recalculate()` silently reverts the status from `STATUS_PUBLISHED` back to `STATUS_PENDING` and clears `final_grade`. This is called on **every `save()`** via L188.

**Why it's dangerous**:
- A published grade is supposed to be immutable — it's been officially approved, the team status was set to PASSED/FAILED, and it's in the audit log.
- If any upstream data changes (rubric deleted, score nulled by a DB fix, peer eval cleaned up), the published grade silently unpublishes. No notification, no audit trail for the revert.
- The `keep_published` parameter is never used — it's declared but the method ignores it.
- This can cascade: `mark_stage_result` already set the team to APPROVED, but now the grade is back to PENDING. The team status and grade status are now **out of sync**.

**Fix needed**: Published grades should refuse to recalculate into an incomplete state. Add an explicit guard that raises an error or logs a high-impact action instead of silently reverting.

---

### 4. `_merge_stale_grade` Silently Moves Score Data Between Grade Records

**File**: [grades/services.py L551-566](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L551-L566)

```python
def _merge_stale_grade(stale, canonical):
    score_fields = ('panel_score', 'adviser_score', 'peer_score')
    for field in score_fields:
        if getattr(stale, field) is not None and getattr(canonical, field) is None:
            setattr(canonical, field, getattr(stale, field))

    if stale.status in TeamGrade.LOCKED_STATUSES and canonical.status not in TeamGrade.LOCKED_STATUSES:
        canonical.status = stale.status
        canonical.published_by = stale.published_by
        canonical.published_at = stale.published_at

    stale.breakdowns.update(team_grade=canonical)
    stale.peer_member_grades.update(team_grade=canonical)
    stale.peer_evaluation_submissions.update(team_grade=canonical)
    stale.delete()
    canonical.save()
```

**What happens**: When the system detects "stale" placeholder grades, it silently merges their scores, breakdowns, peer evaluations, and published status into the "canonical" grade, then deletes the stale record. This happens automatically during `repair_placeholders`.

**Why it's dangerous**:
- Scores from a stale context (e.g., an old defense stage) are silently migrated to a new context. The scores may no longer be valid for the new rubric/stage.
- If the stale grade was `PUBLISHED` and canonical is `PENDING`, the canonical grade inherits the published status — effectively auto-publishing the new grade without explicit approval.
- The merge happens with no audit trail. A grade that was published by one user for one defense stage could silently appear published under a different stage.
- `stale.breakdowns.update(team_grade=canonical)` bulk-updates FK references — if the canonical grade already has breakdowns for the same criteria, you now have **duplicate** breakdown rows.

**Fix needed**: Add `log_high_impact_action` for every merge. Block merging published grades into non-published ones without explicit admin confirmation.

---

### 5. Team Delete with Grades/Schedules Returns Warning But Has No Confirmation

**File**: [student_teams/views.py L316-360](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/views.py#L316-L360)

```python
def delete(self, request, team_id):
    ...
    has_schedules = DefenseSchedule.objects.filter(team=team).exists()
    has_grades = TeamGrade.objects.filter(team=team).exists()
    if has_schedules or has_grades:
        return Response(
            {'warning': '...'},
            status=status.HTTP_409_CONFLICT,
        )
    ...
    team.delete()
```

**What happens**: If a team has schedules or grades, the endpoint returns a 409 warning. But the frontend can simply ignore this and call DELETE again, or there's no server-side "confirmed" flag. The actual delete at L348 has `on_delete=CASCADE` for:
- `TeamMembership` (CASCADE) — all memberships destroyed
- `TeamStageProgress` (CASCADE) — all progress records destroyed
- `TeamGrade` (CASCADE) — **all grades, breakdowns, panelist scores, peer evaluations destroyed**
- `DeliverableSubmission` (CASCADE) — all deliverables destroyed
- `DefenseSchedule` — (team FK is PROTECT, so this would actually block)

**Why it's dangerous**: The warning response at L326-337 is a **suggestion**, not a gate. If the team somehow has grades but no schedules (or vice versa), or if the frontend is buggy and calls delete twice, all grade data is **permanently and irrecoverably destroyed**. The model uses `CASCADE` not `PROTECT` for grades.

**Fix needed**: Require a `?confirm=true` query parameter or a request body flag to proceed with deletion when data exists. The `TeamGrade` FK should arguably be `PROTECT` not `CASCADE`.

---

### 6. Bulk User Import Creates Users Before Validation Completes

**File**: [user_management/views.py L462-482](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py#L462-L482)

```python
user = User.objects.create_user(
    username=username,
    password=username,
    ...
)
created.append(user)
year_level = (data.get('year_level') or context_year_level or '').strip()
if self.force_pit_lead_context:
    row_year = (data.get('year_level') or '').strip()
    if row_year and row_year != context_year_level:
        errors.append(...)
        user.delete()          # ← User was already created, now deleted
        created.pop()
        continue
```

**What happens**: The user is **created in the database first** (L462-470), then additional validation runs (L472-482). If the validation fails, the user is deleted. But:
- The `create_user` at L462 commits to the database immediately (no `transaction.atomic`)
- If the server crashes between L462 and L480, you have an orphaned user with `password = username`
- The `user.delete()` at L480 runs outside a transaction — if it fails, the user persists with no academic record
- Django signals fired by `create_user` (e.g., post_save) cannot be undone by `user.delete()`

**Why it's dangerous**: The entire `post()` method for `BulkImportUsersMixin` runs **without** `@transaction.atomic`. Each row creates a user independently. If the process crashes at row 50 of 100, you have 50 users created but no way to know which 50 (the response was never sent). The skipped/error lists are only in the response payload, not persisted.

**Fix needed**: Wrap the entire import loop in `@transaction.atomic`, or at minimum wrap each row's create + validate in its own atomic block.

---

## 🟡 HIGH RISK — Data Integrity Issues

### 7. `SchoolYear.delete()` Cascades to All Semesters, Teams, and Grades

**File**: [academic_period_management/models.py L42](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/academic_period_management/models.py#L42)

```python
school_year = models.ForeignKey(SchoolYear, related_name='semesters', on_delete=models.CASCADE)
```

**What happens**: Deleting a `SchoolYear` cascades to all its `Semester` records. Each `Semester` then has `PROTECT` on teams and grades — so this will actually fail with a `ProtectedError`. However, the admin Django panel (if exposed) or a shell script could delete a school year and cascade-destroy everything.

**Risk**: Low in production (PROTECT on downstream FKs blocks it), but dangerous if anyone uses the Django admin or shell to clean up old school years. There's no soft-delete mechanism.

---

### 8. Defense Schedule Cancellation Doesn't Clean Up Grade Records

**File**: [defense/scheduler/serializers.py L737-741](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/serializers.py#L737-L741)

```python
def save(self):
    schedule = self.context['schedule']
    schedule.status = self.validated_data['status']
    schedule.save()
    return schedule
```

**What happens**: When a schedule status changes to `cancelled`, the associated `TeamGrade` record (created by `_sync_grade_row`) is **not** cleaned up. The grade record persists with `schedule_id` pointing to a cancelled schedule, and it still counts in grade center views.

**Risk**: Orphaned grade records with stale data. If the team is later rescheduled, the system may create a second grade record (due to the stale one), leading to duplicate grades that need manual merge. The `_cleanup_stale_grades_for_schedule` only runs during create, not on cancellation.

---

### 9. `CompileWeeklyReportsView` Bypasses Permission Scoping

**File**: [repository/deliverables/views.py L149-233](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/deliverables/views.py#L149-L233)

```python
class CompileWeeklyReportsView(APIView):
    permission_classes = [CanManageDeliverables]

    def post(self, request):
        ...
        team = StudentTeam.objects.get(id=team_id)  # ← No scope check!
```

**What happens**: The view uses `StudentTeam.objects.get(id=team_id)` directly instead of `get_allowed_team(request, team_id)`. Any authenticated user with `CanManageDeliverables` permission (which includes **all students**) can compile weekly reports for **any** team, not just their own.

**Risk**: Any student can access any team's weekly progress reports by passing an arbitrary `team_id`. This is a data leakage vulnerability.

**Fix needed**: Replace `StudentTeam.objects.get(id=team_id)` with `get_allowed_team(request, team_id)`.

---

### 10. `keep_published` Parameter in `recalculate()` Is Dead Code

**File**: [grades/models.py L145](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/models.py#L145)

```python
def recalculate(self, keep_published=False):
    # keep_published is NEVER checked in the method body
```

**What happens**: The `keep_published` parameter exists but is never used in the method logic. The `save()` method at L188 calls `self.recalculate(keep_published=True)`, suggesting the intent was to preserve published status during saves — but the parameter is ignored.

**Risk**: This is a bug in the implementation. The intent was clearly to prevent published grades from being reverted during normal saves, but the guard was never implemented. This directly enables issue #3 above.

---

### 11. Legacy APK Fallback Silently Reorders Criteria Scores

**File**: [grades/services.py L306-312](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L306-L312)

```python
# Legacy APK fallback for old versions that send null IDs
if missing_id_items:
    if not payload_by_id and len(missing_id_items) == len(criteria):
        for criterion, item in zip(criteria, missing_id_items):
            payload_by_id[criterion.id] = item
        missing_id_items = []
```

**What happens**: If an old mobile APK sends criteria scores without `criterion_id` fields, and the count exactly matches the rubric, the system assumes they're in the same order and maps them positionally.

**Risk**: If the rubric criteria order was changed after the APK was built, scores get assigned to the **wrong criteria**. Score for "Technical" goes to "Presentation" and vice versa. No warning — grades are silently misattributed. This is especially dangerous because rubric criteria can be reordered by admins at any time.

---

### 12. Semester Transition `force=True` Bypasses All Safety Checks

**File**: [academic_period_management/services.py L48-63](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/academic_period_management/services.py#L48-L63)

```python
def switch_active_semester(target_semester, user, force=False, reason=''):
    ...
    if preview['blocking_reasons']:
        if not force:
            raise ValidationError(...)
        if not reason:
            raise ValidationError(...)
    # If force=True and reason provided, ALL blocking checks are bypassed
```

**What happens**: With `force=True` and any reason string, the semester switch proceeds regardless of: open scheduled defenses, pending grades, open peer grading windows, incomplete official workflows, open archive queues. The impact snapshot is saved but no data is migrated or cleaned up.

**Risk**: After a forced switch, all scheduled defenses are now historical. Pending grades cannot be completed because the semester is no longer active. Peer grading windows become inaccessible. Teams appear in "history" view. Faculty/students lose access to active workflows. Data is not lost but becomes **functionally orphaned**.

**Mitigation already exists**: Requires a `reason` and logs via `log_high_impact_action`. But the actual data is not cleaned up or migrated.

---

## 🟢 NOTEWORTHY — Minor Risks

### 13. `resolve_adviser_by_name()` Full-Table Scan

**File**: [bulk_import.py L82-86](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py#L82-L86)

```python
faculty_matches = [
    user
    for user in User.objects.filter(role__in=['faculty', 'admin'])
    if normalize_name(display_name(user)) == normalized
]
```

**What happens**: For every CSV row, this loads **all** faculty/admin users into memory and iterates them for a case-insensitive name match. With 100 CSV rows and 200 faculty, that's 20,000 Python-side comparisons.

**Risk**: Performance degradation at scale. Not a data loss risk, but could cause timeouts during large bulk imports.

---

### 14. `User.objects.filter(pk__in=member_ids).update(team_id=str(team.id))` Denormalization Drift

**File**: [serializers.py L437](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/serializers.py#L437)

```python
User.objects.filter(pk__in=member_ids).update(team_id=str(team.id))
```

**What happens**: The user model has a denormalized `team_id` field that's updated when memberships change. But when a team is deleted, the cleanup at L359 only clears `team_id` for students of the **deleted** team. If a student was silently removed from another team by the cascade at L422, their `team_id` still points to the old team — it's never cleared.

**Risk**: `User.team_id` becomes stale. Any feature that reads `user.team_id` directly (instead of querying `TeamMembership`) will return incorrect data.

---

## Summary Table

| # | Issue | Severity | Module | Data at Risk |
|---|-------|----------|--------|-------------|
| 1 | PIT adviser silently stripped | 🔴 | student_teams | Adviser assignments |
| 2 | `_sync_members` cascade delete | 🔴 | student_teams | Team memberships across teams |
| 3 | Published grades silently unlock | 🔴 | grading | Final grades, team pass/fail status |
| 4 | Stale grade merge without audit | 🔴 | grading | Grade scores, breakdowns, published status |
| 5 | Team delete cascade without confirm gate | 🔴 | student_teams | All grades, evaluations, deliverables |
| 6 | User import without transaction | 🔴 | user_management | Orphaned users, partial imports |
| 7 | SchoolYear cascade to semesters | 🟡 | academic_period | All downstream data (blocked by PROTECT) |
| 8 | Schedule cancel orphans grades | 🟡 | defense | Orphaned grade records |
| 9 | Weekly reports bypass scope | 🟡 | repository | Cross-team data leakage |
| 10 | `keep_published` dead code | 🟡 | grading | Published grade stability |
| 11 | Legacy APK criteria reorder | 🟡 | grading | Criteria score misattribution |
| 12 | Forced semester switch | 🟡 | academic_period | Orphaned workflows |
| 13 | Full-table scan adviser resolve | 🟢 | student_teams | Performance only |
| 14 | `team_id` denormalization drift | 🟢 | student_teams | Stale user.team_id |

---

## Recommended Fix Priority

1. **🔴 Immediate**: Add warning for PIT adviser stripping (#1)
2. **🔴 Immediate**: Remove or audit-log the cascade delete in `_sync_members` (#2)
3. **🔴 Immediate**: Guard published grades from silent unpublish (#3, #10)
4. **🔴 Immediate**: Add audit logging to `_merge_stale_grade` (#4)
5. **🔴 Immediate**: Add server-side confirmation gate for team delete with data (#5)
6. **🔴 Immediate**: Wrap bulk user import in `@transaction.atomic` (#6)
7. **🟡 Next sprint**: Fix `CompileWeeklyReportsView` scope bypass (#9)
8. **🟡 Next sprint**: Clean up grade records on schedule cancellation (#8)
9. **🟡 Next sprint**: Deprecate legacy APK criterion fallback (#11)
10. **🟡 Backlog**: Add soft-delete for school years (#7)
11. **🟡 Backlog**: Add data migration step to semester transition (#12)

---

## Files Referenced

| File | Path |
|------|------|
| bulk_import.py | [student_teams/bulk_import.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py) |
| serializers.py | [student_teams/serializers.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/serializers.py) |
| views.py | [student_teams/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/views.py) |
| models.py (grades) | [grading/grades/models.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/models.py) |
| services.py (grades) | [grading/grades/services.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py) |
| views.py (users) | [user_management/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py) |
| models.py (academic) | [academic_period_management/models.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/academic_period_management/models.py) |
| services.py (academic) | [academic_period_management/services.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/academic_period_management/services.py) |
| serializers.py (scheduler) | [defense/scheduler/serializers.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/serializers.py) |
| views.py (deliverables) | [repository/deliverables/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/deliverables/views.py) |
