# Capstone & PIT Multi-Year Scope & Logic Audit

## Overview
This document records the comprehensive safety and data-integrity audit of DefenSYS's dual-scope architecture (**Capstone** and **PIT**). It identifies dangerous assumptions, hardcoded year mappings, file resolution hazards, and cross-scope data isolation status across all backend and frontend modules.

---

## Scope Architecture & Boundaries

DefenSYS operates with two distinct project tracks:
1. **Capstone Track**: Academic teams (`level` choices: `"3rd Year Capstone"`, `"4th Year Capstone"`). Driven by `DefenseStage` and `StageGradingConfig`.
2. **PIT Track**: Project Implementation Track teams (`level` choices: `"1st Year PIT"`, `"2nd Year PIT"`, `"3rd Year PIT"`). Driven by `PitEventGradingConfig` and semester-based event names.

---

## Executive Audit Matrix

| Subsystem / Area | Capstone Scope | PIT Scope | Cross-Scope Isolation | Data Integrity Risk |
|---|---|---|---|---|
| **Deliverables API** | Scoped to active `DefenseStage` rows | Scoped to `PitEventGradingConfig` by semester & year level | 🟢 100% Isolated | Low |
| **Defense Scheduler** | Validates `team.is_capstone` & `Rubric.SCOPE_CAPSTONE` | Validates `team.is_pit` & `Rubric.SCOPE_PIT` | 🟢 100% Isolated | Low |
| **Grade Center** | Uses `TeamGrade.SCOPE_CAPSTONE` | Uses `TeamGrade.SCOPE_PIT` | 🟢 100% Isolated | Low |
| **Grade Config Updates** | `StageGradingConfig.save()` targets `SCOPE_CAPSTONE` | `PitEventGradingConfig.save()` targets `SCOPE_PIT` | 🟢 100% Isolated | Low |
| **Vault / Archive Naming** | 🔴 Hardcoded `3rdYear` prefix & regex | 🔴 Missing `4th Year` prefix & regex | 🟡 Independent in DB | 🔴 **HIGH** (File misnaming & archive queue blocks) |

---

## Detailed Findings

### 1. Capstone Scope Findings

#### 🔴 FINDING C-1: Hardcoded 3rdYear Prefix in Capstone Vault Template Resolution
- **File**: [`backend/modules/repository/audit/services.py`](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/audit/services.py#L447)
- **Problem**: `resolve_archive_file_template()` hardcodes `CAPSTONE_YEAR_PREFIX = '3rdYear'`. When a **4th Year Capstone** team generates or saves a vault deliverable filename template, it forces `3rdYear` prefix (e.g., `3rdYear.CAP301...`) instead of `4thYear.CAP301...`.
- **Impact**: 4th Year Capstone vault files are stored under invalid year metadata, leading to corrupt file naming conventions and search indexing bugs.

#### 🔴 FINDING C-2: Capstone Archive Regex Mismatch for 4th Year Teams
- **File**: [`backend/modules/repository/audit/services.py`](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/audit/services.py#L68)
- **Problem**: `CAPSTONE_FILENAME_RE` strictly matches `3rdYear` prefix:
  ```python
  CAPSTONE_FILENAME_RE = re.compile(
      r'^(?P<prefix>3rdYear)\.(?P<course>[A-Za-z0-9]+)\.'
      r'(?P<project>[A-Za-z0-9_-]+)\.(?P<semester>1stSemester|2ndSemester|Summer)\.pdf$',
      re.IGNORECASE,
  )
  ```
- **Impact**: In `capstone_archive_upload_queue()`, post-defense deliverable filename checks fail for 4th Year Capstone teams, causing uploaded post-defense files to be ignored by the archive queue.

---Done

### 2. PIT Scope Findings

#### 🔴 FINDING P-1: Missing 4th Year Prefix in `PIT_PREFIX_BY_YEAR`
- **File**: [`backend/modules/repository/audit/services.py`](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/audit/services.py#L52)
- **Problem**: `PIT_PREFIX_BY_YEAR` only contains entries for `1st Year`, `2nd Year`, and `3rd Year`.
- **Impact**: Any 4th Year PIT file upload is blocked by `upload_pit_files()` validation (`if selected_year not in PIT_PREFIX_BY_YEAR`).

#### 🔴 FINDING P-2: Missing 4th Year Alternation in `PIT_FILENAME_RE`
- **File**: [`backend/modules/repository/audit/services.py`](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/audit/services.py#L58)
- **Problem**: `PIT_FILENAME_RE` regex pattern lacks `4thYear` in the prefix capture group `(1stYear|2ndYear|3rdYear)`.
- **Impact**: 4th Year PIT filenames fail regex validation during batch archive uploads.

#### 🟡 FINDING P-3: Missing 4th Year Course Mapping Fallback
- **File**: [`backend/modules/repository/audit/services.py`](file:///c:/Users/Admin/Desktop/DefenSYS/backend/modules/repository/audit/services.py#L176)
- **Problem**: `_default_course_for_year('4th Year')` returns `'PIT301'` instead of `'PIT401'`.

---False Positve

### 3. Cross-Scope Verification

- **Deliverables Upload & Action Validation**: Verified clean. `DeliverableUploadSerializer` and `DeliverableActionSerializer` check `team.is_capstone` vs `team.is_pit` explicitly.
- **Defense Scheduler Validation**: Verified clean. Creating a schedule verifies `team.is_capstone` when `scope='capstone'` and `team.is_pit` when `scope='pit'`.
- **Grading & Rubric System**: Verified clean. Rubric scopes (`Rubric.SCOPE_CAPSTONE` vs `Rubric.SCOPE_PIT`) are enforced on schedule creation and score submissions.

---

## Action Plan & Remediation

1. **Update Archive Constants in `repository/audit/services.py`**:
   - Add `'4th Year': '4thYear'` to `PIT_PREFIX_BY_YEAR`.
   - Update `PIT_FILENAME_RE` prefix group to `(1stYear|2ndYear|3rdYear|4thYear)`.
   - Update `CAPSTONE_FILENAME_RE` prefix group to `(3rdYear|4thYear)`.
   - Add `'4th Year': 'PIT401'` to `_default_course_for_year()`.
2. **Update Vault Template Resolution**:
   - Replace hardcoded `CAPSTONE_YEAR_PREFIX` in `resolve_archive_file_template()` with dynamic year lookup (`'4thYear'` if `team.year_level == '4th Year'` else `'3rdYear'`).
3. **Automated Verification**:
   - Run full regression suite (`python manage.py test repository.deliverables repository.audit defense.scheduler`).
