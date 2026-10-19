import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/web/admin/curriculum_analytics/curriculum_analytics_screen.dart';
import 'package:defensys/screens/web/faculty/faculty_dashboard.dart';
import 'package:defensys/services/academic/curriculum_explorer_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _LeadAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    user: {
      'role': 'faculty',
      'name': 'PIT Lead',
      'is_pit_lead': true,
      'pit_lead_year': '3rd Year',
    },
  );
}

class _LeadDashboard extends DashboardNotifier {
  _LeadDashboard() : super('faculty');
  @override
  DashboardState build() => DashboardState(
    data: const {
      'faculty': {'name': 'PIT Lead'},
      'roles': {'pit_lead': true, 'pit_lead_year': '3rd Year', 'adviser': true},
    },
  );
  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _Notifications extends NotificationsNotifier {
  _Notifications([super.workspace = 'faculty']);
  @override
  NotificationsState build() => const NotificationsState();
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

class _Explorer extends CurriculumExplorerNotifier {
  final requests = <CurriculumExplorerQuery>[];
  @override
  Future<void> fetch(CurriculumExplorerQuery query) async {
    requests.add(query);
    state = CurriculumExplorerState(
      query: query,
      data: {
        'scope': query.scope,
        'year_level': query.yearLevel,
        'academic_years': <String>[],
        'projects_count': 0,
      },
    );
  }
}

void main() {
  testWidgets(
    'PIT Lead sidebar opens the shared analytics in the assigned workspace',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final explorer = _Explorer();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_LeadAuth.new),
          dashboardProvider('faculty').overrideWith(_LeadDashboard.new),
          notificationsProvider.overrideWith2(_Notifications.new),
          curriculumExplorerProvider.overrideWith(() => explorer),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: FacultyRoutes.dashboard,
        routes: [
          ShellRoute(
            builder: (_, __, child) => FacultyDashboard(routeChild: child),
            routes: [
              GoRoute(
                path: FacultyRoutes.dashboard,
                builder: (_, __) => const Text('Lead dashboard'),
              ),
              GoRoute(
                path: FacultyRoutes.curriculumAnalytics,
                builder: (_, __) => const FacultySectionContent(
                  section: 'curriculum_analytics',
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
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
      await tester.pumpAndSettle();
      expect(find.text('Curriculum Analytics'), findsOneWidget);
      await tester.tap(find.text('Curriculum Analytics'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        FacultyRoutes.curriculumAnalytics,
      );
      expect(
        tester
            .widget<CurriculumAnalyticsScreen>(
              find.byType(CurriculumAnalyticsScreen),
            )
            .pitYearLevel,
        '3rd Year',
      );
      expect(find.text('PIT · 3rd Year'), findsOneWidget);
      expect(explorer.requests, isNotEmpty);
      expect(
        explorer.requests.every((q) => q.scope == 'pit' && q.yearLevel == '3'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
