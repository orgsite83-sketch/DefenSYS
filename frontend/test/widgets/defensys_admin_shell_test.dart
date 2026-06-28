import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:user/services/notifications_provider.dart';

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

    expect(find.text('Grade Center'), findsOneWidget);

    await tester.tap(find.text('Grade Center'));
    await tester.pumpAndSettle();

    expect(navigated, DefensysAdminSection.gradeCenter);
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
}
