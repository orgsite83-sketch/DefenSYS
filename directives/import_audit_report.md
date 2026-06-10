# DefenSYS Import Pipeline Audit Report

**Date:** 2026-06-09  
**Triggered by:** PIT team CSV import accepting `adviser_id` column and showing row as "Ready"

---

## Executive Summary

DefenSYS has **5 data import pipelines**. After auditing all of them end-to-end (frontend CSV parsing → backend serialization → database write), I found **2 dangerous**, **2 needs-improvement**, and **1 acceptable** flow.

The core systemic issue: **the system silently strips or ignores CSV columns that don't belong to the import context** instead of rejecting them or warning the user. This creates a false sense of safety — data passes validation and shows as "Ready" even when the CSV was prepared for a different program.

---

## 🔴 DANGEROUS — Data Corruption / Silent Data Loss Risk

### 1. Team Bulk Import: PIT Accepts Adviser Column Silently

> [!CAUTION]
> **The bug you found.** This is the highest-severity issue.

**What happens:**
1. User uploads a CSV with headers: `team_name,project_title,year_level,member_ids,leader_id,adviser_id`
2. The CSV has `adviser_id = "Ricardo Fontanilla"` — a valid adviser
3. Backend detects this is a PIT row via [is_pit_bulk_row()](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py#L105-L109)
4. [validate_bulk_team_row()](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py#L150-L161) **silently blanks** the adviser:
   ```python
   if pit_row:
       data = dict(data)
       data['adviser_id'] = ''  # ← Silently erased, no warning issued
       adviser, adviser_status, adviser_name = None, ADVISER_STATUS_NONE, ''
   ```
5. No issue is appended to `issues[]`, so `ready = True`
6. The preview row shows **"Ready"** ✅ with no indication the adviser was dropped
7. If imported: team is created **without the adviser** the user intended

**Root causes:**
- [bulk_import.py L157-161](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py#L157-L161): Silently blanks adviser without adding a warning
- [team_bulk_import_csv.dart L103](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/team_bulk_import_csv.dart#L103): Frontend parser happily reads `adviser_id` regardless of context
- [team_bulk_import_csv.dart L132](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/team_bulk_import_csv.dart#L132): `applyDerivedLevelToRow()` does `row.remove('adviser_id')` for PIT — but only after parsing. The backend preview/validate still receives whatever the frontend sends

**Impact:** User thinks adviser is assigned. Team is created without adviser. No audit trail of the dropped data.

**Fix needed:**
- Backend: When `is_pit_bulk_row` is true and `adviser_id` is non-empty, append a **warning** (not a blocker):
  `"PIT teams do not have advisers. The adviser_id column ('Ricardo Fontanilla') will be ignored."`
- Frontend: When PIT Lead imports CSV with an `adviser_id` header, show a **warning banner** before preview

---

### 2. Team Bulk Import: No CSV Schema Validation (Wrong File → Silent Mangling)

> [!CAUTION]
> There is **no validation** that the uploaded CSV matches the expected schema for the user's role.

**What happens:**
- Admin expects: `team_name,project_title,year_level,member_ids,leader_id,adviser_id`
- PIT Lead expects: `team_name,project_title,member_ids,leader_id`
- But [parseTeamBulkCsv()](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/team_bulk_import_csv.dart#L53-L108) accepts **any** CSV as long as it has `team_name`, `member_ids`, and `leader_id`
- Extra columns are silently absorbed; missing expected columns produce empty strings
- A Capstone CSV uploaded by a PIT Lead: all adviser data silently dropped, year_level potentially misinterpreted
- A PIT CSV uploaded by an Admin: no adviser column → teams created without advisers, no warning

**Root cause:** [parseTeamBulkCsv()](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/team_bulk_import_csv.dart#L63-L78) builds column indices dynamically and only validates 3 required headers. No schema mismatch detection exists anywhere in the stack.

**Impact:** Users can upload the wrong CSV template and get silently corrupted imports.

**Fix needed:**
- Frontend: After parsing headers, compare against expected schema for role. If unexpected columns detected (e.g., `adviser_id` for PIT), show a **"Wrong template?"** warning
- Backend: [BulkTeamRowSerializer](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/serializers.py#L440-L464) should reject or warn on unexpected fields

---

## 🟡 NEEDS IMPROVEMENT — Functional but Lacks Guardrails

### 3. User/Student Bulk Import: Has Review Flow, Minor Gaps Remain

**Endpoint:** [BulkImportUsersView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py#L536-L537) (`/api/users/bulk-import/`)

**What works well (already has a two-step review/confirm flow ✅):**
- [_bulkImportReview()](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart#L1986) shows a full "Review Import" panel with row counts, detected year/section/instructor, and a searchable row table
- [_bulkImportBlockingIssues()](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart#L2507) blocks import when: rows have wrong roles for student-mode, no target semester selected, or no year level configured
- [_bulkImportWarnings()](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart#L2550) warns on: duplicate IDs within file, missing emails, year-level mismatches, mixed sections, missing instructor
- [_preflightReview()](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart#L1805) shows resolved semester, batch year level, and section context before import
- Button label changes to **"Confirm Import"** and is disabled until all blockers are resolved
- [BulkImportUsersMixin](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py#L387-L533) validates each row serializer server-side
- `force_student_only` blocks PIT Leads from creating non-student users
- `force_pit_lead_context` enforces year-level scope
- Draft save/resume functionality with unsaved-changes detection

**What's still missing:**
- [BulkUserRowSerializer](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/serializers.py#L209-L217) has no `year_level` range validation on the backend — accepts `"5th Year"` or `"kindergarten"`
- Users are created with `password = username` (documented in the UI subtitle, but no explicit confirmation dialog)

**Impact:** Low — the existing review flow with blockers + warnings catches most issues before import. Only backend-side validation of year_level values is missing.

---

### 4. Official Class List Import: Robust but Missing Section Mismatch Warning

**Endpoint:** [PitLeadOfficialClassListImportView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py#L546-L712) (`/api/users/pit-lead/official-class-list/import/`)

**What works well:**
- Requires instructor name matching
- Enforces PIT year scope
- Uses `transaction.atomic()` for rollback on error
- Creates/updates academic records properly
- Validates faculty match before proceeding

**What's missing:**
- If individual rows have a `section` different from the metadata section, the row section wins silently ([L619](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/user_management/views.py#L619)). No warning about mixed sections in a single class list
- `get_or_create` on User means if a student ID already exists as faculty, it appends an error — but if it exists as student, it silently updates their name/email without confirmation
- No duplicate detection within the same CSV (two rows with same student ID → first creates, second silently updates)

**Impact:** Low-medium — PIT Lead scope limits damage, but silent name overwriting could cause confusion.

**Fix needed:**
- Warn when CSV contains rows with sections different from the metadata section
- Flag within-CSV duplicate student IDs

---

## 🟢 ACCEPTABLE — Adequate Guardrails in Place

### 5. Defense Schedule Import (Generate Plan → Confirm Plan)

**Endpoints:** [GenerateSchedulePlanView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L239-L250), [ConfirmSchedulePlanView](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/defense/scheduler/views.py#L253-L269)

**What works well:**
- Two-step flow: generate slots → confirm plan
- Frontend parsing in [defense_schedule_import_parser.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/defense_schedule_import_parser.dart) validates headers with [_findHeaderIndex()](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/defense_schedule_import_parser.dart#L267-L281)
- Requires both team AND schedule markers (time/chair/panel) before accepting as valid
- Backend serializers validate team existence, panelist assignments, date/time formats, and rubric assignments
- Uses `CanManageSchedules` permission (admin + PIT lead only)
- Supports Excel and CSV with proper cell type handling

**Minor notes:**
- Fill-down logic for merged cells could theoretically misattribute a panel member if the sheet is malformatted — but this is edge-case and caught at the confirm step

---

## Cross-Cutting Issues

| Issue | Affected Imports | Severity |
|---|---|---|
| **No CSV schema/header validation** | Team import (1, 2) | 🔴 |
| **Silent data stripping without warnings** | Team PIT import (1) | 🔴 |
| **Backend `year_level` not range-validated** | User bulk import (3) | 🟡 |
| **Silent section mismatch in class list** | Class list import (4) | 🟡 |
| **No audit log for import actions** | Team import (1, 2) | 🟡 |

---

## Recommended Fix Priority

1. **🔴 Immediate:** Add adviser-present warning for PIT team import ([bulk_import.py L157-161](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py#L157-L161))
2. **🔴 Immediate:** Add CSV header schema validation in frontend + backend  
3. **🟡 Next sprint:** Add `year_level` domain validation in BulkUserRowSerializer  
4. **🟡 Backlog:** Add import audit logging to SystemAuditLog
