import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/admin_overview_scope_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/services/network/connectivity_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';
import '../helpers/auth_test_overrides.dart';

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _AttentionDashboard extends DashboardNotifier {
  _AttentionDashboard() : super('admin');

  @override
  DashboardState build() => DashboardState(
    data: {
      'overview': {
        'semester_id': null,
        'action_counts': {'academicPeriods': 1},
        'action_items': [
          {'id': 'no_active_period', 'target_section': 'academicPeriods'},
        ],
      },
    },
  );

  void resolve() => state = DashboardState(
    data: {
      'overview': {'semester_id': 2, 'action_counts': {}, 'action_items': []},
    },
  );
}

class _AttentionPeriods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();

  void activate() =>
      state = const AcademicPeriodState(activeSemester: {'id': 2});
}

class FakeNotificationsNotifier extends NotificationsNotifier {
  FakeNotificationsNotifier([super.workspace = 'admin']);
  @override
  NotificationsState build() {
    return const NotificationsState(notifications: [], unreadCount: 0);
  }

  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {
    // No-op to prevent timer creation in tests
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final dark in [false, true]) {
    testWidgets(
      'Academic Periods attention badge survives scope and collapse dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        DefensysAdminSection? navigated;
        await pumpDefensysWidget(
          tester,
          DefensysAdminShell(
            activeSection: DefensysAdminSection.overview,
            activeSemesterLabel: 'Not configured',
            onNavigate: (section) => navigated = section,
            onLogout: () {},
            child: const Text('Overview workspace'),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          overrides: [
            ...authTestOverrides(),
            connectivityProvider.overrideWith(_Online.new),
            academicPeriodProvider.overrideWith(_AttentionPeriods.new),
            dashboardProvider('admin').overrideWith(_AttentionDashboard.new),
            notificationsProvider.overrideWith2(
              (workspace) => FakeNotificationsNotifier(workspace),
            ),
          ],
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(DefensysAdminShell)),
        );
        final badge = find.byTooltip('1 administrative task');
        for (final scope in ['capstone', 'pit']) {
          container.read(adminOverviewScopeProvider.notifier).select(scope);
          await tester.pumpAndSettle();
          expect(badge, findsOneWidget);
          expect(
            find.descendant(of: badge, matching: find.text('1')),
            findsOneWidget,
          );
        }
        await capturePreview(
          tester,
          find.byType(DefensysAdminShell),
          'admin-sidebar-attention-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Academic Periods'));
        expect(navigated, DefensysAdminSection.academicPeriods);
        await tester.tap(find.byTooltip('Collapse sidebar'));
        await tester.pumpAndSettle();
        expect(badge, findsOneWidget);
        await tester.tap(find.byTooltip('Expand sidebar'));
        await tester.pumpAndSettle();
        expect(badge, findsOneWidget);
        (container.read(academicPeriodProvider.notifier) as _AttentionPeriods)
            .activate();
        await tester.pumpAndSettle();
        // Retain the semester guard while the dashboard response catches up.
        expect(badge, findsNothing);
        (container.read(dashboardProvider('admin').notifier)
                as _AttentionDashboard)
            .resolve();
        await tester.pumpAndSettle();
        expect(badge, findsNothing);
        expect(find.text('0'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Semester control opens period management at $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          if (width == 390) {
            tester.platformDispatcher.textScaleFactorTestValue = 1.4;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          await loadPreviewFonts();
          DefensysAdminSection? navigated;
          await pumpDefensysWidget(
            tester,
            DefensysAdminShell(
              activeSection: DefensysAdminSection.overview,
              activeSemesterLabel: 'Active: 1st Semester · 2026-2027',
              onNavigate: (section) => navigated = section,
              onLogout: () {},
              child: const Text('Overview workspace'),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
            overrides: [
              ...authTestOverrides(),
              connectivityProvider.overrideWith(_Online.new),
              notificationsProvider.overrideWith2(
                (workspace) => FakeNotificationsNotifier(workspace),
              ),
            ],
          );
          final semester = find.byKey(const ValueKey('admin-active-semester'));
          expect(find.text('Active semester'), findsOneWidget);
          expect(find.text('1st Semester · 2026-2027'), findsOneWidget);
          await tester.tap(semester);
          expect(navigated, DefensysAdminSection.academicPeriods);
          navigated = null;
          Focus.of(tester.element(find.text('Active semester'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(navigated, DefensysAdminSection.academicPeriods);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(DefensysAdminShell),
            'admin-semester-header-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
        },
      );
    }
  }
  testWidgets(
    'DefensysAdminShell renders sidebar and child content at wide viewport',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        DefensysAdminShell(
          activeSection: DefensysAdminSection.studentTeams,
          activeSemesterLabel: 'Active Sem: 2026-2027',
          onNavigate: (_) {},
          onLogout: () {},
          child: const Center(child: Text('Shell child content')),
        ),
        overrides: [
          notificationsProvider.overrideWith2(
            (workspace) => FakeNotificationsNotifier(workspace),
          ),
        ],
      );

      expect(find.text('Shell child content'), findsOneWidget);
      expect(find.text('Student Teams'), findsWidgets);
      expect(find.text('DASHBOARD'), findsNothing);
      expect(find.text('SEMESTER SETUP'), findsOneWidget);
      expect(find.text('ROSTER & TEAMS'), findsOneWidget);
      expect(find.text('DEFENSE & GRADING'), findsOneWidget);
      expect(find.text('ARCHIVE & REPORTS'), findsOneWidget);
      expect(find.text('Defense Schedule'), findsOneWidget);
      expect(find.text('Defense Stages'), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsNothing);
    },
  );

  testWidgets('DefensysAdminShell uses drawer below 1180px', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    DefensysAdminSection? navigated;

    await pumpDefensysWidget(
      tester,
      DefensysAdminShell(
        activeSection: DefensysAdminSection.overview,
        activeSemesterLabel: 'Active Sem: 2026-2027',
        onNavigate: (section) => navigated = section,
        onLogout: () {},
        child: const Center(child: Text('Narrow shell content')),
      ),
      overrides: [
        notificationsProvider.overrideWith2(
          (workspace) => FakeNotificationsNotifier(workspace),
        ),
      ],
    );

    expect(find.text('Narrow shell content'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final userMgmtFinder = find.text('Users & Roles');
    expect(userMgmtFinder, findsOneWidget);
    await tester.tap(userMgmtFinder);
    await tester.pumpAndSettle();

    expect(navigated, DefensysAdminSection.userManagement);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('DefensysAdminShell has no horizontal scroll at 800px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      DefensysAdminShell(
        activeSection: DefensysAdminSection.overview,
        activeSemesterLabel: 'Active Sem: 2026-2027',
        onNavigate: (_) {},
        onLogout: () {},
        child: const Center(child: Text('Compact content')),
      ),
      overrides: [
        notificationsProvider.overrideWith2(
          (workspace) => FakeNotificationsNotifier(workspace),
        ),
      ],
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .any((scrollView) => scrollView.scrollDirection == Axis.horizontal),
      isFalse,
    );
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });

  testWidgets(
    'DefensysAdminShell supports null activeSection and highlights profile card when isProfileActive is true',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        DefensysAdminShell(
          activeSection: null,
          isProfileActive: true,
          activeSemesterLabel: 'Active Sem: 2026-2027',
          onNavigate: (_) {},
          onLogout: () {},
          child: const Center(child: Text('Profile page content')),
        ),
        overrides: [
          notificationsProvider.overrideWith2(
            (workspace) => FakeNotificationsNotifier(workspace),
          ),
        ],
      );

      expect(find.text('Profile page content'), findsOneWidget);
      expect(find.text('Administrator'), findsWidgets);
    },
  );

  testWidgets(
    'DefensysAdminShell nav item highlights maroon directly on press/selection with zero black highlight',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      DefensysAdminSection? tappedSection;

      await pumpDefensysWidget(
        tester,
        DefensysAdminShell(
          activeSection: DefensysAdminSection.overview,
          activeSemesterLabel: 'Active Sem: 2026-2027',
          onNavigate: (section) => tappedSection = section,
          onLogout: () {},
          child: const Center(child: Text('Content')),
        ),
        overrides: [
          notificationsProvider.overrideWith2(
            (workspace) => FakeNotificationsNotifier(workspace),
          ),
        ],
      );

      // Find Student Teams nav item
      final studentTeamsTextFinder = find.text('Student Teams');
      expect(studentTeamsTextFinder, findsOneWidget);

      // Start a pointer down (press) gesture on Student Teams
      final gesture = await tester.startGesture(
        tester.getCenter(studentTeamsTextFinder),
      );
      await tester.pump();

      // Verify container background color is maroon, NOT black
      final containers = tester.widgetList<Container>(find.byType(Container));
      final maroonContainers = containers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          return dec.color == const Color(0xFF7A110A); // DefensysTokens.maroon
        }
        return false;
      });
      expect(
        maroonContainers.isNotEmpty,
        isTrue,
        reason: 'Nav item must be highlighted maroon on press',
      );

      // Verify no container has black background
      final blackContainers = containers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          return dec.color == Colors.black ||
              dec.color == const Color(0xFF000000);
        }
        return false;
      });
      expect(
        blackContainers.isEmpty,
        isTrue,
        reason: 'No nav item container should have black highlight',
      );

      // Complete the tap
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tappedSection, DefensysAdminSection.studentTeams);
    },
  );
}
