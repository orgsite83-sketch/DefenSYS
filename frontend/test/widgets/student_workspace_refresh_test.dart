import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/screens/app/student/repository_tab.dart';
import 'package:defensys/screens/app/student_dashboard.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/repository_provider.dart';
import 'package:defensys/services/network/connectivity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/widgets/branding/defensys_mobile_brand.dart';

import '../helpers/pump_app.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    user: {'id': 1, 'role': 'student', 'name': 'Alex'},
  );
}

class _Notifications extends NotificationsNotifier {
  _Notifications(super.workspace);
  @override
  NotificationsState build() => const NotificationsState();
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _Dashboard extends DashboardNotifier {
  _Dashboard() : super('student');
  int reads = 0;
  @override
  DashboardState build() => DashboardState(
    data: {
      'student': {'id': 1, 'name': 'Alex'},
      'team': {'id': 7, 'name': 'Team Seven', 'isCapstone': true},
      'members': <Map<String, dynamic>>[],
      'stage_options': <String>[],
      'stages': <Map<String, dynamic>>[],
    },
  );
  @override
  Future<void> fetchDashboardData({bool silent = false}) async {
    reads++;
  }
}

class _Deliverables extends CapstoneDeliverablesNotifier {
  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

class _Library extends RepositoryNotifier {
  int reads = 0;
  @override
  Future<void> fetchForStudent({String? search}) async {
    reads++;
  }
}

void main() {
  testWidgets(
    'student loads tabs on demand and revalidates retained tabs on return',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dashboard = _Dashboard();
      final library = _Library();
      await pumpDefensysWidget(
        tester,
        const StudentDashboard(),
        overrides: [
          authProvider.overrideWith(_Auth.new),
          notificationsProvider.overrideWith2(_Notifications.new),
          dashboardProvider('student').overrideWith(() => dashboard),
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
          repositoryProvider.overrideWith(() => library),
          connectivityProvider.overrideWith(_Online.new),
        ],
      );
      expect(dashboard.reads, 1);
      expect(find.byType(DefensysMobileBrand), findsOneWidget);
      expect(library.reads, 0);
      expect(find.byType(RepositoryTab, skipOffstage: false), findsNothing);
      expect(find.byType(StudentEventsTab, skipOffstage: false), findsNothing);
      Future<void> select(int index) async {
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .onDestinationSelected!(index);
        await tester.pumpAndSettle();
      }

      await select(2);
      expect(library.reads, 1);
      expect(find.byType(DefensysMobileBrand), findsOneWidget);
      await select(0);
      expect(dashboard.reads, 2);
      expect(find.byType(RepositoryTab, skipOffstage: false), findsOneWidget);
      await select(2);
      expect(library.reads, 2);
      expect(find.byType(StudentEventsTab, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
