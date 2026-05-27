# DefenSYS Business Logic Audit

> Audit focused on **logic bugs, flow disruptions, and data integrity** risks.
> Not production security — these are things that can break defenses, corrupt grades, or lose event data.
>
> **Audited:** 2026-05-28

---

## Findings Summary

| # | Severity | Area | Finding |
|---|----------|------|---------|
| 1 | 🔴 Critical | Grading | `rebuild_peer_member_grades` uses **hardcoded fake scores** |
| 2 | 🔴 Critical | Grading | Panelist can overwrite grades on a **published/archived** TeamGrade |
| 3 | 🟠 High | Scheduling | No status transition guard — schedule can go `done → scheduled` |
| 4 | 🟠 High | Grading | `require_grade_editable` not enforced on panelist grade submission |
| 5 | 🟠 High | Grading | Deleting a `DefenseSchedule` cascades and orphans grade records |
| 6 | 🟠 High | Defense Stages | Deleting a `DefenseStage` can break existing grades and schedules |
| 7 | 🟡 Medium | Peer Eval | Students can re-submit peer evaluations after stage is complete |
| 8 | 🟡 Medium | Scheduling | Duplicate team schedule check ignores `done` status |
| 9 | 🟡 Medium | Grading | `canonical_capstone_grade_for_team` can pick the wrong grade row |
| 10 | 🟡 Medium | Teams | Deleting a `StudentTeam` cascades all grades, schedules, progress |
| 11 | 🟡 Medium | Academic Period | Multiple `is_active=True` semesters breaks the entire system |
| 12 | 🟢 Low | Grade Center | `sync_missing_grade_rows` creates grades on every GET in some views |
| 13 | 🟢 Low | Dashboard | WebSocket only serves `student` role — faculty/admin miss realtime updates |

---

## 🔴 Critical Findings

### 1. `rebuild_peer_member_grades` uses hardcoded fake scores

**File:** `grading/grades/services.py:1229-1253`

```python
def rebuild_peer_member_grades(grade):
    # ...
    for index, membership in enumerate(memberships):
        average = Decimal('4.20') + (Decimal(index % 4) * Decimal('0.20'))
        if average > Decimal('4.90'):
            average = Decimal('4.90')
        peer_rows.append(
            StudentPeerGrade(
                team_grade=grade,
                student=membership.student,
                average_score=average,  # ← HARDCODED fake data!
                max_score=Decimal('5.00'),
            )
        )
```

**Risk:** This function generates **fake peer evaluation scores** (4.20 → 4.80, cycling by member index). If any code path calls this, students get grades they didn't earn. It looks like placeholder/test code that was never replaced with real logic.

Currently it's only defined — not called from any view or service method — but it's a **time bomb** if anyone invokes it or if a management command references it.

**Fix:** Either:
- Delete this function entirely if it was only for testing
- Replace with actual logic that reads from `PeerEvaluationSubmission` records (like `sync_peer_summaries` already does correctly)

**Status:** `[x] Fixed — function deleted (dead code, zero references)`

---

### 2. Panelist can overwrite grades on a published/archived TeamGrade

**File:** `defense/scheduler/views.py:444-550` (PanelistGradeSubmissionView)

```python
class PanelistGradeSubmissionView(APIView):
    def post(self, request):
        # ...
        team_grade = GradeContextService.get_for_panel_submission(schedule, panelist=panelist)
        submit_panelist_grade(schedule, team_grade, criteria_scores, ...)
        # ↑ No check if team_grade.status is 'published' or 'ready_for_archive'!
```

**Risk:** A panelist can submit grades even after the TeamGrade has been finalized/published. The `submit_panelist_grade` function calls `recompute_panel_score` which overwrites `team_grade.panel_score` and calls `team_grade.save()` — this **changes the published final grade**. The `require_grade_editable` guard is only used in the admin Grade Center views, not here.

The same issue exists for `GuestPanelistGradeSubmissionView` (line 656).

**Fix:** Add a status check before grade submission:
```python
if team_grade.status in TeamGrade.LOCKED_STATUSES:
    return Response(
        {'detail': 'Grades for this team have already been finalized.'},
        status=status.HTTP_400_BAD_REQUEST,
    )
```

**Status:** `[x] Fixed — both PanelistGradeSubmissionView and GuestPanelistGradeSubmissionView now reject when TeamGrade is in LOCKED_STATUSES`


---

## 🟠 High Findings

### 3. No status transition guard on schedule status changes

**File:** `defense/scheduler/serializers.py:633-640`

```python
class DefenseScheduleStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=...)

    def save(self):
        schedule = self.context['schedule']
        schedule.status = self.validated_data['status']
        schedule.save()  # ← Any status → any status, no validation!
```

**Risk:** An admin can set a `done` or `cancelled` schedule back to `scheduled`, which:
- Re-enables panelist grading for a team that already has finalized grades
- Breaks the `_validate_duplicate` check (it only checks `scheduled` status)
- Can cause a team to appear twice in the schedule list for the same stage

**Fix:** Add transition validation:
```python
VALID_TRANSITIONS = {
    'scheduled': ['done', 'cancelled'],
    'done': ['archived'],
    'cancelled': ['scheduled'],  # Allow re-schedule from cancelled only
    'archived': [],              # Terminal state
}

def validate_status(self, value):
    current = self.context['schedule'].status
    allowed = VALID_TRANSITIONS.get(current, [])
    if value not in allowed:
        raise serializers.ValidationError(
            f'Cannot transition from {current} to {value}.'
        )
    return value
```

**Status:** `[x] Fixed — scheduled→done/cancelled, cancelled→scheduled, done→archived, archived=terminal`


---

### 4. `require_grade_editable` not enforced on panelist/adviser submission

The `require_grade_editable` guard checks if a stage/event is officially complete and blocks edits — but it's only called in `GradeCenterDetailView.patch()` and `GradeCenterPublishView.post()` (admin views).

**NOT called in:**
- `PanelistGradeSubmissionView.post()` — panelist can grade after stage is officially complete
- `GuestPanelistGradeSubmissionView.post()` — same for guest panelists
- `submit_student_peer_evaluation()` — students can still submit peer evals
- `AdviserGradeSubmitView` — advisers can still submit

**Risk:** After an admin marks a stage "officially complete" (which triggers auto-finalization), panelists/students/advisers can still submit grades, overwriting finalized scores.

**Fix:** Add the guard to all submission endpoints.

**Status:** `[x] Fixed — guard added to PanelistGradeSubmissionView, GuestPanelistGradeSubmissionView, AdviserSubmitGradeView, and submit_student_peer_evaluation. Works for both admin (capstone) and PIT lead (PIT events).`


---

### 5. Deleting a `DefenseSchedule` orphans grade records

**File:** `defense/scheduler/models.py:36-39` + `grading/grades/models.py:33-39`

```python
# DefenseSchedule model:
team = models.ForeignKey('student_teams.StudentTeam', on_delete=models.CASCADE)

# TeamGrade model:
schedule = models.ForeignKey('defense.DefenseSchedule', null=True, on_delete=models.SET_NULL)
```

When an admin deletes a schedule via `DefenseScheduleDetailView.delete()`:
- The `TeamGrade.schedule` is set to `NULL` (good — grade isn't deleted)
- But the grade now has `schedule=None`, so `weights_for_schedule(None)` returns default weights
- The grade's `stage_label` might become "Unscheduled" on next sync
- Panel submissions (`PanelistGradeSubmission`) CASCADE delete — **all individual panelist scores are lost**

**Risk:** Deleting a defense schedule silently destroys panelist score records even though the team grade survives.

**Fix:** Either:
- Prevent deletion when grade data exists (return 400 with a warning)
- Change `PanelistGradeSubmission.schedule` to `on_delete=SET_NULL` instead of CASCADE

**Status:** `[x] Fixed — board delete returns friendly 409 warning when panelist submissions exist, suggests cancelling instead`


---

### 6. Deleting a `DefenseStage` breaks existing data

**File:** `defense/stages/views.py:128-131`

```python
def delete(self, request, stage_id):
    stage = self.get_object(stage_id)
    stage.delete()  # ← No check for existing schedules/grades/progress
```

The stage uses `on_delete=PROTECT` on schedules and grades, so Django will raise a `ProtectedError` at the database level — but the view doesn't catch it. The user gets a raw 500 error.

**Risk:** Admin sees a confusing 500 error instead of a helpful "This stage has defense schedules that depend on it" message.

**Fix:**
```python
from django.db.models import ProtectedError

def delete(self, request, stage_id):
    stage = self.get_object(stage_id)
    try:
        stage.delete()
    except ProtectedError:
        return Response(
            {'detail': 'Cannot delete stage with existing schedules or grades.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
```

**Status:** `[x] Fixed — catches ProtectedError and returns 409 with warning key for toastification`


---

## 🟡 Medium Findings

### 7. Students can re-submit peer evaluations after stage is officially complete

**File:** `grading/grades/peer_eval.py:186-224`

The `submit_student_peer_evaluation` function checks `peer_grading_allowed_for_grade()` which checks `peer_grading_enabled` — but once the stage is marked "officially complete", `peer_grading_enabled` might still be `True` (they're independent flags).

After `is_officially_complete=True`, submitted peer evals call `sync_peer_summaries` → `maybe_auto_finalize_passed_grade` — which tries to re-finalize already-finalized grades, potentially resetting statuses.

**Fix:** Check `is_officially_complete` in `submit_student_peer_evaluation`.

**Status:** `[x] Fixed — already covered by finding #4 (require_grade_editable + LOCKED_STATUSES guard added to submit_student_peer_evaluation)`


---

### 8. Duplicate team schedule check ignores `done` status

**File:** `defense/scheduler/serializers.py:498-501`

```python
def _validate_duplicate(self, attrs):
    queryset = self._context_filter(attrs).filter(team=attrs['team'])
    # self._context_filter only checks STATUS_SCHEDULED
    if queryset.exists():
        raise serializers.ValidationError(...)
```

The `_context_filter` uses `ACTIVE_STATUSES = [DefenseSchedule.STATUS_SCHEDULED]`, which means a team can be scheduled again for the same stage if their previous defense is `done` (not yet archived).

**Risk:** This is probably **intentional** for re-defense scenarios, but it means a team could accidentally get two grade contexts for the same stage — causing confusion in the Grade Center.

**Fix:** If re-defense is intended, the old `TeamGrade` should be explicitly archived first. If not, add `STATUS_DONE` to the duplicate check.

**Status:** `[x] Fixed — duplicate check now includes both STATUS_SCHEDULED and STATUS_DONE (single schedule + bulk plan)`


---

### 9. `canonical_capstone_grade_for_team` picks the wrong grade in edge cases

**File:** `grading/grades/services.py:524-597`

The function has multiple fallback layers:
1. Grade matching schedule + team + semester + stage
2. Grade matching stage_label 
3. Any capstone grade for team (broadest fallback at line 589)

The final fallback (`order_by('-updated_at', '-id').first()`) returns whichever grade was most recently updated — which might be from a different defense stage.

**Risk:** If a team has grades for both "Proposal Defense" and "Final Defense", and the Final Defense grade was updated more recently, a query for "Proposal Defense" could fall through to the wrong grade.

**Fix:** Remove or restrict the broadest fallback at line 589. At minimum, never fall through across different `defense_stage` records.

**Status:** `[x] Fixed — removed broadest fallback that ignored stage_label; now always filters by resolved_label`


---

### 10. Deleting a `StudentTeam` cascades all grades, schedules, and progress

`StudentTeam` → `defense_schedules` uses `CASCADE`, and `TeamGrade` → `team` uses `CASCADE`.

**Risk:** If an admin deletes a team (e.g., during re-organization), **all defense schedules, grades, breakdowns, peer evaluations, and stage progress** are permanently destroyed with no recovery.

**Fix:** Either:
- Add a soft-delete mechanism to `StudentTeam`
- Change to `PROTECT` and require archiving the team instead of deleting

**Status:** `[x] Fixed — backend returns 409 warning when team has schedules/grades; frontend handles with toastification`


---

### 11. Multiple `is_active=True` semesters breaks the system

**File:** `academic_period_management/models.py` + every `active_semester()` call

```python
def active_semester():
    return Semester.objects.filter(is_active=True).first()
```

There's no `UniqueConstraint` or validation preventing multiple active semesters. If two exist, `.first()` picks one non-deterministically (by ordering). Different parts of the system could pick different semesters, causing:
- Grades stored under the wrong semester
- Schedule visibility issues
- PIT event configs not found

**Fix:** Add a constraint:
```python
class Meta:
    constraints = [
        models.UniqueConstraint(
            fields=['is_active'],
            condition=Q(is_active=True),
            name='unique_active_semester',
        ),
    ]
```

**Status:** `[x] Fixed — UniqueConstraint on is_active=True is present and migrations are up to date`

---

## 🟢 Low Findings

### 12. `sync_missing_grade_rows` creates rows on every navigation

`GradeCenterListView.get()` in some code paths triggers `sync_missing_grade_rows` which creates `TeamGrade` rows, creates `StageGradingConfig` records, and runs repair logic. This is O(teams × stages) on every page load.

**Fix:** Move sync to explicit admin action (the `GradeCenterSyncView` already exists for this). Don't auto-sync on GET.

**Status:** `[x] Fixed — removed sync_missing_grade_rows auto-trigger from adviser_capstone_grades_for_user (which was called by AdviserGradeListView on every load)`


---

### 13. WebSocket realtime only for `student` role

**File:** `frontend/lib/services/realtime_sync_service.dart:38-41`

```dart
void connect({required String? role}) {
    if (role != 'student') {
        _disconnect();
        return;
    }
```

Faculty/admin/panelist roles don't get WebSocket updates. If a panelist submits a grade, the admin Grade Center won't reflect it until the page is manually refreshed.

**Fix:** Extend WebSocket support to include `admin` and `faculty` roles, or add a polling fallback for those roles.

**Status:** `[x] Fixed — allowed all authenticated roles (role != null) to connect to WebSocket sync`

---

## Recommended Priority

| Priority | Findings | Why |
|----------|----------|-----|
| **Before next defense event** | #2 (published overwrite), #3 (status transitions), #4 (editable guard) | These can corrupt finalized grades during an active event |
| **This week** | #1 (fake scores), #5 (cascade delete), #11 (active semester) | Data integrity and one-off disasters |
| **Next sprint** | #6, #7, #8, #9, #10 | Edge cases that cause confusion but not data loss |
| **Backlog** | #12, #13 | UX/performance improvements |

---

## Update Log

_Track fixes here as they are applied._
