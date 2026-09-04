import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_engine_screen.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_full_page_editor.dart';

class FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return AuthState(
      user: {
        'id': 1,
        'username': 'admin',
        'role': 'admin',
        'is_superuser': true,
      },
      token: 'fake-token',
    );
  }
}

class FakeRubricNotifier extends RubricEngineNotifier {
  @override
  RubricEngineState build() {
    return const RubricEngineState(
      isLoading: false,
      rubrics: [],
      scopes: [
        {'value': 'capstone', 'label': 'Capstone'},
        {'value': 'pit', 'label': 'PIT'},
      ],
      semesters: [
        {'id': 1, 'school_year': '2024-2025', 'semester': '1st Semester'},
      ],
      activeSemester: {
        'id': 1,
        'school_year': '2024-2025',
        'semester': '1st Semester',
      },
      scaleOptions: ['5-Point Scale', '10-Point Scale', '100-Point Scale'],
    );
  }

  @override
  Future<void> fetchRubrics({
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? termContext,
    String? successMessage,
  }) async {}
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState(
      schoolYears: [
        {'id': 1, 'school_year': '2024-2025', 'is_active': true},
      ],
      activeSemester: {'id': 1, 'school_year': '2024-2025', 'semester': '1st Semester'},
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeAdminDashboardNotifier extends DashboardNotifier {
  FakeAdminDashboardNotifier() : super('admin');

  @override
  DashboardState build() {
    return DashboardState(
      data: {'active_semester': '2024-2025'},
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class FakeFacultyDashboardNotifier extends DashboardNotifier {
  FakeFacultyDashboardNotifier() : super('faculty');

  @override
  DashboardState build() {
    return DashboardState(
      data: {'pit_lead_year': '3rd Year'},
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class FakeNotificationsNotifier extends NotificationsNotifier {
  @override
  NotificationsState build() => const NotificationsState(notifications: [], unreadCount: 0);

  @override
  Future<void> fetchNotifications() async {}
}

void main() {
  testWidgets('Clicking Create Standard Rubric opens editor without crash', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier()),
        rubricEngineProvider.overrideWith(() => FakeRubricNotifier()),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        dashboardProvider('admin').overrideWith(() => FakeAdminDashboardNotifier()),
        dashboardProvider('faculty').overrideWith(() => FakeFacultyDashboardNotifier()),
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    router.go('/admin/rubrics');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RubricEngineScreen), findsOneWidget);
    final createBtn = find.text('Create Standard Rubric').first;
    expect(createBtn, findsOneWidget);

    await tester.tap(createBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RubricFullPageEditor), findsOneWidget);
  });
}
