# DefenSYS Routing Audit — All Identified Issues & Phased Fix Plan

> Audited: `frontend/lib/navigation/` + `frontend/lib/screens/web/`
> Date: 2026-05-29

---

## Executive Summary

The routing system uses **go_router** with a `ShellRoute` per persona (admin / faculty). Most "top-level" admin sections render their content **locally** inside `AdminShell._buildSectionContent()` and the go_router child for those routes is just `const SizedBox.shrink()`. Sub-pages (bulk-import, team detail, rubric editor, etc.) are the only routes that use the actual go_router child widget.

The core problem is a **mismatch between URL state and widget state**: several flows change the URL to enter a sub-page (e.g. `/admin/users/bulk-import`) but never navigate the URL back to the parent when the sub-page is dismissed. The URL stays "stuck" while the widget flips an internal `_showBulkImport` bool, which means:

1. The browser URL bar is wrong.
2. Clicking the same sidebar item or header button again is a no-op (go_router sees you're already at that path).
3. Refreshing the page reopens the sub-page unexpectedly.

---

## Issue 1 — User Bulk Import: URL stays at `/admin/users/bulk-import` after successful import

> **This is the exact bug the user reported.**

### Root Cause

| Step | What happens |
|------|-------------|
| User clicks **Bulk Import CSV** | `context.go(AdminRoutes.usersBulkImport)` → URL becomes `/admin/users/bulk-import` |
| go_router builds `UserManagementScreen(initialBulkImport: true)` | `initState` sets `_showBulkImport = true` |
| Import succeeds | [_importBulkUsers L4011-4016](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart#L4011-L4016) sets `_showBulkImport = false` via `setState` — **but never calls `context.go(AdminRoutes.users)`** |
| Result | URL is still `/admin/users/bulk-import`. The widget shows the user table (because `_isBulkImportVisible` is now false), but the browser bar is wrong. |
| User clicks **Bulk Import CSV** again | `context.go(AdminRoutes.usersBulkImport)` is a no-op because go_router thinks we're already there. Nothing happens. |

The same issue happens when the user clicks **Back to Users** or **Cancel** inside the bulk import page:

- [L1111](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart#L1111): `setState(() => _showBulkImport = false)` — no URL change
- [L1366](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart#L1366): same

### Affected Files

- [user_management_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart) — lines 234, 1111, 1366, 4011-4016

### Fix

Every exit from the bulk-import view must call `context.go(AdminRoutes.users)` instead of (or in addition to) toggling the `_showBulkImport` bool.

```dart
// L4011-4016: after successful import
if (imported) {
  setState(() {
    _showBulkImport = false;
    _bulkCsv = '';
  });
  context.go(AdminRoutes.users);  // ← ADD THIS
}
```

```dart
// L1111: "Back to Users" button
onTap: state.isSaving
    ? null
    : () {
        setState(() => _showBulkImport = false);
        context.go(AdminRoutes.users);  // ← ADD THIS
      },
```

```dart
// L1366: "Cancel" button
onTap: state.isSaving
    ? null
    : () {
        setState(() => _showBulkImport = false);
        context.go(AdminRoutes.users);  // ← ADD THIS
      },
```

---

## Issue 2 — Student Teams Bulk Import: same URL stickiness

### Root Cause

Identical pattern. When admin clicks **Bulk Import** on the Student Teams page:

- [student_teams_screen.dart L319](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart#L319): `context.go(AdminRoutes.studentTeamsBulkImport)` → URL becomes `/admin/student-teams/bulk-import`
- After all rows import successfully, [L1946-1956](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart#L1946-L1956): `_showBulkImport = false` — **no URL change**
- The "Back" button at [L1085-1093](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart#L1085-L1093) does call `context.pop()` / `context.go(AdminRoutes.studentTeams)`, so the back button works — but the **successful import path** doesn't.

### Affected Files

- [student_teams_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart) — lines 1946-1956

### Fix

After the successful import clears `_showBulkImport`, navigate the URL:

```dart
// L1946-1956: after remaining.isEmpty (full success)
setState(() {
  _showBulkImport = false;
  _parsedBulkRows = [];
  _bulkCsv = '';
  _bulkPreview = null;
});
context.go(AdminRoutes.studentTeams);  // ← ADD THIS
_snack('$created team${created == 1 ? '' : 's'} imported.');
```

---

## Issue 3 — `_isAdminDetailRoute` heuristic is fragile

### Root Cause

[admin_shell.dart L101-111](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/admin_shell.dart#L101-L111) decides whether to show the go_router child vs. locally-built section content:

```dart
bool _isAdminDetailRoute(GoRouterState state) {
  final params = state.pathParameters;
  if (params.containsKey('teamId') || ...) return true;
  return state.uri.path.endsWith('/bulk-import');
}
```

This works today, but:

1. It hard-codes the `/bulk-import` suffix — any future sub-routes need manual updates here.
2. If Issue 1/2 are fixed (URL resets to parent on exit), this method may briefly return `true` for the old URL while `setState` propagates, causing a flash of `SizedBox.shrink()`.

### Fix

No immediate change needed if Issues 1 & 2 are fixed correctly (the URL and the bool flip in the same frame). However, the heuristic should be replaced with a **route-metadata approach** long-term — e.g., a `GoRoute.extra` flag or a static set of detail path prefixes.

> [!TIP]
> A safer approach is to check whether `widget.routeChild` is **not** `SizedBox.shrink()`. Since all top-level admin route builders return `const SizedBox.shrink()`, any non-shrink child means we're on a detail page.

---

## Issue 4 — Faculty `_activeSection` drifts out of sync with URL

### Root Cause

The faculty sidebar drives navigation via `_goToSection(section)` which calls `context.go(FacultyRoutes.pathForSection(section))`. However, the `_activeSection` state variable is **not updated** when the URL changes — it's only set by direct sidebar taps.

In [faculty_dashboard.dart L665-667](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/faculty/faculty_dashboard.dart#L665-L667):

```dart
final sectionFromRoute = FacultyRoutes.sectionForLocation(routerState.uri.path);
final activeSection = sectionFromRoute ?? _activeSection;
```

The **content area** correctly derives from the URL, but the **sidebar highlight** reads `_activeSection` directly ([L325](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/faculty/faculty_dashboard.dart#L325): `isActive: _activeSection == 'dashboard'`). This means after navigating via go_router (e.g., a deep link or browser back/forward), the sidebar highlight stays on the old section.

### Affected Files

- [faculty_dashboard.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/faculty/faculty_dashboard.dart) — lines 39, 325, 412, 431, etc.

### Fix

Sync `_activeSection` from the URL in `build()`, similar to how `AdminShell` syncs `activeAdminSectionProvider`:

```dart
@override
Widget build(BuildContext context) {
  // ... existing code ...
  final routerState = GoRouterState.of(context);
  final sectionFromRoute = FacultyRoutes.sectionForLocation(routerState.uri.path);
  if (sectionFromRoute != null && sectionFromRoute != _activeSection) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _activeSection = sectionFromRoute);
    });
  }
  // ...
}
```

---

## Issue 5 — Admin sidebar highlight uses `activeAdminSectionProvider` which can lag behind URL

### Root Cause

In [admin_shell.dart L70-75](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/admin_shell.dart#L70-L75), the admin shell syncs the Riverpod `activeAdminSectionProvider` from the URL via `addPostFrameCallback`. This is **one frame late**, which means:

1. During that first frame, the sidebar might highlight the wrong section.
2. If `_isAdminDetailRoute` returns `true` (e.g., on `/admin/users/bulk-import`), the section correctly resolves to `userManagement` — but the sidebar highlight comes from the provider which hasn't been updated yet.

### Impact

Low — the user may see a 1-frame flicker on the sidebar highlight when deep-linking. It's generally invisible but can be noticed on slow machines.

### Fix

Use the locally-derived `activeSection` variable (from URL) for the sidebar, not the provider. The provider should be treated as secondary/downstream, not as the source of truth:

```dart
// Already good — L67-68 derives from URL:
final activeSection = routeSection ?? DefensysAdminSection.overview;
// This is already passed to the shell:
activeSection: activeSection,  // L83
```

This is already correct. The only improvement would be moving the provider sync to happen **before** the build completes (e.g., in `didChangeDependencies` or a `ref.listen` on the router).

---

## Issue 6 — Navigating to bulk-import route creates a **new** widget instance, losing local state

### Root Cause

When the user clicks **Bulk Import CSV** from the User Management page:

1. `context.go(AdminRoutes.usersBulkImport)` navigates to `/admin/users/bulk-import`
2. go_router builds a **new** `UserManagementScreen(initialBulkImport: true)` for this child route
3. `_isAdminDetailRoute` returns `true`, so `AdminShell` renders the **go_router child** (the new `UserManagementScreen`)
4. When the parent route (`/admin/users`) was showing the original `UserManagementScreen`, that widget is now **orphaned** — it's no longer in the widget tree

This means:
- Any **local filter state** (search query, role filter, current page) from the parent's `UserManagementScreen` is lost.
- After import, if you navigate back to `/admin/users`, a fresh `UserManagementScreen` is created — all filters reset.

The same applies to `StudentTeamsScreen` and its bulk import route.

### Impact

Medium — users lose their table filters/search after bulk importing. Not a crash, but annoying UX.

### Fix (Longer-term)

Two approaches:

**A. Keep bulk import as an overlay/modal (no route change)**
- Remove the `/admin/users/bulk-import` and `/admin/student-teams/bulk-import` child routes
- The "Bulk Import" button just sets `_showBulkImport = true` via `setState`
- No URL change, no widget rebuild, no state loss
- Downside: no shareable/bookmarkable URL for the import page

**B. Lift state to a provider**
- Move `_showBulkImport`, filters, search query, etc. into a Riverpod provider
- Both the parent route's widget and the child route's widget read from the same provider
- The URL change is cosmetic; state persists

> [!IMPORTANT]
> Approach A is simpler and matches how the screens already work internally (toggle a bool). Approach B is more "correct" for a URL-driven app but requires more refactoring.

---

## Phased Fix Plan

### Phase 1 — Fix the immediate user-reported bug (Issues 1 & 2)
**Effort: ~30 min | Risk: Low**

| File | Change |
|------|--------|
| [user_management_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/user_management_screen.dart) | Add `context.go(AdminRoutes.users)` after setting `_showBulkImport = false` in 3 places (L1111, L1366, L4013) |
| [student_teams_screen.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/student_teams_screen.dart) | Add `context.go(AdminRoutes.studentTeams)` after `_showBulkImport = false` in the success path (L1950) |

### Phase 2 — Fix faculty sidebar highlight desync (Issue 4)
**Effort: ~15 min | Risk: Low**

| File | Change |
|------|--------|
| [faculty_dashboard.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/faculty/faculty_dashboard.dart) | Sync `_activeSection` from URL in `build()` (or `_buildActiveContent`). Use the derived `sectionFromRoute` for sidebar `isActive` checks. |

### Phase 3 — Harden the admin detail-route heuristic (Issue 3)
**Effort: ~15 min | Risk: Low**

| File | Change |
|------|--------|
| [admin_shell.dart](file:///c:/Users/Admin/Desktop/DefenSYS/frontend/lib/screens/web/admin/admin_shell.dart) | Replace `endsWith('/bulk-import')` with a more robust check (e.g., `widget.routeChild is! SizedBox` or a static set of known detail prefixes) |

### Phase 4 — Eliminate widget-rebuild state loss (Issue 6)
**Effort: ~1-2 hours | Risk: Medium**

Choose Approach A or B above. Approach A (remove child routes, use `setState` only) is recommended for simplicity and consistency with the existing pattern.

### Phase 5 (Optional) — Admin section provider sync timing (Issue 5)
**Effort: ~10 min | Risk: Very Low**

Move the `activeAdminSectionProvider` sync out of `addPostFrameCallback` and into a `ref.listen` on the router location. This eliminates the 1-frame lag.

---

## Summary Table

| # | Issue | Severity | Phase | Effort |
|---|-------|----------|-------|--------|
| 1 | User bulk import URL sticks | **High** (user-reported) | 1 | 10 min |
| 2 | Student teams bulk import URL sticks | **High** | 1 | 10 min |
| 3 | `_isAdminDetailRoute` is fragile | Medium | 3 | 15 min |
| 4 | Faculty sidebar highlight desync | Medium | 2 | 15 min |
| 5 | Admin section provider 1-frame lag | Low | 5 | 10 min |
| 6 | Widget rebuild loses filter state | Medium | 4 | 1-2 hr |
