# L3: Monolithic Dart Screens Phased Refactoring Plan

> **Directive Status:** Active / In Progress  
> **Target Issue:** `L3. Large Dart Files Should Be Split` in [production_readiness_audit.md](file:///c:/Users/Admin/Desktop/DefenSYS/directives/production_readiness_audit.md)  
> **Goal:** Decompose 5 monolithic Flutter web screen files (>100KB / 3,000–5,700 lines each) into modular, single-responsibility sub-components, dialogs, and cards.

---

## 📌 Executive Summary

Large screen files hinder maintainability, slow down IDE analysis/refactoring, and increase risk during code reviews. Refactoring will be carried out incrementally in **5 distinct phases**. Each phase focuses on a single screen and must pass static analysis (`flutter analyze`) before proceeding to the next.

---

## 📊 Phase Tracker & Progress

- [x] **Phase 1: `user_management_screen.dart`** (5,707 lines -> decomposed into `user_management/` dialogs & components) ✅ COMPLETED
- [x] **Phase 2: `defense_scheduler_screen.dart`** (5,077 lines -> decomposed into `defense_scheduler/` dialogs, components & models) ✅ COMPLETED
- [x] **Phase 3: `team_deliverables_screen.dart`** (4,469 lines -> decomposed into `team_deliverables/` dialogs & components) ✅ COMPLETED
- [x] **Phase 4: `repository_audit_screen.dart`** (3,143 lines -> decomposed into `repository_audit/` dialogs & components) ✅ COMPLETED
- [x] **Phase 5: `student_teams_screen.dart`** (3,072 lines -> decomposed into `student_teams/` dialogs & components) ✅ COMPLETED

---

## 🛠 Refactoring Architecture Pattern

For each monolithic file, create a dedicated sub-directory following Flutter clean code conventions:

```text
frontend/lib/screens/web/[admin|shared]/<feature_name>/
├── <feature_name>_screen.dart        # Lightweight page shell & state connector (~200–300 lines)
├── components/                       # Visual layout sections & tables
│   ├── <feature>_header.dart
│   ├── <feature>_table.dart
│   └── <feature>_summary_cards.dart
└── dialogs/                          # Popups, form modals, & drawers
    ├── <feature>_create_edit_modal.dart
    └── <feature>_action_dialog.dart
```

---

## 📝 Detailed Phase Specifications

### 🟩 Phase 1: `user_management_screen.dart` ✅ COMPLETED
* **Original File:** [user_management_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart) (5,707 lines)
* **Target Folder:** `frontend/lib/screens/web/admin/user_management/`
* **Status:** Decomposed into `components/`, `dialogs/`, and `access_control/`.

---

### 🟩 Phase 2: `defense_scheduler_screen.dart` ✅ COMPLETED
* **Original File:** [defense_scheduler_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/defense_scheduler_screen.dart) (5,077 lines)
* **Target Folder:** `frontend/lib/screens/web/admin/defense_scheduler/`
* **Tasks:**
  - [x] Extract models and parsing helper logic into `models/schedule_import_models.dart`
  - [x] Extract slot edit modal into `dialogs/manual_slot_editor_dialog.dart`
  - [x] Extract schedule import & conflict resolution modal into `dialogs/venue_conflict_dialog.dart`
  - [x] Extract pre-defense deliverable review modal into `dialogs/team_deliverables_review_dialog.dart`
  - [x] Extract team readiness tracker table into `components/team_readiness_tracker.dart`
  - [x] Extract active schedule calendar list into `components/scheduler_calendar_view.dart`
  - [x] Extract filter toolbar & step indicator into `components/scheduler_toolbar.dart`
  - [x] Reduce `defense_scheduler_screen.dart` to lightweight main shell coordinator (<250 lines).
  - [x] Run `flutter analyze` & verify 0 errors.

---

### 🟩 Phase 3: `team_deliverables_screen.dart` ✅ COMPLETED
* **Original File:** [team_deliverables_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/shared/team_deliverables_screen.dart) (4,469 lines)
* **Target Folder:** `frontend/lib/screens/web/shared/team_deliverables/`
* **Tasks:**
  - [x] Extract submission history & detail modal into `dialogs/deliverable_submission_detail_modal.dart`
  - [x] Extract WPR approval & compilation modals into `dialogs/wpr_management_dialogs.dart`
  - [x] Extract grading/evaluation modal into `dialogs/grade_deliverable_modal.dart`
  - [x] Extract deliverables table into `components/deliverables_table.dart`
  - [x] Extract stage & section filter bar into `components/deliverables_filter_bar.dart`
  - [x] Reduce `team_deliverables_screen.dart` to page shell.
  - [x] Run `flutter analyze` & verify deliverable workflows.

---

### 🟩 Phase 4: `repository_audit_screen.dart` ✅ COMPLETED
* **Original File:** [repository_audit_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/shared/repository_audit_screen.dart) (3,143 lines)
* **Target Folder:** `frontend/lib/screens/web/shared/repository_audit/`
* **Tasks:**
  - [x] Extract PIT and Capstone upload modals into `dialogs/repository_upload_dialogs.dart`
  - [x] Extract status override, CSV export, and PDF viewing into `dialogs/status_override_dialog.dart`
  - [x] Extract audit activity log table & filters into `components/audit_log_table.dart`
  - [x] Extract repository analytics & summary cards into `components/audit_summary_cards.dart`
  - [x] Reduce `repository_audit_screen.dart` to main page shell (~200 lines).
  - [x] Run `flutter analyze` & verify 0 issues.

---

### 🟩 Phase 5: `student_teams_screen.dart` ✅ COMPLETED
* **Original File:** [student_teams_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart) (3,072 lines)
* **Target Folder:** `frontend/lib/screens/web/admin/student_teams/`
* **Tasks:**
  - [x] Extract team creation/editing modal into `dialogs/create_team_modal.dart`
  - [x] Extract adviser/panelist assignment modal into `dialogs/advisor_assignment_modal.dart`
  - [x] Extract team grid & roster cards into `components/student_teams_grid.dart`
  - [x] Extract search & section toolbar into `components/student_teams_toolbar.dart`
  - [x] Extract bulk import view into `components/student_teams_bulk_import.dart`
  - [x] Reduce `student_teams_screen.dart` to main coordinator shell (<250 lines).
  - [x] Run `flutter analyze` & verify team assignment workflows.

---

## ✅ Phase Completion Protocol

After completing each phase:
1. Run `flutter analyze` to ensure zero compilation or type errors.
2. Mark the corresponding checkboxes (`[x]`) in this document.
3. Once all 5 phases are complete, update `production_readiness_audit.md` to mark finding **L3** as resolved (`✅ RESOLVED`).
