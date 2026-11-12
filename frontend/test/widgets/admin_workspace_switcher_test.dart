import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/workspace_preference.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/minutes/staff_workspace_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/app/app_navigator.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 7, 'role': 'admin', 'is_adviser': true},
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  Future<(GoRouter, ProviderContainer)> showSwitcher(
    WidgetTester tester, {
    bool dark = false,
    bool collapsed = false,
    Map<String, dynamic>? user,
    String initialLocation = '/admin/overview',
  }) async {
    await loadPreviewFonts();
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(_Auth.new)],
    );
    final router = GoRouter(
      initialLocation: initialLocation,
      navigatorKey: rootNavigatorKey,
      routes: [
        for (final path in ['/admin/overview', '/faculty/dashboard'])
          GoRoute(
            path: path,
            builder: (context, state) => Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: collapsed ? 72 : 260,
                  child: StaffWorkspaceSwitcher(
                    isWeb: true,
                    collapsed: collapsed,
                    userOverride: user,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
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
    return (router, container);
  }

  testWidgets('documenter-only account hides the workspace selector', (
    tester,
  ) async {
    await showSwitcher(
      tester,
      user: const {
        'id': 7,
        'role': 'faculty',
        'is_documenter': true,
        'has_staff_workspace': true,
      },
    );
    expect(find.byTooltip('Switch workspace'), findsNothing);
    expect(find.text('Staff web workspace'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final collapsed in [false, true]) {
    testWidgets(
      'adviser with panelist access has no sidebar switcher collapsed=$collapsed',
      (tester) async {
        await showSwitcher(
          tester,
          collapsed: collapsed,
          initialLocation: '/faculty/dashboard?workspace=adviser',
          user: const {
            'role': 'faculty',
            'is_adviser': true,
            'is_panelist': true,
          },
        );
        expect(find.byTooltip('Switch workspace'), findsNothing);
        expect(find.text('Panelist'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('sidebar lists only web destinations collapsed=$collapsed', (
      tester,
    ) async {
      final (router, _) = await showSwitcher(
        tester,
        collapsed: collapsed,
        initialLocation: '/faculty/dashboard?workspace=adviser',
        user: const {
          'role': 'faculty',
          'is_adviser': true,
          'is_documenter': true,
          'is_panelist': true,
        },
      );
      await tester.tap(find.byTooltip('Switch workspace'));
      await tester.pumpAndSettle();
      expect(find.text('Project Adviser'), findsWidgets);
      expect(find.text('Documenter'), findsWidgets);
      expect(find.text('Panelist'), findsNothing);
      await tester.tap(find.text('Documenter').last);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/faculty/dashboard?workspace=documenter',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'browser switches to documenter web workspace and back with saved context',
    (tester) async {
      final (router, container) = await showSwitcher(
        tester,
        user: const {
          'id': 7,
          'role': 'admin',
          'is_adviser': true,
          'is_documenter': true,
        },
      );
      await tester.tap(find.byTooltip('Switch workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Documenter').last);
      await tester.pumpAndSettle();
      const documenter = '/faculty/dashboard?workspace=documenter';
      expect(router.routeInformationProvider.value.uri.toString(), documenter);
      expect(
        await container.read(workspacePreferenceProvider.future),
        documenter,
      );
      expect(find.text('Documenter'), findsOneWidget);

      await tester.tap(find.byTooltip('Switch workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/overview');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'API requests capture the selected workspace after real navigation',
    (tester) async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      final (_, container) = await showSwitcher(tester);
      await tester.tap(find.byTooltip('Switch workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project Adviser'));
      await tester.pumpAndSettle();
      final client = container.read(authenticatedHttpClientProvider);
      await tester.runAsync(() async {
        await client.get(
          Uri.parse('https://example.test/api/teams/?workspace=operations'),
        );
        await client.post(
          Uri.parse('https://example.test/api/repository/deliverables/review/'),
          body: '{}',
        );
      });
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.headers['X-Defensys-Workspace'], 'adviser');
        expect(request.url.queryParameters['workspace'], 'adviser');
      }
    },
  );

  testWidgets('an instructor section fits the sidebar and stays in the URL', (
    tester,
  ) async {
    final (router, _) = await showSwitcher(
      tester,
      user: const {
        'id': 7,
        'role': 'admin',
        'staff_workspaces': {
          'pit_instructor_sections': [
            {'year_level': '1st Year', 'section': 'BSIT-1A'},
          ],
        },
      },
    );
    await tester.tap(find.byTooltip('Switch workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIT Instructor · 1st Year (BSIT-1A)'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'workspace': 'instructor',
      'workspaceYear': '1st Year',
      'workspaceSection': 'BSIT-1A',
    });
    expect(find.text('PIT Instructor · 1st Year (BSIT-1A)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final collapsed in [false, true]) {
      testWidgets(
        'admin can switch to adviser and back dark=$dark collapsed=$collapsed',
        (tester) async {
          final (router, container) = await showSwitcher(
            tester,
            dark: dark,
            collapsed: collapsed,
          );
          await tester.tap(find.byTooltip('Switch workspace'));
          await tester.pumpAndSettle();
          expect(find.text('Project Adviser'), findsOneWidget);
          await capturePreview(
            tester,
            find.byType(Scaffold),
            'admin-workspace-menu-${dark ? 'dark' : 'light'}-${collapsed ? 'collapsed' : 'expanded'}',
            viewport: true,
          );
          await tester.tap(find.text('Project Adviser'));
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.toString(),
            '/faculty/dashboard?workspace=adviser',
          );
          expect(
            await readRememberedWorkspace(7),
            '/faculty/dashboard?workspace=adviser',
          );
          expect(container.read(authProvider).user?['role'], 'admin');
          await tester.tap(find.byTooltip('Switch workspace'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Admin').last);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/admin/overview',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'cancel and failed draft saving retain the current workspace and dirty form',
    (tester) async {
      final (router, container) = await showSwitcher(tester);
      container.read(unsavedChangesProvider.notifier).setDirty(true);
      container
          .read(unsavedChangesSaveDraftProvider.notifier)
          .setCallback(() async => false);
      await tester.tap(find.byTooltip('Switch workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project Adviser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/overview');
      expect(container.read(unsavedChangesProvider), isTrue);
      await tester.tap(find.byTooltip('Switch workspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project Adviser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as Draft'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/overview');
      expect(container.read(unsavedChangesProvider), isTrue);
    },
  );
}
