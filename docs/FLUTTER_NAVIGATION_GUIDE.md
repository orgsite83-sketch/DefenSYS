# Flutter Smooth Navigation Guide — DefenSYS Web

This guide explains how to fix the full-page reload problem in the DefenSYS Flutter web app and replace it with smooth, sidebar-persistent navigation — the same experience as the HTML prototype.

---

## The Problem

The current app uses `Navigator.push` for every feature screen:

```dart
// Current approach — causes full page reload on web
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const UserManagementScreen()),
);
```

On Flutter web, `Navigator.push` triggers a full widget tree rebuild. The `Scaffold`, `AppBar`, and sidebar all get torn down and rebuilt from scratch. This causes:

- The sidebar to flash/redraw on every navigation
- The AppBar to re-render
- Any persistent state (scroll position, open dropdowns) to reset
- A visible white flash between screens

---

## The Solution — Shell + IndexedStack

The fix is a **persistent shell widget** that holds the sidebar and only swaps the content area. The sidebar is built once and never rebuilt.

```
┌─────────────────────────────────────────────────────┐
│  AdminShell (StatefulWidget — built ONCE)           │
│  ┌──────────────┐  ┌──────────────────────────────┐ │
│  │  Sidebar     │  │  IndexedStack                │ │
│  │  (never      │  │  ┌──────────────────────────┐│ │
│  │  rebuilds)   │  │  │  Screen 0: Dashboard     ││ │
│  │              │  │  │  Screen 1: Users         ││ │
│  │              │  │  │  Screen 2: Teams         ││ │
│  │              │  │  │  ...                     ││ │
│  │              │  │  └──────────────────────────┘│ │
│  └──────────────┘  └──────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

`IndexedStack` keeps all screens alive in memory and just shows/hides them by index. Switching screens = changing an integer. No rebuild, no flash.

---

## Implementation

### Step 1 — Define your screen index enum

Create `user/lib/screens/web/admin/admin_shell.dart`:

```dart
enum AdminScreen {
  dashboard,
  academicPeriods,
  userManagement,
  studentRecords,
  studentTeams,
  defenseStages,
  rubricEngine,
  defenseScheduler,
  defenseBoard,
  gradeCenter,
}
```

### Step 2 — Build the AdminShell

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import all your screens
import 'admin_dashboard_content.dart';
import 'academic_periods_screen.dart';
// ... etc

// Riverpod provider to track active screen
final activeAdminScreenProvider = StateProvider<AdminScreen>(
  (ref) => AdminScreen.dashboard,
);

class AdminShell extends ConsumerWidget {
  final Map<String, dynamic>? userData;
  const AdminShell({super.key, this.userData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeScreen = ref.watch(activeAdminScreenProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Row(
        children: [
          // ── Sidebar — built once, never rebuilds ──
          AdminSidebar(
            activeScreen: activeScreen,
            onNavigate: (screen) {
              ref.read(activeAdminScreenProvider.notifier).state = screen;
            },
            userData: userData,
          ),

          // ── Content area — only this changes ──
          Expanded(
            child: IndexedStack(
              index: activeScreen.index,
              children: const [
                AdminDashboardContent(),   // index 0
                AcademicPeriodsScreen(),   // index 1
                UserManagementScreen(),    // index 2
                StudentAcademicRecordsScreen(), // index 3
                StudentTeamsScreen(),      // index 4
                DefenseStagesScreen(),     // index 5
                RubricEngineScreen(),      // index 6
                DefenseSchedulerScreen(),  // index 7
                DefenseBoardScreen(),      // index 8
                GradeCenterScreen(),       // index 9
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### Step 3 — Build the Sidebar widget

```dart
class AdminSidebar extends StatelessWidget {
  final AdminScreen activeScreen;
  final void Function(AdminScreen) onNavigate;
  final Map<String, dynamic>? userData;

  const AdminSidebar({
    super.key,
    required this.activeScreen,
    required this.onNavigate,
    this.userData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: const Color(0xFF7A110A), // --primary-maroon
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 25, 20, 20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                // Logo
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'DefenSYS',
                  style: TextStyle(
                    color: Color(0xFFFFC107), // --accent-gold
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _navItem(Icons.bar_chart, 'Overview',
                    AdminScreen.dashboard),
                _navItem(Icons.calendar_month, 'Academic Periods',
                    AdminScreen.academicPeriods),
                _navItem(Icons.people_alt, 'User Management',
                    AdminScreen.userManagement),
                _navItem(Icons.badge, 'Student Records',
                    AdminScreen.studentRecords),
                _navItem(Icons.groups, 'Student Teams',
                    AdminScreen.studentTeams),
                _navItem(Icons.layers, 'Defense Stages',
                    AdminScreen.defenseStages),
                _navItem(Icons.fact_check, 'Rubric Engine',
                    AdminScreen.rubricEngine),
                _navItem(Icons.event_available, 'Defense Scheduler',
                    AdminScreen.defenseScheduler),
                _navItem(Icons.table_chart, 'Defense Board',
                    AdminScreen.defenseBoard),
                _navItem(Icons.grade, 'Grade Center',
                    AdminScreen.gradeCenter),
              ],
            ),
          ),

          // Footer — logout
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Consumer(
              builder: (context, ref, _) => GestureDetector(
                onTap: () {
                  ref.read(authProvider.notifier).logout();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: Color(0xFFFCA5A5), size: 18),
                    const SizedBox(width: 10),
                    const Text(
                      'Log Out',
                      style: TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, AdminScreen screen) {
    final isActive = activeScreen == screen;
    return GestureDetector(
      onTap: () => onNavigate(screen),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 1),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF5E0D08) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive ? const Color(0xFFFFC107) : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? const Color(0xFFFFC107) : const Color(0xFFD1D5DB),
            ),
            const SizedBox(width: 15),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isActive ? const Color(0xFFFFC107) : const Color(0xFFD1D5DB),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Step 4 — Update login to navigate to AdminShell

```dart
// In login_screen.dart — replace AdminDashboard with AdminShell
if (user['role'] == 'admin') {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => AdminShell(userData: user),
    ),
  );
}
```

### Step 5 — Remove AppBar from individual screens

Each screen (e.g. `UserManagementScreen`) should no longer have its own `Scaffold` + `AppBar`. Instead, return just the content:

```dart
// Before — each screen had its own Scaffold
class UserManagementScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(          // ← remove this
      appBar: AppBar(...),    // ← remove this
      body: ...content...
    );
  }
}

// After — just return the content
class UserManagementScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: ...content...
    );
  }
}
```

---

## Why IndexedStack over other approaches

| Approach | Sidebar redraws? | Screen state preserved? | Notes |
|---|---|---|---|
| `Navigator.push` (current) |  Yes — full rebuild |  No | Causes the flash |
| `Navigator` with named routes |  Yes — full rebuild |  No | Same problem |
| `IndexedStack` |  No |  Yes | Best for web dashboards |
| `PageView` |  No |  Yes | Good but swipe gesture can interfere |
| `AnimatedSwitcher` |  No |  No — rebuilds on switch | Good for transitions, not state |

`IndexedStack` is the right choice here because:
- Sidebar is completely outside the stack — never touched
- All screens stay alive in memory — scroll positions, loaded data, open panels all persist
- Switching is instant — just an integer change, no widget rebuild
- Works identically on web, Android, and iOS

---

## Handling sub-screens (modals and detail views)

For screens that need to open a detail view (e.g. clicking a team to see its details), use `showDialog` or a side panel instead of `Navigator.push`:

```dart
// Instead of Navigator.push for detail views:
showDialog(
  context: context,
  builder: (_) => TeamDetailDialog(teamId: team.id),
);

// Or a slide-in panel using AnimatedContainer on the right side
```

This keeps the sidebar visible and avoids any navigation flash.

---

## Top Nav Bar

Add a persistent top nav bar inside `AdminShell`, above the `IndexedStack`:

```dart
Expanded(
  child: Column(
    children: [
      // Top nav — sticky, always visible
      Container(
        height: 70,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          children: [
            const Spacer(),
            // Active semester badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFDEF7EC),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Active Sem: 2026-2027',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF03543F),
                ),
              ),
            ),
            const SizedBox(width: 15),
            // Profile circle
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFF7A110A),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(userData?['name'] ?? 'Admin'),
          ],
        ),
      ),
      // Content
      Expanded(
        child: IndexedStack(
          index: activeScreen.index,
          children: [...],
        ),
      ),
    ],
  ),
),
```

---

## Summary

The full change is:

1. Create `AdminShell` with a persistent `Row(sidebar, IndexedStack)`
2. Move navigation state to a Riverpod `StateProvider<AdminScreen>`
3. Sidebar calls `onNavigate(screen)` which updates the provider
4. `IndexedStack` reacts to the provider and shows the right screen
5. Remove `Scaffold`/`AppBar` from individual screens — they live inside the shell now
6. Login navigates to `AdminShell` instead of `AdminDashboard`

Result: clicking any sidebar item changes one integer. The sidebar, top nav, and all other screens stay exactly where they are. Zero flash, zero rebuild, instant navigation.
