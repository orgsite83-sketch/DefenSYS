# Dead Code, Bug & Dangerous Logic Audit

> **Date:** 2026-06-30  
> **Scope:** Full backend codebase + architecture-level frontend implications  
> **Severity Scale:** 🔴 Critical · 🟠 High · 🟡 Medium · 🔵 Low · ⚪ Info (Dead Code)

---

## Table of Contents

1. [🔴 Critical — Data-Corrupting / Security Issues](#1--critical--data-corrupting--security-issues)
2. [🟠 High — Logic Bugs That Affect Correctness](#2--high--logic-bugs-that-affect-correctness)
3. [🟡 Medium — Dangerous Patterns & Fragile Logic](#3--medium--dangerous-patterns--fragile-logic)
4. [🔵 Low — Code Smells & Minor Issues](#4--low--code-smells--minor-issues)
5. [⚪ Dead Code & Unused Artifacts](#5--dead-code--unused-artifacts)
6. [Summary Matrix](#6-summary-matrix)

---

## 1. 🔴 Critical — Data-Corrupting / Security Issues

### 1.1 🔴 Silent Exception Swallowing in `TeamGrade.save()` — GRADE DATA LOSS

**File:** `modules/grading/grades/models.py` — Lines 210–226

```python
try:
    from .peer_eval import recalculate_student_grade
    memberships = list(self.team.memberships.select_related('student').all())
    for membership in memberships:
        sg, _ = StudentStageGrade.objects.get_or_create(team_grade=self, student=membership.student)
        sg.adviser_score = self.adviser_score
        # ...
        sg.save()
        recalculate_student_grade(sg)
except Exception:
    pass  # ← SILENT SWALLOW
```

**Why this is critical:** Every time a `TeamGrade` is saved, student-level grade propagation can silently fail. A single `IntegrityError`, `ValidationError`, or even a typo in future code changes will result in **team grades and student grades being permanently out of sync** — with zero logging and zero indication. This is a grading system for an academic institution.

**Impact:** Students may receive incorrect final grades. Published grade reports may have wrong scores. No audit trail exists for the failure.

**Fix:** At minimum, log the exception. Ideally, let it propagate or wrap in a controlled error handler with audit logging.

---Done

### 1.2 🔴 CORS Allows All Private Network Origins in DEBUG Mode

**File:** `defensys_backend/cors.py` — Lines 40–44

```python
def _is_local_origin(origin):
    return (origin.startswith('http://localhost') or 
            origin.startswith('http://127.0.0.1') or 
            origin.startswith('http://192.168.') or 
            origin.startswith('http://10.'))
```

**Why this is critical:** Any device on the same local network (e.g., lab workstations, students' laptops on campus Wi-Fi) can make authenticated CORS requests to the API while `DEBUG=True`. Combined with the fact that `DEBUG` defaults to `True`, this means the API is wide open to CSRF-style cross-origin attacks from any `192.168.*` or `10.*` device.

**Impact:** A student could craft a malicious web page that, when opened by a logged-in admin on the same network, executes admin-level API calls (grade publishing, team deletion, etc.).

**Fix:** Restrict CORS in DEBUG mode to `localhost`/`127.0.0.1` only. Require explicit allowlisting for LAN IPs.

---

### 1.3 🔴 `is_uploader` Role Grants Full Admin-Level Data Access

**File:** `modules/authentication_access_control/scopes.py` — Lines 75–76 and 135–136

```python
if getattr(user, 'is_uploader', False):
    return base  # ← Returns ALL teams, unfiltered
```

And again for schedules:

```python
if getattr(user, 'is_uploader', False):
    return base  # ← Returns ALL defense schedules, unfiltered
```

**Why this is critical:** The `is_uploader` flag is meant for document upload functionality, but it grants the **same data visibility as a system admin** — every team, every defense schedule across all years, levels, and semesters. Any faculty with this flag can see all private team data.

**Impact:** Privacy breach. An uploader sees every team's data even when they shouldn't (e.g., PIT teams, teams from different sections).

**Fix:** Scope `is_uploader` visibility to only the teams/schedules relevant to their upload duties.

---Done

### 1.4 🔴 `DELETE /teams/<id>` Warning-Only Guard for Cascading Deletes

**File:** `modules/student_teams/views.py` — Lines 326–339

```python
has_schedules = DefenseSchedule.objects.filter(team=team).exists()
has_grades = TeamGrade.objects.filter(team=team).exists()
if has_schedules or has_grades:
    return Response(
        {'warning': 'This team has defense schedules or grade records...'},
        status=status.HTTP_409_CONFLICT,
    )
```

**Why this is critical:** This guard only warns the frontend — it doesn't block subsequent delete attempts. If the frontend ignores the 409 (or a direct API caller simply retries), the team and all CASCADE-linked records (**TeamMembership**, **WeeklyProgressReport**, **TeamDocument**, **TeamStageProgress**) are deleted. Grade records are orphaned via `SET_NULL`.

There is **no force-delete confirmation** mechanism. A second DELETE call (without the grade/schedule check being re-evaluated differently) will still hit `team.delete()` on line 350.

**Impact:** Accidental or malicious data loss of team memberships, documents, and progress records.

**Fix:** Block the delete entirely if `has_schedules or has_grades`, or require a `force=true` parameter with additional permission checks.

---Done

### 1.5 🔴 `SemesterGradesReportView` References Undefined `Response`

**File:** `modules/reports/views.py` — Lines 83–86

```python
if not semester:
    return Response(
        {"detail": "No active semester is configured."},
        status=status.HTTP_400_BAD_REQUEST
    )
```

**Why this is critical:** `Response` from `rest_framework.response` is not imported in this file — only `HttpResponse` from `django.http` is imported. This will raise a **`NameError: name 'Response' is not defined`** at runtime when no active semester exists. The same bug appears in `DefenseScheduleReportView` (line 133).

**Impact:** Unhandled 500 server error instead of a clean 400 response. Users get a crash page.

**Fix:** Add `from rest_framework.response import Response` at the top of the file, or use `HttpResponse`.

---Done

## 2. 🟠 High — Logic Bugs That Affect Correctness

### 2.1 🟠 `_reject_capstone_bulk_import_if_closed` — Inverted Guard Logic

**File:** `modules/student_teams/views.py` — Lines 388–400

```python
def _reject_capstone_bulk_import_if_closed(user, *, section=''):
    if (section or '').strip():
        return None          # ← Section imports skip capstone check
    if not user_is_admin(user):
        return None          # ← Non-admins skip capstone check too
    # Only admins without a section hit the assertion
```

**Why this is high:** The guard is meant to reject bulk imports when capstone creation is closed, but it **only fires for admins doing non-section imports**. PIT leads doing bulk imports bypass it entirely because `user_is_admin` returns `False` for them, so the check returns `None` (permit). Section-level imports also bypass it.

**Impact:** Capstone teams could be created during closed periods by non-admin users or via section imports.

---Done

### 2.2 🟠 Duplicate `PASS_GRADE_THRESHOLD` Constants

**File:** `modules/grading/grades/services.py` — Line 1610  
**File:** `modules/student_teams/services.py` — Line 9

Both define `PASS_GRADE_THRESHOLD = Decimal('75.00')` independently. If one is changed and the other is not, pass/fail determination will be inconsistent between the grade center and the team stage progression system.

**Impact:** A team could be marked "Passed" in grade center but "Failed" in stage progress, or vice versa.

**Fix:** Define once in a shared constants module and import everywhere.

---Done

### 2.3 🟠 `board_queryset_for_user` — PIT Lead Filtering Uses Raw `pit_lead_year` Without Normalization

**File:** `modules/defense/board/views.py` — Lines 34–42

```python
def board_queryset_for_user(user):
    queryset = schedule_queryset()
    if getattr(user, 'is_pit_lead', False) and getattr(user, 'role', None) != 'admin':
        queryset = queryset.filter(
            ...
            team__year_level=getattr(user, 'pit_lead_year', None),
        )
    return queryset
```

**Why this is high:** `pit_lead_year` is used raw (e.g., `"2nd Year"` or `" 2nd Year "` with spaces). Other scoping functions use `normalize_year_level()` or `_pit_year()` which strip whitespace. If the user model has trailing spaces in `pit_lead_year`, the board filter will return **zero results** even when valid schedules exist.

**Impact:** PIT leads may see an empty defense board, unable to manage any schedules.

---Done

### 2.4 🟠 `admin` Users Cannot Edit Non-Capstone Teams

**File:** `modules/student_teams/term_scope.py` — Lines 75–76

```python
if user_is_admin(user):
    return 'Capstone' in (team.level or '')
```

**Why this is high:** `team_is_editable` returns `False` for admins viewing PIT teams. An admin trying to edit a PIT team will get a "You do not have permission" error. This means **admins cannot edit PIT teams** — they are locked to capstone-only editing.

**Impact:** System administrators are unexpectedly locked out of PIT team management unless they go through Django admin.

---Done

### 2.5 🟠 `audit_logs_for` — PIT Lead Audit Filtering is AND-combined, May Return Nothing

**File:** `modules/authentication_access_control/scopes.py` — Lines 232–248

```python
return base.filter(pit_marker, year_marker)
```

**Why this is high:** Both `pit_marker` and `year_marker` are Q expressions joined with AND. An audit log must match **both** the PIT scope marker AND the year level marker. However, many system-generated audit entries (e.g., grade center operations) may include `scope=pit` but not `year_level` in the JSON. These would be invisible to PIT leads.

**Impact:** PIT leads may miss important audit entries that don't have year-level metadata embedded in the JSON.

---Done

### 2.6 🟠 `_build_peer_scores_for_complete_grade` — Returns `None` Tuple vs `None`

**File:** `modules/grading/grades/peer_eval.py` — Lines 135–159

```python
def _build_peer_scores_for_complete_grade(grade, memberships):
    ...
    for membership in memberships:
        ...
        if not averages:
            return None  # ← Returns None (not a tuple)
    ...
    return peer_scores, normalized_total  # ← Returns a tuple
```

**Why this is high:** If any single evaluatee has zero evaluations, the function returns `None` early. The caller on line 187 does:

```python
built = _build_peer_scores_for_complete_grade(grade, memberships)
if built is None:
    ...
``` 

This works, but it means **one missing peer evaluation for one student wipes all peer scores for the entire team**, even if 4 out of 5 students have complete evaluations. The early return prevents partial scoring.

**Impact:** Peer scores become all-or-nothing. Partial peer evaluation progress is silently discarded.

--- Done

## 3. 🟡 Medium — Dangerous Patterns & Fragile Logic

### 3.1 🟡 Full User Table Scan in `_users_matching_full_name`

**File:** `modules/student_teams/bulk_import.py` — Lines 25–38

```python
def _users_matching_full_name(value, *, role=None):
    ...
    for user in queryset:  # ← Iterates ALL users
        if normalize_name(display_name(user)) == normalized:
            matches.append(user)
    return matches
```

**Why this is medium:** Iterates every user in the database to match by display name. With hundreds of students and faculty, this is O(N) per lookup. Bulk imports call this once per member per row — potentially thousands of iterations for a large CSV.

**Impact:** Bulk import could take minutes and potentially timeout or OOM on large rosters.

**Fix:** Use database-level name matching with `annotate(full_name=Concat(...))` and `filter()`.

---Done

### 3.2 🟡 `resolve_adviser_by_name` Also Scans All Faculty

**File:** `modules/student_teams/bulk_import.py` — Lines 72–102

Same pattern as above — iterates all `faculty`/`admin` users in Python to match names. Compounded during bulk imports.

---Done

### 3.3 🟡 `TeamGrade.save()` Calls `full_clean()` on Every Save

**File:** `modules/grading/grades/models.py` — Lines 196–208

```python
def save(self, *args, **kwargs):
    ...
    self.recalculate(keep_published=True)
    self.full_clean()
    super().save(*args, **kwargs)
```

**Why this is medium:** `full_clean()` re-validates every time the model is saved, including during batch operations. The `clean()` method checks weight totals and completeness — both of which may be temporarily invalid during multi-step grade construction. The `except Exception: pass` block after `super().save()` exists partly because `full_clean()` may raise for intermediate states.

**Impact:** Can cause unexpected `ValidationError` during legitimate multi-step operations. Also has performance implications during sync operations.

---Done

### 3.4 🟡 `LogoutView` Uses `AllowAny` Permission

**File:** `modules/authentication_access_control/views.py` — Lines 46–47

```python
class LogoutView(TokenBlacklistView):
    permission_classes = [AllowAny]
```

**Why this is medium:** An unauthenticated user can POST arbitrary tokens to the blacklist endpoint. While `TokenBlacklistView` validates the token before blacklisting, this still allows brute-force token blacklist attempts.

**Impact:** An attacker could potentially blacklist valid refresh tokens by guessing token payloads.

---Done

### 3.5 🟡 Media File Path Traversal — Incomplete Sanitization

**File:** `defensys_backend/media_views.py` — Lines 20–23

```python
resolved = os.path.normpath(file_path)
drive, path = os.path.splitdrive(resolved)
if drive or os.path.isabs(resolved) or '..' in resolved or resolved.startswith('/') or resolved.startswith('\\'):
    raise Http404('Invalid file path.')
```

**Why this is medium:** The check is on `resolved` (after `normpath`), but `file_path` is what's passed to `default_storage.exists()` and `default_storage.open()` on lines 25 and 28. If `normpath` collapses `../` but the storage backend interprets the original path differently, there could be a bypass.

Additionally, the check `'..' in resolved` after `normpath` is redundant on most platforms (normpath resolves `..`), but the mismatch between the validated path and the used path is the real concern.

**Fix:** Use `resolved` consistently for both validation and file operations.

---Done

### 3.6 🟡 `GuestPanelistPrincipal` Has No Django Permission Backend Support

**File:** `modules/authentication_access_control/guest_authentication.py` — Lines 8–29

The `GuestPanelistPrincipal` class sets `is_authenticated = True` but doesn't implement `has_perm`, `has_module_perms`, or other methods expected by Django's permission framework. If any code calls `request.user.has_perm(...)` on a guest request, it will raise `AttributeError`.

**Impact:** Any future code that adds standard Django permission checks will crash for guest panelists.

---Done

---

### 3.7 🟡 `_context_for_team` Falls Back to `'Unscheduled'` Creating Orphan Grades

**File:** `modules/grading/grades/services.py` — Lines 706–707

```python
def _context_for_team(team):
    return team.current_defense_stage or team.ready_for_stage or 'Unscheduled'
```

**Why this is medium:** Teams without a defense stage get `'Unscheduled'` as their `stage_label`. This creates "placeholder" grade records that then require complex cleanup logic (`_cleanup_stale_capstone_grades_for_team`, `_merge_stale_grade`, etc. — over 200 lines of code). The placeholders frequently become stale and need garbage collection.

**Impact:** Grade records accumulate as orphaned "Unscheduled" entries, complicating queries and potentially confusing users.

---Done

### 3.8 🟡 `StageCompletionService.complete_group` — Identical Branches

**File:** `modules/grading/grades/services.py` — Lines 2002–2005

```python
if scope == TeamGrade.SCOPE_PIT:
    auto_result = _auto_finalize_passed_grades_in_queryset(grades, user=user)
else:
    auto_result = _auto_finalize_passed_grades_in_queryset(grades, user=user)
```

The `if/else` branches are identical, making the conditional dead code. This suggests either a copy-paste error or an incomplete implementation where the two scopes should have different behaviors.

---

### 3.9 🟡 Notification System — No Pagination on List Endpoint

**File:** `modules/notifications/views.py` — Lines 13–20

```python
def get(self, request):
    notifications = Notification.objects.filter(recipient=request.user)
    serializer = NotificationSerializer(notifications, many=True)
```

All notifications for a user are returned in a single response with no pagination. For active users, this could grow to hundreds or thousands of records.

**Impact:** API response size grows unbounded. Slow responses, mobile app memory issues.

---Done


## 4. 🔵 Low — Code Smells & Minor Issues

### 4.1 🔵 `active_semester()` Called Multiple Times Per Request

`options_payload()` in `modules/student_teams/views.py` calls `active_semester()` twice (lines 116 and 173). Each call hits the database.

**Fix:** Call once and pass the result.

---Done

### 4.2 🔵 `db.sqlite3` in Backend Directory

**File:** `backend/db.sqlite3` (483 KB)

An SQLite database file exists in the backend directory despite PostgreSQL being the configured database. This is likely a leftover from initial Django setup and should be removed.

---Done

### 4.3 🔵 `test_minutes_output.pdf` Committed to Repository

**File:** `backend/test_minutes_output.pdf` (3 KB)

A test output PDF file exists in the backend root directory. Should be gitignored.

---Done

### 4.4 🔵 Bottom-of-File Imports in Models

**File:** `modules/student_teams/models.py` — Lines 280–281

```python
from student_teams.documents.models import TeamDocument  # noqa: E402,F401
from student_teams.weekly_progress.models import WeeklyProgressReport  # noqa: E402,F401
```

Circular import workaround at the bottom of the file. While functional, this is fragile and breaks IDE tooling.

---Done

### 4.5 🔵 `resolve_adviser_username` Alias Is Misleading

**File:** `modules/student_teams/bulk_import.py` — Line 432

```python
resolve_adviser_username = resolve_adviser_by_name
```

The alias name says "username" but the function resolves by "name". This is confusing for maintainers.

---Done

### 4.6 🔵 `adviser_phase` Field on User Model — Never Used

**File:** `modules/authentication_access_control/models.py` — Line 29

```python
adviser_phase = models.CharField(max_length=50, blank=True, null=True)
```

This field is defined on the User model but is never referenced in any view, serializer, or service. It's also not exposed in `UserSerializer`.

---Done

---

### 4.7 🔵 `team_id` Field on User Model — Stale Denormalization

**File:** `modules/authentication_access_control/models.py` — Line 22

```python
team_id = models.CharField(max_length=100, blank=True, null=True)
```

This `CharField` on the User model stores a team reference, but team membership is properly managed through the `TeamMembership` model. Only one place in the codebase writes to it (line 361 in `views.py` during team deletion). This stale denormalization can get out of sync.

---

### 4.8 🔵 `stage_options()` Iterates Instead of Using DB Query

**File:** `modules/defense/board/views.py` — Lines 57–62

```python
def stage_options(queryset):
    labels = set()
    for item in queryset:
        if item.stage_label:
            labels.add(item.stage_label)
    return sorted(labels)
```

This materializes the entire queryset into Python to extract unique labels. Could be `queryset.values_list('stage_label', flat=True).distinct()`.

---

## 5. ⚪ Dead Code & Unused Artifacts

### 5.1 ⚪ `teams_queryset()` — Shadow Function, Never Called Meaningfully

**File:** `modules/student_teams/views.py` — Lines 63–67

```python
def teams_queryset():
    return (
        StudentTeam.objects.select_related(...)
        .prefetch_related(...)
    )
```

This duplicates the logic in `visible_teams_for()` from `scopes.py`. The main list view uses `teams_queryset_for_user()` (which calls `visible_teams_for`), and `teams_queryset()` is only used for re-fetching after writes or counts — but the counts should use the scoped queryset for consistency.

---

### 5.2 ⚪ `grade_queryset()` Duplicated in Services

**File:** `modules/grading/grades/services.py` — Lines 654–681

The `grade_queryset()` function defines the same `select_related`/`prefetch_related` chain as `grade_records_for()` in `scopes.py`. Both exist and are called in different contexts, leading to potential drift.

---Done

---

### 5.3 ⚪ `_format_serializer_errors` — Internal Helper Duplicates `format_bulk_import_errors`

**File:** `modules/student_teams/bulk_import.py` — Lines 409–410

```python
def _format_serializer_errors(errors):
    return '; '.join(format_bulk_import_errors(errors))
```

Only called once in `preview_bulk_teams`. Could be inlined.

---Done

---

### 5.4 ⚪ `incomplete_peer_teams_for_group` — Backward-Compatible Alias

**File:** `modules/grading/grades/services.py` — Line 1810

```python
incomplete_peer_teams_for_group = incomplete_grading_teams_for_group
```

This alias exists for backward compatibility but has no callers in the codebase. If no external consumers exist, it should be removed.

---Done

### 5.5 ⚪ `maybe_auto_publish_passed_grade` — Alias

**File:** `modules/grading/grades/services.py` — Line 1922

```python
maybe_auto_publish_passed_grade = maybe_auto_finalize_passed_grade
```

Same pattern — rename alias with no callers.

---Done


### 5.6 ⚪ `finalize_passed_pit_grade_for_archive` — Alias

**File:** `modules/grading/grades/services.py` — Line 1646

```python
finalize_passed_pit_grade_for_archive = finalize_passed_grade_for_archive
```

Another backward-compatibility alias with no callers.

---Done

### 5.7 ⚪ `User.team_id` CharField Cleanup Not Enforced

The only write to `User.team_id` is in `StudentTeamDetailView.delete()` (line 361), where it clears the field for deleted team members. But `User.team_id` is never set during team creation or membership changes — so it's stale data from a previous schema design.

---Done

### 5.8 ⚪ `peer_completion_counts_for_group` Wraps `grading_readiness_counts_for_group`

**File:** `modules/grading/grades/services.py` — Lines 1840–1841

```python
def peer_completion_counts_for_group(semester, scope, stage_label, *, config=None):
    return grading_readiness_counts_for_group(semester, scope, stage_label, config=config)
```

Pure passthrough with no additional logic. Dead wrapper.

---Done

## 6. Summary Matrix

| # | Severity | Category | Module | Brief Description |
|---|----------|----------|--------|-------------------|
| 1.1 | 🔴 Critical | Bug | `grading/grades/models.py` | Silent `except: pass` in `TeamGrade.save()` — grade propagation fails silently |
| 1.2 | 🔴 Critical | Security | `defensys_backend/cors.py` | CORS allows all private network origins in DEBUG mode |
| 1.3 | 🔴 Critical | Security | `auth/scopes.py` | `is_uploader` grants admin-level data visibility |
| 1.4 | 🔴 Critical | Bug | `student_teams/views.py` | Team deletion guard is warning-only; cascade deletes possible |
| 1.5 | 🔴 Critical | Bug | `reports/views.py` | `NameError: Response` — undefined import causes 500 error |
| 2.1 | 🟠 High | Logic | `student_teams/views.py` | Capstone closed-period guard skipped for non-admins |
| 2.2 | 🟠 High | Logic | Multiple files | Duplicate `PASS_GRADE_THRESHOLD` constants |
| 2.3 | 🟠 High | Bug | `defense/board/views.py` | PIT lead year filtering lacks normalization |
| 2.4 | 🟠 High | Logic | `student_teams/term_scope.py` | Admins cannot edit PIT teams |
| 2.5 | 🟠 High | Logic | `auth/scopes.py` | PIT lead audit logs may filter out valid entries |
| 2.6 | 🟠 High | Logic | `grading/grades/peer_eval.py` | One missing peer eval wipes all peer scores for team |
| 3.1 | 🟡 Medium | Perf | `student_teams/bulk_import.py` | Full user table scan for name matching |
| 3.2 | 🟡 Medium | Perf | `student_teams/bulk_import.py` | Full faculty scan for adviser resolution |
| 3.3 | 🟡 Medium | Logic | `grading/grades/models.py` | `full_clean()` on every save causes validation during batch ops |
| 3.4 | 🟡 Medium | Security | `auth/views.py` | `LogoutView` uses `AllowAny` — unauthenticated blacklist attempts |
| 3.5 | 🟡 Medium | Security | `media_views.py` | Path traversal check uses different variable than file open |
| 3.6 | 🟡 Medium | Bug | `auth/guest_authentication.py` | `GuestPanelistPrincipal` missing Django permission methods |
| 3.7 | 🟡 Medium | Logic | `grading/grades/services.py` | `'Unscheduled'` placeholder grades accumulate as orphans |
| 3.8 | 🟡 Medium | Dead Code | `grading/grades/services.py` | Identical if/else branches in `complete_group` |
| 3.9 | 🟡 Medium | Perf | `notifications/views.py` | No pagination on notification list endpoint |
| 4.1 | 🔵 Low | Perf | `student_teams/views.py` | `active_semester()` called twice per request |
| 4.2 | 🔵 Low | Cleanup | `backend/` | `db.sqlite3` leftover file |
| 4.3 | 🔵 Low | Cleanup | `backend/` | `test_minutes_output.pdf` in repo |
| 4.4 | 🔵 Low | Smell | `student_teams/models.py` | Bottom-of-file circular import workaround |
| 4.5 | 🔵 Low | Smell | `student_teams/bulk_import.py` | Misleading alias `resolve_adviser_username` |
| 4.6 | 🔵 Low | Dead Code | `auth/models.py` | `adviser_phase` field never used |
| 4.7 | 🔵 Low | Dead Code | `auth/models.py` | `User.team_id` stale denormalization |
| 4.8 | 🔵 Low | Perf | `defense/board/views.py` | `stage_options()` iterates queryset in Python |
| 5.1 | ⚪ Info | Dead Code | `student_teams/views.py` | `teams_queryset()` shadow function |
| 5.2 | ⚪ Info | Dead Code | `grading/grades/services.py` | `grade_queryset()` duplicated logic |
| 5.3 | ⚪ Info | Dead Code | `student_teams/bulk_import.py` | `_format_serializer_errors` wrapper |
| 5.4 | ⚪ Info | Dead Code | `grading/grades/services.py` | `incomplete_peer_teams_for_group` alias |
| 5.5 | ⚪ Info | Dead Code | `grading/grades/services.py` | `maybe_auto_publish_passed_grade` alias |
| 5.6 | ⚪ Info | Dead Code | `grading/grades/services.py` | `finalize_passed_pit_grade_for_archive` alias |
| 5.7 | ⚪ Info | Dead Code | `auth/models.py` | `User.team_id` never set during normal ops |
| 5.8 | ⚪ Info | Dead Code | `grading/grades/services.py` | `peer_completion_counts_for_group` passthrough |

---

> **Total Findings:** 32  
> **🔴 Critical:** 5 · **🟠 High:** 6 · **🟡 Medium:** 9 · **🔵 Low:** 8 · **⚪ Dead Code:** 8
