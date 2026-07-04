# Endpoint Source of Truth Audit

> **Purpose**: Identify every endpoint in the DefenSYS backend and verify that each has a single, canonical source of truth for its data. Flag any duplicated logic, divergent data paths, inconsistent fallbacks, or multiple mutation points that could cause data corruption or misalignment.

---

## Summary of Findings

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 Critical | 4 | Multiple mutation paths for the same data that can cause corruption |
| 🟠 High | 5 | Duplicated logic that can silently diverge |
| 🟡 Medium | 5 | Inconsistent patterns that increase maintenance risk |
| 🔵 Low | 3 | Style inconsistencies (not dangerous, but messy) |

**Total: 113 endpoints audited across 13 modules.**

---

## 🔴 1. Grade Score Writes from Multiple Endpoints (Panel Scores)

**Priority**: P0 — Fix Immediately

**Problem**: Panel grades for a team can be submitted through THREE different endpoints, all ultimately writing to the same `TeamGrade.panel_score` and `GradeBreakdown` rows:

| # | Endpoint | View | Module |
|---|----------|------|--------|
| 1 | `PATCH /api/grading/grades/<id>/` | `GradeCenterDetailView.patch` | [views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/views.py#L192-L219) |
| 2 | `POST /api/defense/schedules/submit-grades/` | `PanelistGradeSubmissionView.post` | [scheduler/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L533-L742) |
| 3 | `POST /api/defense/schedules/guest-submit-grades/` | `GuestPanelistGradeSubmissionView.post` | [scheduler/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L849-L1036) |

**Why it's dangerous (how the code works now)**:
- **Endpoint 1** (`GradeCenterDetailView.patch`) performs a raw `TeamGradeUpdateSerializer.save()` which writes `panel_score` directly via `setattr` — it **does NOT** call `recompute_panel_score()`. The admin can manually set `panel_score=85` while the underlying `GradeBreakdown`/`PanelistGradeSubmission` rows still reflect the real per-panelist averages.
- **Endpoints 2 & 3** both call `submit_panelist_grade()` → `recompute_panel_score()` which recalculates from breakdown/submission data.
- If an admin manually edits via Endpoint 1, then a panelist submits via Endpoint 2, the `recompute_panel_score()` will **overwrite** the admin's manual value with the computed average — silently dropping the admin's override.
- **No audit trail** distinguishes whether `panel_score` was set by manual override or by computation.
- **Data that can be corrupted**: `TeamGrade.panel_score`, `TeamGrade.final_grade`.

**Recommended Fix**:

**Step 1 — Add override flag to `TeamGrade` model** in [models.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/models.py#L95-L97):

```diff
 panel_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
+panel_score_is_override = models.BooleanField(default=False)
 adviser_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
+adviser_score_is_override = models.BooleanField(default=False)
 peer_score = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
```

**Step 2 — Set the flag in `TeamGradeUpdateSerializer.save()`** in [serializers.py:262-273](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/serializers.py#L262-L273):

```diff
 def save(self):
     grade = self.context['grade']
     for field in ['panel_score', 'adviser_score', 'peer_score']:
         if field in self.validated_data:
             setattr(grade, field, self.validated_data[field])
+            setattr(grade, f'{field.split("_score")[0]}_score_is_override', True)
     ...
```

**Step 3 — Respect override in `recompute_panel_score()`** in [services.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py):

```diff
 def recompute_panel_score(grade):
+    if grade.panel_score_is_override:
+        return  # Admin override takes precedence; skip recompute
     # ... existing computation logic ...
```

**Step 4 — Add audit log to `GradeCenterDetailView.patch`** in [views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/views.py#L192-L219):

```diff
+if any(f in serializer.validated_data for f in ['panel_score', 'adviser_score', 'peer_score']):
+    log_high_impact_action(
+        category=SystemAuditLog.CATEGORY_GRADE_CENTER,
+        action='grade.admin_score_override',
+        target=grade,
+        actor=request.user,
+        new_values={f: str(serializer.validated_data[f]) for f in ['panel_score', 'adviser_score', 'peer_score'] if f in serializer.validated_data},
+    )
```

**Migration**: Generate and run migration for the two new boolean fields.

---

## 🔴 2. Schedule Status Modified from Three Independent Paths

**Priority**: P0 — Fix Immediately

**Problem**: `DefenseSchedule.status` can be changed from three separate code paths with **different validation logic and different audit trails**:

| # | Mutation Path | Location | Audit? |
|---|--------------|----------|--------|
| 1 | `PATCH /api/defense/schedules/<id>/` | [DefenseScheduleDetailView.patch](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L311-L325) | ✅ `log_high_impact_action` |
| 2 | `PATCH /api/defense/board/<id>/` | [DefenseBoardDetailView.patch](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L134-L146) | ❌ No audit log |
| 3 | Grade publish/finalize | [GradeContextService.publish](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L1172-L1187) | ❌ No schedule audit |

**Why it's dangerous (how the code works now)**:
- Path 1 uses `DefenseSchedulePatchSerializer` which delegates transition validation to `DefenseScheduleStatusSerializer.VALID_TRANSITIONS`.
- Path 2 uses `DefenseScheduleStatusSerializer` directly — same transitions but **no audit log is written**.
- Path 3 directly sets `schedule.status = STATUS_DONE` and calls `schedule.save()` — **no transition validation at all** and no schedule-level audit.
- A user could bypass transition rules by using the grade publish path (e.g., going from `CANCELLED` → `DONE` if a grade is published on a cancelled schedule).
- Schedule status changes via the Board endpoint are completely invisible in the audit trail.

**Recommended Fix**:

**Step 1 — Create a single canonical service function** (new file or add to existing `defense/scheduler/services.py`):

```python
from authentication_access_control.models import SystemAuditLog
from .models import DefenseSchedule

VALID_TRANSITIONS = {
    DefenseSchedule.STATUS_SCHEDULED: [DefenseSchedule.STATUS_DONE, DefenseSchedule.STATUS_CANCELLED],
    DefenseSchedule.STATUS_DONE: [DefenseSchedule.STATUS_ARCHIVED],
    DefenseSchedule.STATUS_CANCELLED: [DefenseSchedule.STATUS_SCHEDULED],
    DefenseSchedule.STATUS_ARCHIVED: [],
}

def transition_schedule_status(schedule, new_status, *, actor=None, reason=''):
    """Single source of truth for schedule status transitions."""
    from authentication_access_control.services import log_high_impact_action

    old_status = schedule.status
    if new_status == old_status:
        return schedule

    allowed = VALID_TRANSITIONS.get(old_status, [])
    if new_status not in allowed:
        from rest_framework.exceptions import ValidationError
        raise ValidationError({'status': f'Cannot change status from "{old_status}" to "{new_status}".'})

    schedule.status = new_status
    schedule.save(update_fields=['status', 'updated_at'])

    log_high_impact_action(
        category=SystemAuditLog.CATEGORY_DEFENSE_SCHEDULING,
        action='schedule.status_change',
        target=schedule,
        actor=actor,
        old_values={'status': old_status},
        new_values={'status': new_status, 'reason': reason},
    )
    return schedule
```

**Step 2 — Refactor Board view** at [board/views.py:134-146](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L134-L146):

```diff
 def patch(self, request, schedule_id):
     schedule = self.get_object(request, schedule_id)
-    serializer = DefenseScheduleStatusSerializer(data=request.data, context={'schedule': schedule})
-    serializer.is_valid(raise_exception=True)
-    schedule = serializer.save()
+    from defense.scheduler.services import transition_schedule_status
+    schedule = transition_schedule_status(schedule, request.data.get('status'), actor=request.user, reason='board_view')
```

**Step 3 — Refactor Grade service** at [services.py:1172-1184](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L1172-L1184):

```diff
-if grade.schedule_id and grade.schedule.status != DefenseSchedule.STATUS_DONE:
-    grade.schedule.status = DefenseSchedule.STATUS_DONE
-    grade.schedule.save(update_fields=['status', 'updated_at'])
+if grade.schedule_id and grade.schedule.status != DefenseSchedule.STATUS_DONE:
+    from defense.scheduler.services import transition_schedule_status
+    transition_schedule_status(grade.schedule, DefenseSchedule.STATUS_DONE, actor=user, reason='grade_finalized')
```

**Step 4 — Make both serializers import `VALID_TRANSITIONS`** from the service instead of defining their own copies.

---

## 🔴 3. Team Status Modified via Grade Publish AND Direct Team Edit

**Priority**: P0 — Fix Immediately

**Problem**: `StudentTeam.status` is set in two places:

| # | Mutation path | Location |
|---|--------------|----------|
| 1 | Grade publish/finalize | [_apply_team_result_from_grade](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L1600-L1612) sets `team.status` to `STATUS_APPROVED` or `STATUS_FAILED` |
| 2 | Direct team PATCH | `StudentTeamDetailView.patch` can update team `status` directly |

**Why it's dangerous (how the code works now)**:
- An admin publishes a grade → `_apply_team_result_from_grade()` sets `team.status = 'Approved'`.
- Another user (or the same admin) then PATCHes the team directly → sets `team.status = 'Active'`.
- Now the published grade says "Approved" but the team says "Active". These are permanently out of sync.
- No guard prevents overwriting a grade-derived team status.

**Recommended Fix**:

Add a guard in `StudentTeamDetailView.patch` in [student_teams/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/views.py):

```diff
 def patch(self, request, pk):
     team = self.get_object(pk)
     assert_team_writable(request.user, team)
+
+    # Prevent overriding a grade-derived team status
+    if 'status' in request.data:
+        from grading.grades.models import TeamGrade
+        published_grade = TeamGrade.objects.filter(
+            team=team, status=TeamGrade.STATUS_PUBLISHED
+        ).exists()
+        if published_grade:
+            return Response(
+                {'status': 'Team status is locked because a published grade exists. Unpublish the grade to change team status.'},
+                status=status.HTTP_409_CONFLICT,
+            )
+
     serializer = ...
```

---

## 🔴 4. `adviser_score` Written from Two Modules with Different Validation

**Priority**: P0 — Fix Immediately

**Problem**: `TeamGrade.adviser_score` can be written from:

| # | Endpoint | View | Validation |
|---|----------|------|------------|
| 1 | `POST /api/grading/grades/adviser-grades/<id>/submit/` | `AdviserSubmitGradeView.post` | Checks `LOCKED_STATUSES`, `require_grade_editable`, `require_matching_rubric`, adviser grading enabled flag |
| 2 | `PATCH /api/grading/grades/<id>/` | `GradeCenterDetailView.patch` | Only checks `require_grade_editable` via `TeamGradeUpdateSerializer` |

**Why it's dangerous (how the code works now)**:
- The admin PATCH endpoint (2) can write `adviser_score` **even when `capstone_adviser_grading_enabled` is false** and **without rubric validation**.
- If an admin sets `adviser_score` manually, then the adviser submits through endpoint 1, the adviser's validated score overwrites via `grade.save()` — but the breakdown data is now from the adviser while the raw score may have been from the admin. No conflict resolution exists.

**Recommended Fix**:

Add validation in `TeamGradeUpdateSerializer.validate()` in [serializers.py:242-260](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/serializers.py#L242-L260):

```diff
 def validate(self, attrs):
     if not attrs:
         raise serializers.ValidationError('At least one score or status field is required.')
+
+    # Block if editing disabled grading components
+    grade = self.context['grade']
+    if 'adviser_score' in attrs and grade.scope == TeamGrade.SCOPE_CAPSTONE:
+        semester = grade.semester
+        if not getattr(semester, 'capstone_adviser_grading_enabled', True):
+            raise serializers.ValidationError({
+                'adviser_score': 'Adviser grading is disabled for this semester. Enable it in Evaluation Settings first.'
+            })
+
     if attrs.get('status') == TeamGrade.STATUS_PUBLISHED:
         # ... existing publish validation ...
```

---

## 🟠 5. Seven Independent `active_semester()` Functions

**Priority**: P1 — Fix Soon

**Problem**: The concept of "get the active semester" is implemented as **7 separate function definitions** plus multiple inline `Semester.objects.filter(is_active=True).first()` calls:

| # | Location | Implementation |
|---|----------|----------------|
| 1 | [grading/grades/services.py:59](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L59) | Own copy with `select_related` |
| 2 | [student_teams/term_scope.py:24](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/term_scope.py#L24) | Own copy with `select_related` |
| 3 | [student_teams/views.py:79](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/views.py#L79) | Wraps `get_active_semester()` |
| 4 | [defense/scheduler/serializers.py:46](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/serializers.py#L46) | Own copy |
| 5 | [grading/rubrics/views.py:89](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/views.py#L89) | Own copy |
| 6 | [academic_period_management/views.py:21](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/academic_period_management/views.py#L21) | Own copy |
| 7 | [repository/deliverables/services.py:118](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/deliverables/services.py#L118) | Own copy |
| 8 | [user_management/academic_records/rollover.py:14](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/academic_records/rollover.py#L14) | Own copy |

**Inline queries that skip the helper entirely**:
- [reports/views.py:82, 132, 183](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/reports/views.py#L82) — no `select_related`
- [defense/scheduler/views.py:629, 933](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L629) — `team.semester or Semester.objects.filter(...).first()` fallback
- [dashboards/views.py:841](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L841) — no `select_related`

**Why it's dangerous (how the code works now)**:
- If the model or query logic changes (e.g., adding `is_archived` flag), not all copies will be updated.
- The `select_related('school_year')` prefetch is missing in some copies, causing inconsistent N+1 queries.
- The `team.semester or Semester.objects.filter(...)` fallback in scheduler views can pick a different semester than what the team is scoped to, potentially creating a `TeamGrade` row with a mismatched semester.

**Recommended Fix**:

**Step 1 — Create the one canonical function** in `academic_period_management/services.py` (new file):

```python
from .models import Semester

def active_semester():
    """Single source of truth for the currently active semester."""
    return Semester.objects.select_related('school_year').filter(is_active=True).first()
```

**Step 2 — Delete all 7+ duplicates** and replace with:

```python
from academic_period_management.services import active_semester
```

In `student_teams/term_scope.py`, add an alias for backwards compatibility:

```python
from academic_period_management.services import active_semester as get_active_semester
```

**Step 3 — Replace all inline queries** in `reports/views.py`, `scheduler/views.py`, and `dashboards/views.py` with the canonical import.

---

## 🟠 6. Duplicate `counts_payload()` in academic_records/views.py

**Priority**: P1 — Fix Soon

**Problem**: [academic_records/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/academic_records/views.py) defines `counts_payload()` **twice** — at line 46 and line 165. Both are identical.

**Why it's dangerous (how the code works now)**:
- Python uses the **last** definition in file scope — so the line-46 copy is dead code.
- If someone edits only the line-46 copy thinking it's the active one, nothing changes. If they edit only the line-165 copy, it works but the line-46 version becomes stale and confusing.
- During a refactor, updating one but not the other will cause subtle bugs.

**Recommended Fix**:

Delete the first `options_payload()` + `counts_payload()` block at lines 31–52. Keep the line-165 block (the one Python actually uses). Verify all callers reference the correct version.

---

## 🟠 7. Four Identical Permission Classes (`CanManage*`)

**Priority**: P1 — Fix Soon

**Problem**: The same "admin or PIT lead" permission check is implemented as 4 separate classes:

| Class | File |
|-------|------|
| `CanManageSchedules` | [scheduler/views.py:46](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L46) |
| `CanManageGradeCenter` | [grades/views.py:33](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/views.py#L33) |
| `CanManageBoard` | [board/views.py:18](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L18) |
| `CanManageRubrics` | [rubrics/views.py:16](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/views.py#L16) |

All check: `user.role == 'admin' or user.is_superuser or user.is_pit_lead`.

**Why it's dangerous (how the code works now)**:
- If the permission model changes (e.g., a new "department head" role), one class might be updated while the others remain unchanged, creating an access-control gap where some modules allow the role and others don't.

**Recommended Fix**:

**Step 1 — Create a single canonical permission** in [user_management/permissions.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/permissions.py):

```python
class CanManageModule(BasePermission):
    """Allows admin, superuser, or PIT lead to manage module resources."""
    message = 'Only administrators and PIT leads can manage this module.'

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user and user.is_authenticated
            and (getattr(user, 'role', None) == 'admin' or user.is_superuser or getattr(user, 'is_pit_lead', False))
        )
```

**Step 2 — Replace all four duplicates** with `from user_management.permissions import CanManageModule` and update `permission_classes`.

---

## 🟠 8. Default Grade Weights Defined in Two Places

**Priority**: P1 — Fix Soon

**Problem**: The default grade weight distribution is defined independently in:

| # | Location | Values |
|---|----------|--------|
| 1 | [grading/grades/services.py:63-66](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L63-L66) | `{'panel_weight': 50, 'adviser_weight': 30, 'peer_weight': 20}` / `{'panel_weight': 80, 'peer_weight': 20, 'adviser_weight': 0}` |
| 2 | [grading/rubrics/views.py:121-124](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/views.py#L121-L124) | `{'panel': 50, 'adviser': 30, 'peer': 20}` / `{'panel': 80, 'peer': 20}` |

**Why it's dangerous (how the code works now)**:
- The rubric view returns these as display metadata to the frontend. If someone changes the actual computation defaults in `services.py` but forgets the rubric view, the frontend will display wrong weights to users while the backend computes with different ones.

**Recommended Fix**:

Make the rubric view read from the canonical source at [rubrics/views.py:121-124](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/views.py#L121-L124):

```diff
+from grading.grades.services import default_weights
+
 'default_weights': {
-    'capstone': {'panel': 50, 'adviser': 30, 'peer': 20},
-    'pit': {'panel': 80, 'peer': 20},
+    'capstone': {
+        'panel': default_weights('capstone')['panel_weight'],
+        'adviser': default_weights('capstone')['adviser_weight'],
+        'peer': default_weights('capstone')['peer_weight'],
+    },
+    'pit': {
+        'panel': default_weights('pit')['panel_weight'],
+        'peer': default_weights('pit')['peer_weight'],
+    },
 },
```

---

## 🟠 9. Student Dashboard Grade Lookup Bypasses Canonical Resolution

**Priority**: P1 — Fix Soon

**Problem**: The student dashboard in [dashboards/views.py:572-594](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L572-L594) builds its grade display with a standalone `_student_visible_grade()` function that queries `TeamGrade` independently, bypassing the canonical resolution paths used everywhere else.

```python
# Current dashboard code — does NOT use canonical_capstone_grade_for_team
def _student_visible_grade(team, schedule):
    if schedule is not None:
        return TeamGrade.objects.filter(..., status=TeamGrade.STATUS_PUBLISHED).first()
    return TeamGrade.objects.filter(team=team, status=TeamGrade.STATUS_PUBLISHED).first()
```

**Why it's dangerous (how the code works now)**:
- Only shows `STATUS_PUBLISHED` grades — if a grade is `PENDING`, the student sees **no grade at all**.
- Does **not** filter by scope (capstone vs PIT), so it could return a PIT grade for a capstone team if the PIT grade was published more recently.
- Does **not** use `without_stale_unscheduled_placeholders()`, so it could return a stale placeholder.
- Meanwhile, line 851-859 of the **same view** uses `canonical_capstone_grade_for_team()` for peer evaluation context — so the same API response can show grade data from one source and peer eval data from a completely different grade record.

**Recommended Fix**:

**Step 1 — Rewrite `_student_visible_grade()`**:

```python
def _student_visible_grade(team, schedule):
    """Return the student-visible grade using canonical resolution."""
    if team is None:
        return None

    from grading.grades.services import canonical_capstone_grade_for_team, resolve_canonical_capstone_grade
    from grading.grades.models import TeamGrade

    if team.is_capstone:
        grade = canonical_capstone_grade_for_team(team, team.semester)
        if grade is not None:
            grade = resolve_canonical_capstone_grade(grade)
        if grade is not None and grade.status == TeamGrade.STATUS_PUBLISHED:
            return grade
        return None

    # PIT: use schedule-scoped or latest published
    base = TeamGrade.objects.filter(team=team, scope=TeamGrade.SCOPE_PIT)
    if schedule is not None:
        base = base.filter(semester=schedule.semester, stage_label=schedule.stage_label)
    return base.filter(status=TeamGrade.STATUS_PUBLISHED).order_by('-updated_at', '-id').first()
```

**Step 2 — Unify grade source** for display AND peer eval context in `StudentDashboardView.get()`:

```diff
-grade = _student_visible_grade(team, schedule)
-...
-peer_grade_row = None
-if team:
-    if team.is_capstone:
-        peer_grade_row = canonical_capstone_grade_for_team(team, team.semester)
-        ...
+# Unified grade resolution
+canonical_grade = None
+if team:
+    if team.is_capstone:
+        canonical_grade = canonical_capstone_grade_for_team(team, team.semester)
+        if canonical_grade is not None:
+            canonical_grade = resolve_canonical_capstone_grade(canonical_grade)
+    else:
+        canonical_grade = TeamGrade.objects.filter(
+            team=team, scope=TeamGrade.SCOPE_PIT
+        ).order_by('-updated_at', '-id').first()
+
+grade = canonical_grade if (canonical_grade and canonical_grade.status == TeamGrade.STATUS_PUBLISHED) else None
+peer_grade_row = canonical_grade
```

---

## 🟡 10. Semester Fallback in Grade Submission (`team.semester or active_semester()`)

**Priority**: P2 — Fix When Convenient

**Problem**: In [PanelistGradeSubmissionView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L629) and [GuestPanelistGradeSubmissionView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L933):

```python
semester = team.semester or Semester.objects.filter(is_active=True).first()
```

**Why it's dangerous (how the code works now)**:
- This fallback can pick a **different semester** than what the team is scoped to.
- If the logic is ever refactored to pass `semester` into the grade service, this fallback could cause grades to be created on the wrong semester.
- Currently the variable is only used for the "no active semester" error check, so it's a dead fallback — but its presence is misleading.

**Recommended Fix**:

```diff
-semester = team.semester or Semester.objects.filter(is_active=True).first()
-if not semester:
-    return Response({'error': 'No active semester is configured.'}, ...)
+if not team.semester:
+    return Response({'detail': 'This team has no semester assigned.'}, ...)
+semester = team.semester
```

---

## 🟡 11. Board vs Scheduler Delete Have Different Safety Checks

**Priority**: P2 — Fix When Convenient

**Problem**: Two endpoints delete schedules with different safety levels:

| # | Endpoint | Safety Check |
|---|----------|-------------|
| 1 | [DefenseBoardDetailView.delete](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L148-L165) | ✅ Checks `panelist_grade_submissions.exists()`, returns 409 warning |
| 2 | [DefenseScheduleDetailView.delete](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L334-L350) | ❌ No check — just deletes |

**Why it's dangerous (how the code works now)**:
- The scheduler endpoint is the more commonly used one, and it has **zero** safety checks — it will delete a schedule even if panelists have already submitted grades, permanently destroying those scores.
- The board endpoint at least warns, but doesn't hard-block.

**Recommended Fix**:

Add the same grade-data check to `DefenseScheduleDetailView.delete` in [scheduler/views.py:334-350](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L334-L350):

```diff
 def delete(self, request, schedule_id):
     schedule = self.get_object(request, schedule_id)
+
+    has_grade_data = schedule.panelist_grade_submissions.exists()
+    if has_grade_data:
+        return Response(
+            {'detail': 'This schedule has panelist grades already submitted. '
+             'Deleting it will permanently remove those individual scores. '
+             'Consider cancelling the schedule instead.',
+             'code': 'has_grade_data'},
+            status=status.HTTP_409_CONFLICT,
+        )
+
     schedule.delete()
```

Better long-term: unify both into a single `delete_schedule()` service function.

---Done

## 🟡 12. Report Filter Logic Diverges from Source List Views

**Priority**: P2 — Fix When Convenient

**Problem**: The search filters in report export views use a subset of fields vs the main list views:

| Filter Field | Grade Center List | Semester Grades Report |
|-------------|-------------------|----------------------|
| `team__name` | ✅ | ✅ |
| `team__project_title` | ✅ | ✅ |
| `stage_label` | ✅ | ✅ |
| `team__adviser__*` | ✅ | ❌ |
| `schedule__panel_assignments__panelist__*` | ✅ | ❌ |

Same issue in [DefenseScheduleReportView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/reports/views.py#L149-L155) — missing `defense_stage__label` and panelist search.

**Why it's dangerous (how the code works now)**:
- Users can get different result sets when exporting vs viewing the same data with the same search term, leading to confusion about data integrity.

**Recommended Fix**:

**Step 1 — Add missing fields** to [SemesterGradesReportView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/reports/views.py#L99-L104):

```diff
 if search:
     queryset = queryset.filter(
         Q(team__name__icontains=search)
         | Q(team__project_title__icontains=search)
         | Q(stage_label__icontains=search)
+        | Q(team__adviser__first_name__icontains=search)
+        | Q(team__adviser__last_name__icontains=search)
+        | Q(schedule__panel_assignments__panelist__first_name__icontains=search)
+        | Q(schedule__panel_assignments__panelist__last_name__icontains=search)
     ).distinct()
```

**Step 2 — Add missing fields** to [DefenseScheduleReportView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/reports/views.py#L149-L155):

```diff
 if search:
     queryset = queryset.filter(
         Q(team__name__icontains=search)
         | Q(team__project_title__icontains=search)
         | Q(room__icontains=search)
         | Q(event_name__icontains=search)
+        | Q(defense_stage__label__icontains=search)
+        | Q(panel_assignments__panelist__first_name__icontains=search)
+        | Q(panel_assignments__panelist__last_name__icontains=search)
     ).distinct()
```

**Better long-term**: Extract filter logic into a `filter_queryset()` function per module that both the list view and the report view call.

---

## 🟡 13. Grade Weights Fallback Chain Has 4 Levels

**Priority**: P2 — Fix When Convenient

**Problem**: `weights_for_schedule()` at [services.py:626-652](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L626-L652) has a complex fallback chain:

1. StageGradingConfig / PitEventGradingConfig (if configured)
2. Schedule's rubric custom weights
3. `default_weights()` for the scope

**Why it's dangerous (how the code works now)**:
- Each level can return different weights for the same schedule.
- If a PIT event config is created **after** a grade was already created with rubric weights, the grade's weights won't retroactively update unless a sync is manually triggered.
- No documentation explains the precedence order.

**Recommended Fix**:

**Step 1 — Document the precedence** with an inline docstring:

```python
def weights_for_schedule(schedule):
    """
    Weight resolution order (first match wins):
    1. StageGradingConfig / PitEventGradingConfig (if configured)
    2. Schedule's rubric custom weights
    3. default_weights() for the scope

    IMPORTANT: Existing TeamGrade rows are NOT retroactively updated
    when a config is created after the grade. Call sync_missing_grade_rows() to recompute.
    """
```

**Step 2 — Add retroactive sync** when a config is saved:

```python
# defense/stages/grading_config.py — after saving the config:
from grading.grades.models import TeamGrade
TeamGrade.objects.filter(
    defense_stage=config.defense_stage,
    semester=config.semester,
    status=TeamGrade.STATUS_PENDING,
).update(
    panel_weight=config.panel_weight,
    adviser_weight=config.adviser_weight,
    peer_weight=config.peer_weight,
)
```

---

## 🟡 14. Peer Grading Enabled — Dashboard vs Submit Check

**Priority**: P2 — Fix When Convenient

**Problem**: Two separate sources determine if peer evaluation is enabled:

| Source | Logic |
|--------|-------|
| [peer_grading_allowed_for_grade](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L2143-L2147) | PIT: checks `group_settings.peer_grading_enabled`; Capstone: checks `semester.capstone_peer_evaluation_enabled` |
| `submit_student_peer_evaluation()` in `peer_eval.py` | Has its own peer-enabled check |

**Why it's dangerous (how the code works now)**:
- The dashboard correctly calls `peer_grading_allowed_for_grade()` to show "peer eval enabled".
- But the submit endpoint in `peer_eval.py` uses its own internal check.
- If those two paths diverge, the dashboard could show "peer eval enabled" while the submit endpoint rejects, or vice versa.

**Recommended Fix**:

Ensure `submit_student_peer_evaluation()` in `peer_eval.py` calls the canonical function:

```diff
 # grading/grades/peer_eval.py — inside submit_student_peer_evaluation()
+from .services import peer_grading_allowed_for_grade
+if not peer_grading_allowed_for_grade(grade):
+    raise ValidationError({'peer_eval': 'Peer grading is not currently enabled for this grade.'})
```

---Done

## 🔵 15. Duplicate Function Blocks in academic_records/views.py

**Priority**: P2 — Fix When Convenient

**Problem**: [academic_records/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/academic_records/views.py) defines `options_payload()` and `counts_payload()` twice — at lines 31–52 and again at lines 148–171. Both blocks are identical.

**Why it's dangerous (how the code works now)**:
- Python uses the last definition — so the line-46 copy is dead code today.
- During future edits, developers may update the wrong copy.

**Recommended Fix**: Delete the first block (lines 31–52). Keep the line-148–171 block. Verify callers.

---Done

---

## 🔵 16. Inconsistent Error Response Shapes

**Priority**: P2 — Fix When Convenient

**Problem**: Error responses across endpoints use different payload shapes:

| Pattern | Used In |
|---------|---------|
| `{'detail': 'message'}` | Most endpoints (DRF standard) |
| `{'error': 'message'}` | [scheduler/views.py:632](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L632), [scheduler/views.py:740](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L740) |
| `{'warning': 'message'}` | [board/views.py:155](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L155) |

**Why it's dangerous (how the code works now)**:
- Frontend must handle multiple error shapes, making global error handling fragile. A global error interceptor that checks `response.data.detail` will miss `error` and `warning` keys.

**Recommended Fix**: Standardize all to `{'detail': '...'}` (DRF convention):

| File | Line | Change |
|------|------|--------|
| [scheduler/views.py:632](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L632) | 632 | `{'error': ...}` → `{'detail': ...}` |
| [scheduler/views.py:740](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L740) | 740 | `{'error': ...}` → `{'detail': ...}` |
| [board/views.py:155](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L155) | 155 | `{'warning': ...}` → `{'detail': ..., 'code': 'has_grade_data'}` |

---Done

---

## 🔵 17. Dashboard Triple Semester Query

**Priority**: P2 — Fix When Convenient

**Problem**: The dashboard views query `Semester.objects.filter(is_active=True)` multiple times in a single request — `_active_semester_label()` at [dashboards/views.py:137](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L137), plus inline at [line 841](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L841), etc.

**Why it's dangerous (how the code works now)**:
- Not a corruption risk, but 3 separate identical database queries in one API response is wasteful.
- If an admin deactivates the semester between queries in the same request (unlikely but possible), each query could return a different result.

**Recommended Fix**: Cache the semester at the top of each dashboard view and pass it down:

```diff
+from academic_period_management.services import active_semester
+active_sem = active_semester()
 ...
-active_sem = Semester.objects.filter(is_active=True).first()
```

Refactor `_active_semester_label()` to accept an optional parameter:

```diff
-def _active_semester_label():
-    semester = Semester.objects.select_related('school_year').filter(is_active=True).first()
-    return semester.display_name if semester else 'Not configured'
+def _active_semester_label(semester=None):
+    if semester is None:
+        from academic_period_management.services import active_semester
+        semester = active_semester()
+    return semester.display_name if semester else 'Not configured'
```

---Done

---

## Full Endpoint Map (Reference)

| # | Full URL | HTTP Methods | View Class | Module |
|---|----------|-------------|------------|--------|
| 1 | `api/login/` | POST | `CustomTokenObtainPairView` | authentication_access_control |
| 2 | `api/token/refresh/` | POST | `ThrottledTokenRefreshView` | authentication_access_control |
| 3 | `api/logout/` | POST | `LogoutView` | authentication_access_control |
| 4 | `api/me/` | GET | `CurrentUserView` | authentication_access_control |
| 5 | `api/audit-logs/` | GET | `SystemAuditLogListView` | authentication_access_control |
| 6 | `api/dashboards/admin/` | GET | `AdminDashboardView` | dashboards |
| 7 | `api/dashboards/pit-lead/cohort/` | GET | `PitLeadCohortView` | dashboards |
| 8 | `api/dashboards/pit-lead/cohort/rollover-preview/` | GET | `PitLeadCohortRolloverPreviewView` | dashboards |
| 9 | `api/dashboards/pit-lead/cohort/rollover/` | POST | `PitLeadCohortRolloverConfirmView` | dashboards |
| 10 | `api/dashboards/faculty/` | GET | `FacultyDashboardView` | dashboards |
| 11 | `api/dashboards/student/` | GET | `StudentDashboardView` | dashboards |
| 12 | `api/dashboards/panelist/` | GET | `PanelistDashboardView` | dashboards |
| 13 | `api/academic-periods/` | GET, POST | `AcademicPeriodListCreateView` | academic_period_management |
| 14 | `api/academic-periods/<id>/semesters/` | POST | `SemesterCreateView` | academic_period_management |
| 15 | `api/academic-periods/semesters/<id>/transition-preview/` | GET | `SemesterTransitionPreviewView` | academic_period_management |
| 16 | `api/academic-periods/semesters/<id>/activate/` | POST | `SemesterActivateView` | academic_period_management |
| 17 | `api/academic-periods/semesters/<id>/` | GET | `SemesterStatusView` | academic_period_management |
| 18 | `api/users/` | GET, POST | `UserListCreateView` | user_management |
| 19 | `api/users/bulk-import/` | POST | `BulkImportUsersView` | user_management |
| 20 | `api/users/pit-lead/student-import/` | POST | `PitLeadStudentImportView` | user_management |
| 21 | `api/users/pit-lead/official-class-list-import/` | POST | `PitLeadOfficialClassListImportView` | user_management |
| 22 | `api/users/pit-instructors/` | GET, POST | `PitInstructorAssignmentView` | user_management |
| 23 | `api/users/pit-instructors/<id>/` | GET, PATCH, DELETE | `PitInstructorAssignmentDetailView` | user_management |
| 24 | `api/users/guest-codes/` | GET, POST | `GuestPanelistCodeListCreateView` | user_management |
| 25 | `api/users/guest-codes/<id>/` | GET, PATCH, DELETE | `GuestPanelistCodeDetailView` | user_management |
| 26 | `api/users/guest-codes/exchange/` | POST | `GuestCodeExchangeView` | user_management |
| 27 | `api/users/guest-codes/validate/<code>/` | GET | `GuestCodeValidateView` | user_management |
| 28 | `api/users/e-signature/` | GET, POST | `UserESignatureView` | user_management |
| 29 | `api/users/<id>/adviser-assignments/` | GET | `UserAdviserAssignmentHistoryView` | user_management |
| 30 | `api/users/<id>/role-assignments/` | GET | `UserRoleAssignmentHistoryView` | user_management |
| 31 | `api/users/<id>/` | GET, PATCH, DELETE | `UserDetailView` | user_management |
| 32 | `api/users/academic-records/` | GET, POST | `StudentAcademicRecordListCreateView` | user_management.academic_records |
| 33 | `api/users/academic-records/rollover-preview/` | GET | `RolloverPreviewView` | user_management.academic_records |
| 34 | `api/users/academic-records/rollover/` | POST | `RolloverConfirmView` | user_management.academic_records |
| 35 | `api/users/academic-records/<id>/` | GET, PATCH, DELETE | `StudentAcademicRecordDetailView` | user_management.academic_records |
| 36 | `api/teams/` | GET, POST | `StudentTeamListCreateView` | student_teams |
| 37 | `api/teams/section-assignments/` | GET, POST | `SectionAssignmentListCreateView` | student_teams |
| 38 | `api/teams/section-assignments/<id>/` | GET, PATCH, DELETE | `SectionAssignmentDetailView` | student_teams |
| 39 | `api/teams/bulk-import/preview/` | POST | `BulkImportTeamsPreviewView` | student_teams |
| 40 | `api/teams/bulk-import/` | POST | `BulkImportTeamsView` | student_teams |
| 41 | `api/teams/<id>/remind/` | POST | `StudentTeamSendReminderView` | student_teams |
| 42 | `api/teams/<id>/adviser-history/` | GET | `TeamAdviserHistoryView` | student_teams |
| 43 | `api/teams/<id>/` | GET, PATCH, DELETE | `StudentTeamDetailView` | student_teams |
| 44 | `api/teams/documents/` | GET | `TeamDocumentListView` | student_teams.documents |
| 45 | `api/teams/documents/upload/` | POST | `TeamDocumentUploadView` | student_teams.documents |
| 46 | `api/teams/documents/<id>/` | GET, DELETE | `TeamDocumentDetailView` | student_teams.documents |
| 47 | `api/teams/documents/<id>/download/` | GET | `TeamDocumentDownloadView` | student_teams.documents |
| 48 | `api/teams/weekly-progress/` | GET, POST | `StudentWeeklyProgressListCreateView` | student_teams.weekly_progress |
| 49 | `api/teams/weekly-progress/<id>/` | GET, PATCH, DELETE | `StudentWeeklyProgressDetailView` | student_teams.weekly_progress |
| 50 | `api/teams/weekly-progress/<id>/file/` | GET | `WeeklyProgressReportFileView` | student_teams.weekly_progress |
| 51 | `api/defense/stages/` | GET, POST | `DefenseStageListCreateView` | defense.stages |
| 52 | `api/defense/stages/<id>/` | GET, PATCH, DELETE | `DefenseStageDetailView` | defense.stages |
| 53 | `api/defense/stages/<id>/grading-config/` | GET, PATCH | `StageGradingConfigView` | defense.stages |
| 54 | `api/defense/stages/<id>/deliverables/` | GET, POST | `StageDeliverableListCreateView` | defense.stages |
| 55 | `api/defense/stages/<id>/deliverables/<id>/` | GET, PATCH, DELETE | `StageDeliverableDetailView` | defense.stages |
| 56 | `api/defense/schedules/` | GET, POST | `DefenseScheduleListCreateView` | defense.scheduler |
| 57 | `api/defense/schedules/pit-event-config/` | GET, POST, DELETE | `PitEventConfigLookupView` | defense.scheduler |
| 58 | `api/defense/schedules/generate-plan/` | POST | `DefenseScheduleGeneratePlanView` | defense.scheduler |
| 59 | `api/defense/schedules/confirm-plan/` | POST | `DefenseScheduleConfirmPlanView` | defense.scheduler |
| 60 | `api/defense/schedules/panelist-assignments/` | GET | `PanelistAssignmentsView` | defense.scheduler |
| 61 | `api/defense/schedules/panelist-results/` | GET | `PanelistResultsView` | defense.scheduler |
| 62 | `api/defense/schedules/guest-assignments/` | GET | `GuestPanelistAssignmentsView` | defense.scheduler |
| 63 | `api/defense/schedules/guest-panelist-results/` | GET | `GuestPanelistResultsView` | defense.scheduler |
| 64 | `api/defense/schedules/submit-grades/` | POST | `PanelistGradeSubmissionView` | defense.scheduler |
| 65 | `api/defense/schedules/guest-submit-grades/` | POST | `GuestPanelistGradeSubmissionView` | defense.scheduler |
| 66 | `api/defense/schedules/<id>/` | GET, PATCH, DELETE | `DefenseScheduleDetailView` | defense.scheduler |
| 67 | `api/defense/board/` | GET | `DefenseBoardListView` | defense.board |
| 68 | `api/defense/board/<id>/` | GET, PATCH, DELETE | `DefenseBoardDetailView` | defense.board |
| 69 | `api/defense/minutes/my-assignments/` | GET | `MyDocumenterAssignmentsView` | defense.minutes |
| 70 | `api/defense/minutes/<id>/` | GET | `MinutesDetailView` | defense.minutes |
| 71 | `api/defense/minutes/<id>/submit/` | POST | `MinutesSubmitView` | defense.minutes |
| 72 | `api/defense/minutes/<id>/sign-adviser/` | POST | `MinutesSignAdviserView` | defense.minutes |
| 73 | `api/defense/minutes/<id>/sign-chairman/` | POST | `MinutesSignChairmanView` | defense.minutes |
| 74 | `api/defense/minutes/<id>/pdf/` | GET | `MinutesPdfView` | defense.minutes |
| 75 | `api/grading/rubrics/` | GET, POST | `RubricListCreateView` | grading.rubrics |
| 76 | `api/grading/rubrics/<id>/` | GET, PATCH, DELETE | `RubricDetailView` | grading.rubrics |
| 77 | `api/grading/rubrics/<id>/publish/` | POST | `RubricPublishView` | grading.rubrics |
| 78 | `api/grading/rubrics/<id>/weights/` | GET, PATCH | `RubricWeightsView` | grading.rubrics |
| 79 | `api/grading/grades/` | GET | `GradeCenterListView` | grading.grades |
| 80 | `api/grading/grades/sync/` | POST | `GradeCenterSyncView` | grading.grades |
| 81 | `api/grading/grades/evaluation-settings/` | PATCH | `CapstoneEvaluationSettingsView` | grading.grades |
| 82 | `api/grading/grades/group-settings/` | PATCH | `GradeCenterGroupSettingsView` | grading.grades |
| 83 | `api/grading/grades/<id>/` | GET, PATCH | `GradeCenterDetailView` | grading.grades |
| 84 | `api/grading/grades/<id>/publish/` | POST | `GradeCenterPublishView` | grading.grades |
| 85 | `api/grading/grades/adviser-grades/` | GET | `AdviserGradeListView` | grading.grades |
| 86 | `api/grading/grades/adviser-grades/<id>/submit/` | POST | `AdviserSubmitGradeView` | grading.grades |
| 87 | `api/grading/grades/peer-evaluations/` | POST | `StudentPeerEvaluationSubmitView` | grading.grades |
| 88 | `api/repository/vault/` | GET | `DigitalVaultListView` | repository.vault |
| 89 | `api/repository/vault/search/` | GET | `DigitalVaultSearchView` | repository.vault |
| 90 | `api/repository/deliverables/` | GET | `CapstoneDeliverablesListView` | repository.deliverables |
| 91 | `api/repository/deliverables/upload/` | POST | `CapstoneDeliverableUploadView` | repository.deliverables |
| 92 | `api/repository/deliverables/remove/` | POST | `CapstoneDeliverableRemoveView` | repository.deliverables |
| 93 | `api/repository/deliverables/endorse/` | POST | `CapstoneDeliverableEndorseView` | repository.deliverables |
| 94 | `api/repository/deliverables/review/` | POST | `CapstoneDeliverableReviewView` | repository.deliverables |
| 95 | `api/repository/deliverables/compile-weekly-reports/` | POST | `CompileWeeklyReportsView` | repository.deliverables |
| 96 | `api/repository/audit/` | GET | `RepositoryAuditListView` | repository.audit |
| 97 | `api/repository/audit/upload-pit/` | POST | `RepositoryAuditUploadPitView` | repository.audit |
| 98 | `api/repository/audit/upload-capstone/` | POST | `RepositoryAuditUploadCapstoneView` | repository.audit |
| 99 | `api/repository/audit/override-status/` | POST | `RepositoryAuditOverrideStatusView` | repository.audit |
| 100 | `api/repository/audit/trail/` | GET | `RepositoryAuditTrailView` | repository.audit |
| 101 | `api/repository/audit/export/` | GET | `RepositoryAuditExportView` | repository.audit |
| 102 | `api/curriculum-analytics/` | GET | `CurriculumAnalyticsView` | curriculum_analytics |
| 103 | `api/curriculum-analytics/proposal/` | GET, POST | `CurriculumProposalView` | curriculum_analytics |
| 104 | `api/reports/team-grade/<id>/` | GET | `TeamGradeReportView` | reports |
| 105 | `api/reports/semester-grades/` | GET | `SemesterGradesReportView` | reports |
| 106 | `api/reports/defense-schedules/` | GET | `DefenseScheduleReportView` | reports |
| 107 | `api/reports/team-roster/` | GET | `TeamRosterReportView` | reports |
| 108 | `api/reports/user-directory/` | GET | `UserDirectoryReportView` | reports |
| 109 | `api/reports/audit-trail/` | GET | `AuditTrailReportView` | reports |
| 110 | `api/notifications/` | GET | `NotificationListView` | notifications |
| 111 | `api/notifications/<id>/read/` | POST | `NotificationReadView` | notifications |
| 112 | `api/notifications/read-all/` | POST | `NotificationReadAllView` | notifications |
| 113 | `api/media/files/<path>/` | GET | `AuthenticatedMediaFileView` | defensys_backend |
