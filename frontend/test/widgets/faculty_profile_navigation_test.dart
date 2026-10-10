import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/app/student/profile_edit_screen.dart';
import 'package:defensys/screens/web/faculty/faculty_dashboard.dart';
import 'package:defensys/screens/web/uploader/uploader_dashboard.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    token: 'test-token',
    user: {
      'id': 1,
      'username': 'faculty',
      'name': 'Test Faculty',
      'role': 'faculty',
    },
  );
}

class _Dashboard extends DashboardNotifier {
  _Dashboard(this.workspace) : super('faculty');
  final String workspace;

  @override
  DashboardState build() => DashboardState(
    data: {
      'faculty': {'name': 'Test Faculty'},
      'roles': {workspace: true, 'pit_lead_year': '1st Year'},
    },
  );

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _Notifications extends NotificationsNotifier {
  _Notifications([super.workspace = 'admin']);
  @override
  NotificationsState build() => const NotificationsState();
  @override
  Future<void> fetchNotifications({bool? unreadOnly, bool loadMore = false}) async {}
}

class _Files implements AuthenticatedHttpClient {
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async =>
      http.Response('[]', 200);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<(ProviderContainer, GoRouter)> pumpWorkspace(
    WidgetTester tester, {
    String workspace = 'adviser',
    double width = 1400,
    bool realRouter = false,
    bool startAtProfile = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        dashboardProvider('faculty').overrideWith(() => _Dashboard(workspace)),
        notificationsProvider.overrideWith2(_Notifications.new),
        authenticatedHttpClientProvider.overrideWithValue(_Files()),
      ],
    );
    addTearDown(container.dispose);
    final router = realRouter
        ? container.read(appRouterProvider)
        : GoRouter(
            initialLocation: startAtProfile
                ? FacultyRoutes.profile
                : FacultyRoutes.dashboard,
            routes: [
              ShellRoute(
                builder: (_, __, child) => FacultyDashboard(routeChild: child),
                routes: [
                  GoRoute(
                    path: FacultyRoutes.dashboard,
                    builder: (_, __) => const Text('Workspace content'),
                  ),
                  GoRoute(
                    path: FacultyRoutes.profile,
                    builder: (_, __) =>
                        const FacultySectionContent(section: 'profile'),
                  ),
                  GoRoute(
                    path: FacultyRoutes.uploader,
                    builder: (_, __) => const Text('Uploader workspace'),
                  ),
                ],
              ),
            ],
          );
    addTearDown(router.dispose);
    if (realRouter) router.go(FacultyRoutes.profile);
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
    return (container, router);
  }

  Future<void> openAccountMenu(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
  }

  for (final workspace in [
    'faculty',
    'adviser',
    'pit_lead',
    'pit_instructor',
    'documenter',
  ]) {
    testWidgets('$workspace opens the shared profile from its account menu', (
      tester,
    ) async {
      final (_, router) = await pumpWorkspace(tester, workspace: workspace);
      await openAccountMenu(tester);
      expect(find.text('Profile'), findsOneWidget);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, FacultyRoutes.profile);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Identity & Account Details'), findsOneWidget);
      expect(find.text('Draw Signature'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('profile navigation closes a narrow workspace drawer', (
    tester,
  ) async {
    final (_, router) = await pumpWorkspace(tester, width: 700);
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await openAccountMenu(tester);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, FacultyRoutes.profile);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1400.0, 700.0]) {
    testWidgets(
      'cancel keeps unsaved workspace work when opening profile at $width',
      (tester) async {
        final (container, router) = await pumpWorkspace(tester, width: width);
        container.read(unsavedChangesProvider.notifier).setDirty(true);
        if (width < 1180) {
          await tester.tap(find.byTooltip('Open menu'));
          await tester.pumpAndSettle();
        }
        await openAccountMenu(tester);
        await tester.tap(find.text('Profile'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, FacultyRoutes.dashboard);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, FacultyRoutes.dashboard);
        expect(container.read(unsavedChangesProvider), isTrue);
        expect(find.text('Workspace content'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('uploader-only profile has a working return to its workspace', (
    tester,
  ) async {
    final (_, router) = await pumpWorkspace(
      tester,
      workspace: 'uploader',
      startAtProfile: true,
    );
    expect(find.byType(ProfileScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back to uploader workspace'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, FacultyRoutes.uploader);
    expect(find.byType(UploaderDashboard), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'faculty profile deep link resolves through the application router',
    (tester) async {
      final (_, router) = await pumpWorkspace(tester, realRouter: true);
      expect(router.state.uri.path, FacultyRoutes.profile);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );
}
