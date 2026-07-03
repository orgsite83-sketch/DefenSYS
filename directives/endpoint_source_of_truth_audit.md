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

---

## 🔴 CRITICAL — Multiple Mutation Paths (Data Corruption Risk)

### 1. Grade Score Writes from Multiple Endpoints (Panel Scores)

**Problem**: Panel grades for a team can be submitted through THREE different endpoints, all ultimately writing to the same `TeamGrade.panel_score` and `GradeBreakdown` rows:

| # | Endpoint | View | Module |
|---|----------|------|--------|
| 1 | `POST /api/grading/grades/<id>/` (PATCH) | `GradeCenterDetailView.patch` | [views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/views.py#L192-L219) |
| 2 | `POST /api/defense/schedules/submit-grades/` | `PanelistGradeSubmissionView.post` | [scheduler/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L533-L742) |
| 3 | `POST /api/defense/schedules/guest-submit-grades/` | `GuestPanelistGradeSubmissionView.post` | [scheduler/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L849-L1036) |

**Why it's dangerous**:
- **Endpoint 1** (`GradeCenterDetailView.patch`) performs a raw `TeamGradeUpdateSerializer.save()` which writes `panel_score` directly — it **does NOT** call `recompute_panel_score()`. The admin can manually set `panel_score=85` while the underlying `GradeBreakdown`/`PanelistGradeSubmission` rows still reflect the real per-panelist averages.
- **Endpoints 2 & 3** both call `submit_panelist_grade()` → `recompute_panel_score()` which recalculates from breakdown/submission data.
- If an admin manually edits via Endpoint 1, then a panelist submits via Endpoint 2, the `recompute_panel_score()` will **overwrite** the admin's manual value with the computed average — silently dropping the admin's override.
- **No audit trail** distinguishes whether `panel_score` was set by manual override or by computation.

**Data that can be corrupted**: `TeamGrade.panel_score`, `TeamGrade.final_grade`.

---

### 2. Schedule Status Modified from Two Independent Endpoints

**Problem**: `DefenseSchedule.status` can be changed from two separate endpoints with **different validation logic and different audit trails**:

| # | Endpoint | View | Audit |
|---|----------|------|-------|
| 1 | `PATCH /api/defense/schedules/<id>/` | `DefenseScheduleDetailView.patch` | ✅ `log_high_impact_action` with `schedule.status_change` |
| 2 | `PATCH /api/defense/board/<id>/` | `DefenseBoardDetailView.patch` | ❌ No audit log for status changes |

**Why it's dangerous**:
- Both endpoints use different serializers (`DefenseSchedulePatchSerializer` vs `DefenseScheduleStatusSerializer`) to validate status transitions. If the transition rules differ between these serializers, a user could make a transition via the Board endpoint that the Scheduler endpoint would reject.
- Schedule status changes via the Board endpoint are **not audited** — silent changes to defense schedules.

**Additionally**: The `GradeContextService.publish()` and `GradeContextService.finalize_for_archive()` methods in [services.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L1172-L1187) also directly mutate `schedule.status` to `STATUS_DONE`, creating a **third** mutation path for schedule status with no schedule-level audit log.

**Data that can be corrupted**: `DefenseSchedule.status` — three sources can set it with different validation rules.

---

### 3. Team Status Modified via Grade Publish AND Direct Team Edit

**Problem**: `StudentTeam.status` is set in two places:

| # | Mutation path | Location |
|---|--------------|----------|
| 1 | Grade publish/finalize | [_apply_team_result_from_grade](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L1600-L1612) sets `team.status` to `STATUS_APPROVED` or `STATUS_FAILED` |
| 2 | Direct team PATCH | `StudentTeamDetailView.patch` can update team `status` directly |

**Why it's dangerous**: An admin could publish a grade (setting team status to "Approved"), then another user or process edits the team directly back to "Active", while the published grade still says "Approved". The team status and grade status become permanently out of sync.

---

### 4. `adviser_score` Written from Two Different Modules

**Problem**: `TeamGrade.adviser_score` can be written from:

| # | Endpoint | View | Validation |
|---|----------|------|------------|
| 1 | `POST /api/grading/grades/adviser-grades/<id>/submit/` | `AdviserSubmitGradeView.post` | Checks `LOCKED_STATUSES`, `require_grade_editable`, `require_matching_rubric`, adviser grading enabled flag |
| 2 | `PATCH /api/grading/grades/<id>/` | `GradeCenterDetailView.patch` | Only checks `require_grade_editable` via `TeamGradeUpdateSerializer` |

**Why it's dangerous**: 
- The admin PATCH endpoint (2) can write `adviser_score` **even when `capstone_adviser_grading_enabled` is false** and **without rubric validation**.
- If an admin sets `adviser_score` manually, then the adviser submits through endpoint 1, the adviser's validated score overwrites via `grade.save()` — but the breakdown data is now from the adviser while the raw score may have been from the admin. No conflict resolution exists.

---

## 🟠 HIGH — Duplicated Logic That Can Silently Diverge

### 5. Seven Independent `active_semester()` Functions

**Problem**: The concept of "get the active semester" is implemented as **7 separate function definitions** across the codebase, plus multiple inline `Semester.objects.filter(is_active=True).first()` calls:

| # | Location | Implementation |
|---|----------|----------------|
| 1 | [grading/grades/services.py:59](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L59) | `Semester.objects.select_related('school_year').filter(is_active=True).first()` |
| 2 | [student_teams/term_scope.py:24](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/term_scope.py#L24) | `Semester.objects.select_related('school_year').filter(is_active=True).first()` |
| 3 | [student_teams/views.py:79](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/views.py#L79) | Wraps `get_active_semester()` from term_scope |
| 4 | [defense/scheduler/serializers.py:46](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/serializers.py#L46) | Own copy |
| 5 | [grading/rubrics/views.py:89](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/views.py#L89) | Own copy |
| 6 | [academic_period_management/views.py:21](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/academic_period_management/views.py#L21) | Own copy |
| 7 | [repository/deliverables/services.py:118](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/deliverables/services.py#L118) | Own copy |
| 8 | [user_management/academic_records/rollover.py:14](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/academic_records/rollover.py#L14) | Own copy |

**Additionally**, these inline queries skip the helper entirely:
- [reports/views.py:82, 132, 183](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/reports/views.py#L82) — `Semester.objects.filter(is_active=True).first()` (no `select_related`)
- [defense/scheduler/views.py:629, 933](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L629) — `team.semester or Semester.objects.filter(is_active=True).first()`
- [dashboards/views.py:841](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L841) — `Semester.objects.filter(is_active=True).first()`

**Why it's dangerous**: 
- If the model or query logic changes (e.g., adding `is_archived` flag, multi-tenant support), not all copies will be updated.
- The `select_related('school_year')` prefetch is missing in some copies (reports, dashboards), causing inconsistent performance and potential N+1 queries.
- The inline `team.semester or Semester.objects.filter(...)` pattern in scheduler views (lines 629, 933) is a **fallback** that can pick a different semester than what the team is scoped to, potentially creating a `TeamGrade` row with a semester that doesn't match the team's semester.

---

### 6. Duplicate `counts_payload()` Functions in `academic_records/views.py`

**Problem**: The file [academic_records/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/academic_records/views.py) defines `counts_payload()` **twice** — at line 46 and line 165. Both are identical.

**Why it's dangerous**: If only one copy is updated during a refactor, the two views using different copies will return different count structures to the frontend.

---

### 7. Duplicated Permission Classes (`CanManage*`)

**Problem**: The same "admin or PIT lead" permission check is implemented as **4 separate classes** with the same logic:

| Class | File |
|-------|------|
| `CanManageSchedules` | [scheduler/views.py:46](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L46-L59) |
| `CanManageGradeCenter` | [grades/views.py:33](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/views.py#L33-L46) |
| `CanManageBoard` | [board/views.py:18](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L18-L31) |
| `CanManageRubrics` | [rubrics/views.py:16](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/views.py#L16) |

All check: `user.role == 'admin' or user.is_superuser or user.is_pit_lead`.

**Why it's dangerous**: If the permission model changes (e.g., a new "department head" role), one class might be updated while the others remain unchanged, creating an access-control gap.

---

### 8. Default Grade Weights Defined in Two Places

**Problem**: The default grade weight distribution (capstone: 50/30/20, PIT: 80/20) is defined independently in:

| # | Location | Values |
|---|----------|--------|
| 1 | [grading/grades/services.py:63-66](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L63-L66) | `{'panel_weight': 50, 'adviser_weight': 30, 'peer_weight': 20}` / `{'panel_weight': 80, 'peer_weight': 20, 'adviser_weight': 0}` |
| 2 | [grading/rubrics/views.py:121-124](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/rubrics/views.py#L121-L124) | `{'panel': 50, 'adviser': 30, 'peer': 20}` / `{'panel': 80, 'peer': 20}` |

**Why it's dangerous**: The rubric view returns these as display-only metadata to the frontend. If someone changes the actual computation defaults in `services.py` but forgets the rubric view, the frontend will display wrong weights to users.

---

### 9. `_student_visible_grade()` Uses Independent Grade Lookup

**Problem**: The student dashboard in [dashboards/views.py:572-594](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L572-L594) builds its grade display with a standalone `_student_visible_grade()` function that queries `TeamGrade` independently, bypassing the canonical resolution paths used everywhere else (`resolve_canonical_capstone_grade`, `GradeContextService`, `grade_records_for`).

```python
# Dashboard code — does NOT use canonical_capstone_grade_for_team
def _student_visible_grade(team, schedule):
    if schedule is not None:
        return TeamGrade.objects.filter(..., status=TeamGrade.STATUS_PUBLISHED).first()
    return TeamGrade.objects.filter(team=team, status=TeamGrade.STATUS_PUBLISHED).first()
```

**Why it's dangerous**: This function:
- Only shows `STATUS_PUBLISHED` grades — if a grade is `PENDING`, the student sees **no grade at all**, even though the data exists.
- Does **not** filter by scope (capstone vs PIT), so it could return a PIT grade for a capstone team if the PIT grade was published more recently.
- Does **not** use `without_stale_unscheduled_placeholders()`, so it could return a stale placeholder.
- Meanwhile, line 851-859 of the **same view** uses `canonical_capstone_grade_for_team()` for peer evaluation context — so the same response can show grade data from one source and peer eval data from a completely different grade record.

---

## 🟡 MEDIUM — Inconsistent Patterns

### 10. Semester Fallback in Grade Submission (`team.semester or active_semester()`)

**Problem**: In [PanelistGradeSubmissionView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L629) and [GuestPanelistGradeSubmissionView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L933):

```python
semester = team.semester or Semester.objects.filter(is_active=True).first()
```

This fallback is used to determine `semester` but **is never used** downstream in the grade creation path — `GradeContextService.get_for_panel_submission(schedule)` derives semester from the schedule, not the local variable. The variable `semester` is only used for the "no active semester" error check.

**Why it's risky**: If the logic is refactored to pass `semester` into the grade service, this fallback could cause grades to be created on the wrong semester.

---

### 11. Board View Bypasses Scope Filtering for Schedule Deletion

**Problem**: [DefenseBoardDetailView.delete](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L148-L165) checks `schedule.panelist_grade_submissions.exists()` before deletion but returns a 409 Conflict warning instead of actually blocking. The user sees a warning about grade data loss but the endpoint does NOT prevent the deletion if called a second time (since the response is 409, not 403).

However, the [DefenseScheduleDetailView.delete](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L334-L350) in the scheduler module **does not check** for existing grade submissions at all — it just deletes.

**Why it's risky**: Two endpoints for the same delete operation, with different safety checks. The scheduler endpoint is more dangerous.

---

### 12. Report Filter Logic Diverges from Source List Views

**Problem**: The search filter in [SemesterGradesReportView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/reports/views.py#L99-L104) uses a subset of the search fields vs the [GradeCenterListView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/views.py#L64-L75):

| Filter Field | Grade Center List | Semester Grades Report |
|-------------|-------------------|----------------------|
| `team__name` | ✅ | ✅ |
| `team__project_title` | ✅ | ✅ |
| `stage_label` | ✅ | ✅ |
| `team__adviser__*` | ✅ | ❌ |
| `schedule__panel_assignments__panelist__*` | ✅ | ❌ |

Users could get different result sets when exporting vs viewing, leading to confusion about data integrity.

Similarly, [DefenseScheduleReportView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/reports/views.py#L149-L155) lacks the `defense_stage__label` and panelist search fields present in the scheduler list view's [filter_schedules](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L107-L117).

---

### 13. Grade Weights Fallback Chain Has 4 Levels

**Problem**: The `weights_for_schedule()` function at [services.py:626-652](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L626-L652) has a complex fallback chain:

1. If capstone + defense_stage → `weights_for_capstone_stage()`
2. If PIT → `get_pit_event_config()` → config weights, else `weights_for_pit_event()`
3. If rubric exists → rubric weights
4. Else → `default_weights()`

Each level can return different weights for the same schedule. If a PIT event config is created **after** a grade was already created with rubric weights, the grade's weights won't retroactively update unless a sync is manually triggered.

---

### 14. `peer_grading_allowed_for_grade()` vs Dashboard Peer Eval Flag

**Problem**: Two separate sources determine if peer evaluation is enabled:

| Source | Logic |
|--------|-------|
| [peer_grading_allowed_for_grade](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/services.py#L2143-L2147) | PIT: checks `group_settings_for_grade().peer_grading_enabled`; Capstone: checks `semester.capstone_peer_evaluation_enabled` |
| [StudentDashboardView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L861) | Calls `peer_grading_allowed_for_grade()` ✅ (correctly delegates) |

This is actually correctly delegated — noting for completeness that the **dashboard** correctly uses the canonical function. However, the `StudentPeerEvaluationSubmitView` in [peer_views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/grading/grades/peer_views.py) delegates to `submit_student_peer_evaluation()` which contains its **own** peer-enabled check inside `peer_eval.py`. If those two paths diverge, the dashboard could show "peer eval enabled" while the submit endpoint rejects.

---

## 🔵 LOW — Style / Maintenance Inconsistencies

### 15. `academic_records/views.py` Has Duplicate Function Blocks

**Problem**: The file [academic_records/views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/academic_records/views.py) defines `options_payload()` and `counts_payload()` twice at lines 31–52 and again at lines 148–171. The blocks are identical. This appears to be a copy-paste artifact from when the view was refactored.

**Impact**: Low — both are identical today, but divergence risk during future edits.

---

### 16. Inconsistent Error Response Shapes

**Problem**: Error responses across endpoints use different payload shapes:

| Pattern | Used In |
|---------|---------|
| `{'detail': 'message'}` | Most endpoints |
| `{'error': 'message'}` | [scheduler/views.py:632-633](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L632-L633), [scheduler/views.py:740-741](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L740-L741) |
| `{'warning': 'message'}` | [board/views.py:155-160](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/board/views.py#L155-L160) |
| Exception `message_dict` (flat) | Several views |

**Impact**: Frontend must handle multiple error shapes, making global error handling fragile.

---

### 17. Dashboard `_active_semester_label()` vs `active_semester()` 

**Problem**: The dashboard uses `_active_semester_label()` at [dashboards/views.py:137-139](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/dashboards/views.py#L137-L139) which returns a display string, while most other code uses `active_semester()` which returns a model object. The dashboard also separately queries `Semester.objects.filter(is_active=True).first()` at line 841.

**Impact**: Low — no data corruption, but 3 separate semester queries in one dashboard response.

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

**Total: 113 endpoints across 13 modules.**

---

## Recommended Fixes (Priority Order)

### P0 — Fix Immediately

1. **Item #1 (Panel Score)**: Add an `is_manual_override` flag to `TeamGrade` or make `GradeCenterDetailView.patch` call `recompute_panel_score()` when `panel_score` changes, so manual edits aren't silently overwritten.

2. **Item #2 (Schedule Status)**: Add audit logging to `DefenseBoardDetailView.patch`. Unify the status transition serializer or have both endpoints delegate to a single `transition_schedule_status()` service function.

3. **Item #4 (Adviser Score)**: Make `GradeCenterDetailView.patch` respect the `capstone_adviser_grading_enabled` flag, or at minimum log a warning when an admin overrides a disabled grading type.

### P1 — Fix Soon

4. **Item #5 (active_semester)**: Create a single canonical `active_semester()` in `academic_period_management.services` and import it everywhere. Remove all duplicate definitions.

5. **Item #6 (Duplicate counts_payload)**: Remove the duplicate block in `academic_records/views.py`.

6. **Item #7 (CanManage*)**: Create a single `CanManageModule` permission class in `user_management.permissions` and import it.

7. **Item #9 (Student Dashboard Grade)**: Rewrite `_student_visible_grade()` to use `canonical_capstone_grade_for_team()` for capstone teams and the canonical PIT grade resolver, ensuring the same grade record is used for both display and peer eval context.

### P2 — Fix When Convenient

8. **Items #8, #10, #12, #13, #14**: Consolidate default weights, remove unused semester fallbacks, align report filters with list view filters.

9. **Items #15, #16, #17**: Clean up duplicate code blocks, normalize error response shapes.
