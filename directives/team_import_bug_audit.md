# Team Import Bug Audit — Root Cause Analysis

> **Date**: 2026-05-30  
> **Scope**: PIT Lead team import via CSV bulk import and admin team detail display  
> **Reporter**: User observed a 3rd Year PIT team import that landed in 1st Year, and showed "Capstone · 1st Year" as the program label

---

## Summary of Observed Symptoms

1. **Team imported under wrong year level**: User imported a 3rd Year PIT team via CSV, but the PIT Lead's `pit_lead_year` was accidentally set to "1st Year". The team was created as a **1st Year PIT** team.
2. **Team disappears after fixing PIT lead year**: After correcting the PIT Lead's year back to "3rd Year", the team vanished from the 3rd Year PIT view — because it was persisted as "1st Year PIT" in the DB.
3. **Wrong program label on detail page**: The admin team detail page shows **"Capstone · 1st Year"** for what is actually a PIT team — there is no Capstone in 1st Year.

---

## Bug 1: Team Level Derived From PIT Lead's Year, Ignoring CSV Data

### Root Cause

When a PIT Lead imports a team via CSV, the frontend **unconditionally overwrites** the CSV's `year_level` and `level` with the PIT Lead's `pit_lead_year`:

#### Frontend — [team_bulk_import_csv.dart:118-131](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/team_bulk_import_csv.dart#L118-L131)

```dart
void applyDerivedLevelToRow(
  Map<String, dynamic> row, {
  required bool isCapstoneAdmin,
  String? pitLeadYear,
}) {
  if (isCapstoneAdmin) {
    return;  // Admins keep CSV values — correct
  }
  if (pitLeadYear != null && pitLeadYear.isNotEmpty) {
    row['year_level'] = pitLeadYear;        // ← OVERWRITES CSV year_level
    row['level'] = '$pitLeadYear PIT';      // ← OVERWRITES CSV level
    row.remove('adviser_id');
  }
}
```

This function is called on every CSV row in `parseTeamBulkCsvWithContext()`, and again in `_deriveLevelOnRow()` on the student teams screen.

**Impact**: Even if the CSV explicitly says `year_level=3rd Year`, the frontend replaces it with whatever `pit_lead_year` the PIT Lead user currently has. If `pit_lead_year` is accidentally set to "1st Year", **all** imported teams become "1st Year PIT".

#### Backend — [team_levels.py:139-147](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/team_levels.py#L139-L147)

```python
if user_is_pit_lead_only(user):
    if explicit_level and 'CAPSTONE' in explicit_level.upper():
        raise ValueError('PIT Leads can only manage PIT teams.')
    if explicit_level and 'PIT' in explicit_level.upper():
        return explicit_level           # ← Accepts whatever level the frontend sent
    year = year or (getattr(user, 'pit_lead_year', None) or '').strip()
    if not year:
        raise ValueError('year_level or pit_lead_year is required for PIT teams.')
    return f'{year} PIT'
```

The backend **also** falls back to `user.pit_lead_year` when no explicit level is given (line 144). But since the frontend **already** stamps the PIT lead's year into the row, the backend always receives `level="1st Year PIT"` and accepts it without question.

**There is no cross-validation** against the students' actual academic records for PIT teams — the `infer_year_level_from_members()` function is only invoked for admins creating capstone teams.

### Why the team disappears after fixing pit_lead_year

The visibility filter in [scopes.py:45-50](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/authentication_access_control/scopes.py#L45-L50):

```python
if is_pit_lead_only(user):
    queryset = base.filter(level__icontains='PIT')
    pit_year = _pit_year(user)
    if pit_year:
        queryset = queryset.filter(year_level=pit_year)
    return queryset
```

After you change the PIT Lead's year to "3rd Year", the scope filter only shows teams where `year_level="3rd Year"`. The imported team has `year_level="1st Year"`, so it's **invisible** to the PIT Lead. It didn't disappear — it's still in the DB under "1st Year PIT", which is correct from the DB perspective but wrong from the user's intent.

---

## Bug 2: "Capstone · 1st Year" Label on a PIT Team (Detail Page)

### Root Cause

In [team_detail_page.dart:287-289](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/team_detail_page.dart#L287-L289):

```dart
final programLabel = widget.isPitLead
    ? '${widget.pitLeadYear ?? yearLevel} PIT'
    : 'Capstone · $yearLevel';
```

When the **admin** views the team detail page (i.e., `widget.isPitLead == false`), the label is **always** `"Capstone · $yearLevel"`, regardless of whether the team is actually PIT or Capstone. For a "1st Year PIT" team viewed by an admin, this renders as:

> **Program**: Capstone · 1st Year

This is semantically wrong on two counts:
1. The team is PIT, not Capstone
2. There is no "Capstone" program in 1st Year

The same bug exists in the edit view at [team_detail_page.dart:447-449](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/team_detail_page.dart#L447-L449).

---

## Bug 3: No Guardrail Against Invalid Level Combinations

### Root Cause

The model [models.py:7-18](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/models.py#L7-L18) defines valid level choices:

```python
LEVEL_1_PIT = '1st Year PIT'
LEVEL_2_PIT = '2nd Year PIT'
LEVEL_3_PIT = '3rd Year PIT'
LEVEL_3_CAPSTONE = '3rd Year Capstone'
LEVEL_4_CAPSTONE = '4th Year Capstone'
```

Note: There is **no** `1st Year Capstone` or `2nd Year Capstone` in the choices. However:

- The frontend team detail page can display "Capstone · 1st Year" even though this combination doesn't exist
- The `resolve_team_level()` function for admins can construct `f'{year} Capstone'` for any year level, including 1st Year, if the year is inferred from member records

While the Django model's `ChoiceField` constraint should reject invalid levels at the DB level, the **display logic** doesn't validate against the actual level field — it derives the label from `isPitLead` flag alone.

---

## Impact Assessment

| Issue | Severity | Data Affected |
|-------|----------|---------------|
| Team imported under wrong year | **High** | Teams created with wrong `level` and `year_level`. Affects scheduling, grading, defense scoping, and audit trails |
| Team invisible after PIT lead year fix | **High** | Orphaned teams that neither the PIT lead nor admin (via PIT filter) can easily find. Admin can see them via "PIT Teams" filter but they appear under the wrong year |
| Wrong program label | **Medium** | Misleading UI — admin sees "Capstone · 1st Year" for a PIT team, causing confusion about the team's actual program track |

---

## Suggested Fixes

### Fix 1: Validate PIT team year_level against member academic records

**Files to modify**:
- [team_levels.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/team_levels.py) — `prepare_bulk_row()` and `resolve_team_level()`
- [serializers.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/serializers.py) — `StudentTeamWriteSerializer.validate()`

**What to do**:
- For PIT Lead team creation (both manual and bulk), **infer year_level from member academic records** the same way admin capstone teams do
- If members' year levels conflict with the PIT Lead's `pit_lead_year`, surface a validation error: _"Students are enrolled in 3rd Year but your PIT scope is 1st Year"_
- The PIT Lead's `pit_lead_year` should be treated as a **scope filter** (which students you can see), not as an **override** for the team's level

```python
# In resolve_team_level(), for PIT leads:
if user_is_pit_lead_only(user):
    # ... existing capstone guard ...
    if explicit_level and 'PIT' in explicit_level.upper():
        # Validate that the year in the level matches pit_lead_year
        pit_year = (getattr(user, 'pit_lead_year', None) or '').strip()
        level_year_val = level_year(explicit_level)
        if pit_year and level_year_val and level_year_val != pit_year:
            raise ValueError(
                f'Cannot create {explicit_level} team: '
                f'your PIT scope is {pit_year}.'
            )
        return explicit_level
```

### Fix 2: Stop frontend from overwriting CSV year_level blindly

**File to modify**:
- [team_bulk_import_csv.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/team_bulk_import_csv.dart) — `applyDerivedLevelToRow()`

**What to do**:
- Only set `year_level` from `pitLeadYear` if the CSV row doesn't already have a `year_level` value
- Or better: let the backend be the single source of truth for level derivation (don't derive on frontend at all)

```dart
void applyDerivedLevelToRow(
  Map<String, dynamic> row, {
  required bool isCapstoneAdmin,
  String? pitLeadYear,
}) {
  if (isCapstoneAdmin) return;
  if (pitLeadYear != null && pitLeadYear.isNotEmpty) {
    // Only set if the CSV didn't provide a year_level
    final existingYear = (row['year_level'] ?? '').toString().trim();
    if (existingYear.isEmpty) {
      row['year_level'] = pitLeadYear;
      row['level'] = '$pitLeadYear PIT';
    } else {
      row['level'] = '$existingYear PIT';
    }
    row.remove('adviser_id');
  }
}
```

### Fix 3: Fix the program label on team_detail_page.dart

**File to modify**:
- [team_detail_page.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/team_detail_page.dart) — `_buildOverviewView()` and `_buildOverviewEdit()`

**What to do**:
- Use the actual `level` field from the team data instead of deriving it from `isPitLead` flag alone

```dart
// BEFORE (line 287-289):
final programLabel = widget.isPitLead
    ? '${widget.pitLeadYear ?? yearLevel} PIT'
    : 'Capstone · $yearLevel';

// AFTER:
final isPitTeam = level.toUpperCase().contains('PIT');
final programLabel = isPitTeam
    ? '$yearLevel PIT'
    : 'Capstone · $yearLevel';
```

Apply the same fix in `_buildOverviewEdit()` at line 447-449.

### Fix 4 (Bonus): Add a mismatch warning in the admin team list

**File to modify**:
- [student_teams_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart)

**What to do**:
- When displaying PIT teams in the admin "PIT Teams" filter, highlight teams whose `year_level` doesn't match common PIT patterns (e.g., a "1st Year PIT" team where all members are actually 3rd year students)
- This would help admins catch misclassified teams faster

---

## Steps to Reproduce the Current Bug

1. Set a faculty user as PIT Lead with `pit_lead_year = "1st Year"`
2. Log in as that PIT Lead on the faculty portal
3. Go to Student Teams → Bulk Import
4. Upload a CSV with `year_level = "3rd Year"` (or no year_level column — PIT CSV template omits it)
5. The preview will show **"1st Year PIT"** as the program, ignoring the CSV
6. Import the team
7. Now go to Admin → User Management, change the PIT Lead's year to "3rd Year"
8. Log back in as PIT Lead → the team is gone from the team list
9. Log in as Admin → navigate to Student Teams → PIT Teams → the team shows "1st Year" with "Capstone · 1st Year" as program label on the detail page

---

## Files Audited

| File | Path | Key Findings |
|------|------|--------------|
| Team models | [models.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/models.py) | Valid level choices don't include 1st/2nd Year Capstone — correct |
| Team levels | [team_levels.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/team_levels.py) | `resolve_team_level()` trusts frontend-supplied level for PIT leads without validating against member records |
| Bulk import | [bulk_import.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/bulk_import.py) | `is_pit_bulk_row()` correctly detects PIT rows; `prepare_bulk_row()` delegates to `resolve_team_level()` |
| Serializers | [serializers.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/serializers.py) | `StudentTeamWriteSerializer` validates PIT guard for admin but **does not** cross-validate PIT team year against member records |
| Access scopes | [scopes.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/authentication_access_control/scopes.py) | PIT Lead visibility correctly filters by `year_level` — this is working as designed |
| CSV parser (FE) | [team_bulk_import_csv.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/utils/team_bulk_import_csv.dart) | `applyDerivedLevelToRow()` unconditionally overwrites year_level — **primary frontend culprit** |
| Team detail (FE) | [team_detail_page.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/team_detail_page.dart) | Program label uses `isPitLead` flag instead of actual `level` field — **display bug** |
| Teams screen (FE) | [student_teams_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart) | Year level derivation defers to `applyDerivedLevelToRow()` — inherits same bug |
| Teams provider (FE) | [student_teams_provider.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/services/student_teams_provider.dart) | Passes data through correctly — no issues found |
| Team detail provider (FE) | [team_detail_provider.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/services/team_detail_provider.dart) | Passes data through correctly — no issues found |
| Views | [views.py](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/student_teams/views.py) | Bulk import pipeline correctly chains validation but inherits level derivation bug from `team_levels.py` |
