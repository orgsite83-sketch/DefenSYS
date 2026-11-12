import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/navigation/workspace_access.dart';
import 'package:defensys/navigation/workspace_preference.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthNotifier {
  _Auth(this.user);
  final Map<String, dynamic> user;
  @override
  AuthState build() =>
      AuthState(isRestoring: false, token: 'fixture-token', user: user);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void setWidth(WidgetTester tester, double width) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
  }

  Future<(ProviderContainer, GoRouter)> showWorkspace(
    WidgetTester tester, {
    double width = 390,
    bool panelist = false,
    String role = 'faculty',
    String? preferredWorkspace,
    String? initialLocation,
  }) async {
    setWidth(tester, width);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final user = {
      'id': 7,
      'role': role,
      'is_adviser': true,
      'is_documenter': true,
      'is_panelist': panelist,
      'has_staff_workspace': true,
    };
    if (preferredWorkspace != null) {
      SharedPreferences.setMockInitialValues({
        'app.workspace.7': preferredWorkspace,
      });
    }
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _Auth(user))],
    );
    await container.read(workspacePreferenceProvider.future);
    // Exercise browser access rules with a real GoRouter/MediaQuery on the VM,
    // independently of the installed SDK's Windows browser-test harness.
    final router = GoRouter(
      initialLocation: initialLocation ?? AppRoutes.login,
      refreshListenable: container.read(routerRefreshProvider),
      redirect: (context, state) => WorkspaceAccess.redirect(
        user,
        state.uri.toString(),
        isWeb: true,
        viewportWidth: MediaQuery.sizeOf(context).width,
        preferredWorkspace: container.read(workspacePreferenceProvider).value,
      ),
      routes: [
        for (final route in [
          '/',
          AppRoutes.login,
          AdminRoutes.overview,
          AdminRoutes.users,
          FacultyRoutes.dashboard,
          FacultyRoutes.profile,
          AppRoutes.panelist,
          AppRoutes.documenter,
        ])
          GoRoute(
            path: route,
            builder: (context, _) => Scaffold(
              body: Column(
                children: [
                  Text(route),
                  Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () async {
                        await rememberWorkspace(ref, FacultyRoutes.dashboard);
                        if (context.mounted) {
                          context.go(FacultyRoutes.dashboard);
                        }
                      },
                      child: const Text('Use staff workspace'),
                    ),
                  ),
                ],
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return (container, router);
  }

  for (final role in ['faculty', 'admin']) {
    for (final workspace in [
      role == 'admin' ? AdminRoutes.overview : FacultyRoutes.dashboard,
      '/faculty/dashboard?workspace=adviser',
      '/faculty/dashboard?workspace=documenter',
    ]) {
      testWidgets('$role resizes with remembered $workspace', (tester) async {
        final (container, router) = await showWorkspace(
          tester,
          role: role,
          width: 1200,
          preferredWorkspace: workspace,
          initialLocation: workspace,
        );
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          workspace,
        );
        setWidth(tester, 600);
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          workspace,
        );
        setWidth(tester, 500);
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.documenter,
        );
        expect(
          await container.read(workspacePreferenceProvider.future),
          workspace,
        );
        router.go('/');
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.documenter,
        );
        setWidth(tester, 1200);
        await tester.pumpAndSettle();
        router.go('/');
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          workspace,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final panelist in [false, true]) {
    testWidgets(
      'phone-width browser defaults to ${panelist ? 'panel' : 'documenter'}',
      (tester) async {
        final (_, router) = await showWorkspace(tester, panelist: panelist);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          panelist ? AppRoutes.panelist : AppRoutes.documenter,
        );
        expect(tester.takeException(), isNull);
      },
    );
    for (final role in ['faculty', 'admin']) {
      testWidgets(
        '$role opens on a phone with a remembered adviser workspace and panelist=$panelist',
        (tester) async {
          final (_, router) = await showWorkspace(
            tester,
            role: role,
            panelist: panelist,
            preferredWorkspace: '/faculty/dashboard?workspace=adviser',
          );
          expect(
            router.routerDelegate.currentConfiguration.uri.path,
            panelist ? AppRoutes.panelist : AppRoutes.documenter,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('resizing from desktop to phone redirects the staff dashboard', (
    tester,
  ) async {
    final (_, router) = await showWorkspace(tester, width: 1200);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      FacultyRoutes.dashboard,
    );
    setWidth(tester, 600);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      FacultyRoutes.dashboard,
    );
    setWidth(tester, 500);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.documenter,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (role, location) in [
    ('faculty', '/faculty/profile?workspace=adviser'),
    ('admin', '/faculty/profile?workspace=adviser'),
    ('admin', AdminRoutes.users),
  ]) {
    testWidgets('resizing preserves $role subpage $location', (tester) async {
      final (_, router) = await showWorkspace(
        tester,
        role: role,
        width: 1200,
        initialLocation: location,
        preferredWorkspace: '/faculty/dashboard?workspace=adviser',
      );
      setWidth(tester, 390);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        location,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone width takes priority over a new staff choice', (
    tester,
  ) async {
    final (container, router) = await showWorkspace(tester);
    await tester.tap(find.text('Use staff workspace'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.documenter,
    );
    expect(
      await container.read(workspacePreferenceProvider.future),
      FacultyRoutes.dashboard,
    );
    setWidth(tester, 450);
    await tester.pumpAndSettle();
    router.go('/');
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.documenter,
    );
    expect(tester.takeException(), isNull);
  });
}
