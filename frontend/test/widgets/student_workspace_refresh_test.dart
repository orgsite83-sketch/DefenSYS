import 'dart:async';
import 'dart:typed_data';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/navigation/library_navigation.dart';
import 'package:defensys/screens/app/student/repository/repository_entry_view.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/academic/student_team_tasks_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

class _RoutedAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 1, 'role': 'student', 'name': 'Alex'},
  );
}

class _SlowFiles extends AuthenticatedHttpClient {
  _SlowFiles(super.ref);
  final responses = <Completer<Uint8List>>[];
  Completer<Uint8List> get response => responses.last;
  @override
  Future<Uint8List> fetchAuthenticatedFile(String fileRef) {
    responses.add(Completer<Uint8List>());
    return response.future;
  }
}

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
  for (final (browserBack, width) in [
    for (final width in [390.0, 1280.0])
      for (final browserBack in [false, true]) (browserBack, width),
  ]) {
    testWidgets(
      'student readers handle ${browserBack ? 'browser' : 'system'} Back without leaving the workspace at $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await loadPreviewFonts(force: true);
        final reflectImperativeRoutes =
            GoRouter.optionURLReflectsImperativeAPIs;
        GoRouter.optionURLReflectsImperativeAPIs = true;
        addTearDown(
          () => GoRouter.optionURLReflectsImperativeAPIs =
              reflectImperativeRoutes,
        );
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late _SlowFiles files;
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(_RoutedAuth.new),
            notificationsProvider.overrideWith2(_Notifications.new),
            dashboardProvider('student').overrideWith(_Dashboard.new),
            capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
            repositoryProvider.overrideWith(_Library.new),
            connectivityProvider.overrideWith(_Online.new),
            studentTeamTasksProvider.overrideWith((ref) async => {}),
            authenticatedHttpClientProvider.overrideWith(
              (ref) => files = _SlowFiles(ref),
            ),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(appRouterProvider);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
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
        expect(router.routeInformationProvider.value.uri.path, '/student');
        final teamHistory = router.routeInformationProvider.value;
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .onDestinationSelected!(2);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          studentLibraryPath,
        );
        final libraryHistory = router.routeInformationProvider.value;
        await tester.tap(find.text('Browse all'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '$studentLibraryPath/directory',
        );
        if (browserBack) {
          await router.routeInformationProvider.didPushRouteInformation(
            libraryHistory,
          );
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.text('A new idea starts here.'), findsOneWidget);
        final libraryContext = tester.element(find.byType(RepositoryTab));
        unawaited(
          pushLibraryPage<void>(
            libraryContext,
            page: 'project',
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Test project')),
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    TextButton(
                      onPressed: () => openRepositoryEntry(
                        context,
                        ref,
                        VaultEntry.fromJson({
                          'id': 'test-poster',
                          'file_url': '/media/poster.png',
                          'file_name': 'poster.png',
                          'document_kind': 'poster',
                        }),
                      ),
                      child: const Text('Open test poster'),
                    ),
                    TextButton(
                      onPressed: () => openRepositoryEntry(
                        context,
                        ref,
                        VaultEntry.fromJson({
                          'id': 'test-document',
                          'file_url': '/media/document.docx',
                          'file_name': 'document.docx',
                          'document_kind': 'document',
                        }),
                      ),
                      child: const Text('Open test document'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final projectHistory = router.routeInformationProvider.value;
        await tester.tap(find.text('Open test poster'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
        expect(
          router.routeInformationProvider.value.uri.path,
          '$studentLibraryPath/image',
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(Scaffold).last,
          'repository-fullscreen-loading-${width.toInt()}',
          viewport: true,
        );
        expect(find.byType(NavigationBar).hitTestable(), findsNothing);
        expect(find.byType(DefensysMobileBrand).hitTestable(), findsNothing);
        expect(
          tester.getSize(find.byType(Scaffold).last),
          Size(width, 900),
        );
        Future<void> back(RouteInformation previous) async {
          if (browserBack) {
            await router.routeInformationProvider.didPushRouteInformation(
              previous,
            );
          } else {
            await tester.binding.handlePopRoute();
          }
          await tester.pumpAndSettle();
        }

        await back(projectHistory);
        expect(find.text('Test project'), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // A download completing after Back must neither reopen its viewer nor
        // pop the project now on top of the navigator.
        files.response.complete(Uint8List(0));
        await tester.pumpAndSettle();
        expect(find.text('Test project'), findsOneWidget);
        await tester.tap(find.text('Open test document'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        if (browserBack) {
          await back(libraryHistory);
        } else {
          await back(projectHistory);
          expect(find.text('Test project'), findsOneWidget);
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
        }
        files.response.complete(Uint8List(0));
        await tester.pumpAndSettle();
        expect(find.text('A new idea starts here.'), findsOneWidget);
        await back(teamHistory);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .onDestinationSelected!(1);
        await tester.pumpAndSettle();
        await back(teamHistory);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        // A reloaded transient reader has no session payload. Recover to the
        // library rather than showing a blank reader or the login page.
        router.go('$studentLibraryPath/image');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          studentLibraryPath,
        );
        expect(find.text('A new idea starts here.'), findsOneWidget);
        expect(container.read(authProvider).token, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

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
