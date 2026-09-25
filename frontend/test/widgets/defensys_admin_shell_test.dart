import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/notifications/notifications_provider.dart';

import '../helpers/pump_app.dart';

class FakeNotificationsNotifier extends NotificationsNotifier {
  @override
  NotificationsState build() {
    return const NotificationsState(
      notifications: [],
      unreadCount: 0,
    );
  }

  @override
  Future<void> fetchNotifications() async {
    // No-op to prevent timer creation in tests
  }
}

void main() {
  testWidgets('DefensysAdminShell renders sidebar and child content at wide viewport', (
    tester,
  ) async {
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
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
      ],
    );

    expect(find.text('Shell child content'), findsOneWidget);
    expect(find.text('Student Teams'), findsWidgets);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

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
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
      ],
    );

    expect(find.text('Narrow shell content'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final userMgmtFinder = find.text('User Management');
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
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
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

  testWidgets('DefensysAdminShell supports null activeSection and highlights profile card when isProfileActive is true', (tester) async {
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
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
      ],
    );

    expect(find.text('Profile page content'), findsOneWidget);
    expect(find.text('Administrator'), findsWidgets);
  });

  testWidgets('DefensysAdminShell nav item highlights maroon directly on press/selection with zero black highlight', (tester) async {
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
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
      ],
    );

    // Find Student Teams nav item
    final studentTeamsTextFinder = find.text('Student Teams');
    expect(studentTeamsTextFinder, findsOneWidget);

    // Start a pointer down (press) gesture on Student Teams
    final gesture = await tester.startGesture(tester.getCenter(studentTeamsTextFinder));
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
    expect(maroonContainers.isNotEmpty, isTrue, reason: 'Nav item must be highlighted maroon on press');

    // Verify no container has black background
    final blackContainers = containers.where((c) {
      final dec = c.decoration;
      if (dec is BoxDecoration) {
        return dec.color == Colors.black || dec.color == const Color(0xFF000000);
      }
      return false;
    });
    expect(blackContainers.isEmpty, isTrue, reason: 'No nav item container should have black highlight');

    // Complete the tap
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tappedSection, DefensysAdminSection.studentTeams);
  });
}
