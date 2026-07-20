# Restrict Capstone Instructor to Informational View Only

Capstone Instructors (faculty assigned as section instructors for 3rd/4th Year sections) currently get the same full workspace as PIT Instructors — with team management, deliverables, and grading access. Since capstone teams already have their own advisers, the Capstone Instructor role should be **informational only** — they can view team data but shouldn't get a full workspace with action-oriented features.

## Context: Capstone Timeline

- **3rd Year, 1st Sem** → Students are in PIT ("3rd Year PIT" teams)
- **3rd Year, 2nd Sem** → Students transition to Capstone ("3rd Year Capstone" teams) — Capstone 1 intake
- **4th Year, 1st Sem** → Capstone continues ("4th Year Capstone" teams) — Capstone 2 continuation

The current problem is in `views.py` line 799 — `level__icontains=norm_year` with `norm_year = "3rd Year"` matches **both** `"3rd Year PIT"` and `"3rd Year Capstone"` teams. So a 3rd Year section instructor gets a full workspace showing capstone teams too.

## Scope

> **Separation of Concerns**: Currently, a section instructor assigned to "3rd Year" picks up **both** PIT teams (3rd Year PIT) and Capstone teams (3rd Year Capstone) in the same workspace. The proposed change separates these so that:
> - PIT section assignments → full PIT Instructor workspace (as-is)
> - Capstone section assignments → read-only informational dashboard (no workspace in the sidebar switcher)

> **Mixed Roles**: If a faculty member is assigned as section instructor for **both** a PIT section (e.g., "1st Year") and a Capstone section (e.g., "3rd Year"), they will get the PIT workspace for the 1st Year and the Capstone informational view for the 3rd Year. The workspace switcher would only show PIT year-level workspaces.

## Open Questions

1. **What should the Capstone Instructor informational view show?** Options:
   - A lightweight dashboard showing assigned capstone teams with read-only stats (team name, project title, adviser, members, status) — no action buttons
   - Simply remove capstone instructor from the workspace switcher entirely, and rely on them using the "Project Adviser" workspace if they're also an adviser
   - Show a simplified card view on the main dashboard with a "Capstone Teams Overview" section

2. **Should the capstone section instructor still be able to navigate to deliverables view?** Currently they can open "Section Deliverables" — should this remain as a read-only view, or be removed entirely?

## Proposed Changes

### Backend — Dashboard API

#### [MODIFY] `backend/modules/dashboards/views.py`

- In `FacultyDashboardView.get()` (line ~789): Split the `pit_teams` query into two separate lists:
  - `pit_teams` → only teams where `level__icontains='PIT'` (filtered by section instructor assignments)
  - `capstone_info_teams` → only teams where `is_capstone=True` (filtered by section instructor assignments) — returned as a **separate key** in the response
- In `_faculty_roles()` (line ~105): Add a new role field `capstone_instructor: true/false` and `capstone_instructor_years: [...]` to distinguish from PIT instructor assignments

---

### Frontend — Faculty Dashboard

#### [MODIFY] `frontend/lib/screens/web/faculty/faculty_dashboard.dart`

- In `_availableWorkspaces()` (line 184): Only add `FacultyWorkspace.pitInstructor` entries for year levels that have PIT teams, not capstone
- Remove capstone year levels from the workspace dropdown
- Add a new `FacultyWorkspace` enum value or a lightweight informational section for capstone instructor data (if we choose to show it)

#### [MODIFY] `frontend/lib/screens/web/faculty/pit_instructor_dashboard_content.dart`

- Remove the `isCapstoneWorkspace` conditional logic — this dashboard will now only ever show PIT teams
- Simplify all labels back to "PIT" only (remove "Section Instructor workspace" alternate label)

---

### Frontend — New Informational Component (if Option 1 above)

#### [NEW] `frontend/lib/screens/web/faculty/capstone_instructor_info_section.dart`

- A lightweight, read-only widget that shows capstone team overview cards
- Displayed on the main dashboard when the faculty has capstone instructor assignments
- Shows: team name, project title, adviser name, member count, current status
- No action buttons, no deliverables navigation, no grading

## Verification Plan

### Manual Verification
- Log in as a faculty member who is a section instructor for a capstone year level (3rd or 4th Year)
- Verify the workspace switcher no longer shows a capstone workspace entry
- Verify the informational view (if applicable) shows capstone teams in read-only mode
- Log in as a PIT instructor (1st/2nd Year) and verify their workspace is unchanged
- Test a faculty with both PIT and capstone section assignments — confirm only PIT workspace appears in switcher
