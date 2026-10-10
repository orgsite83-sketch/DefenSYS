import 'dart:async';

import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/app/app_settings_screen.dart';
import 'package:defensys/screens/app/panelist_dashboard.dart';
import 'package:defensys/screens/app/student/profile_edit_screen.dart';
import 'package:defensys/screens/app/student_dashboard.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/network/connectivity_provider.dart';
import 'package:defensys/services/theme_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

class _Auth extends AuthNotifier {
  _Auth(this.role);
  final String role;

  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: {
      'id': 42,
      'role': role,
      'username': '2026-0042',
      'first_name': 'Jonathan',
      'last_name': 'Beltran',
      'name': 'Jonathan Beltran',
      'email': 'jonathan@defensys.edu',
      'is_panelist': role == 'faculty',
    },
  );
}

class _Notifications extends NotificationsNotifier {
  _Notifications([super.workspace = 'admin']);
  @override
  NotificationsState build() => const NotificationsState();
  @override
  Future<void> fetchNotifications({bool? unreadOnly, bool loadMore = false}) async {}
}

class _Dashboard extends DashboardNotifier {
  _Dashboard() : super('student');
  @override
  DashboardState build() => DashboardState(error: 'Connection unavailable');
  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _Connectivity extends ConnectivityNotifier {
  @override
  bool build() => true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setApiHttpClientForTesting(
      MockClient(
        (_) async =>
            http.Response('{"teams":[],"history":[],"results":[]}', 200),
      ),
    );
  });
  tearDown(resetApiHttpClientForTesting);

  Future<ProviderContainer> show(
    WidgetTester tester, {
    String role = 'faculty',
    double width = 390,
    ThemeMode theme = ThemeMode.light,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts(force: true);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _Auth(role)),
        notificationsProvider.overrideWith2(_Notifications.new),
        dashboardProvider('student').overrideWith(_Dashboard.new),
        connectivityProvider.overrideWith(_Connectivity.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(themeModeProvider.notifier).setThemeMode(theme);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.mistDarkTheme,
            themeMode: ref.watch(themeModeProvider),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: RepaintBoundary(
              key: const ValueKey('preview'),
              child: role == 'student'
                  ? const StudentDashboard()
                  : const PanelistDashboard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder destination(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  for (final role in ['faculty', 'student']) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        '$role profile contains settings at 320px in ${theme.name} mode',
        (tester) async {
          final container = await show(
            tester,
            role: role,
            width: 320,
            theme: theme,
          );
          await tester.tap(destination('Profile'));
          await tester.pumpAndSettle();
          expect(find.byType(AppSettingsContent), findsOneWidget);
          expect(find.byTooltip('Settings'), findsNothing);
          expect(find.text('Appearance Theme'), findsNothing);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            '${role}_profile_${theme.name}',
          );
          final selector = find.byType(DropdownButtonFormField<ThemeMode>);
          await tester.ensureVisible(selector);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Use device setting').last);
          await tester.pumpAndSettle();
          expect(container.read(themeModeProvider), ThemeMode.system);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'Faculty profile remains available during assignment load and failure',
    (tester) async {
      final pending = Completer<http.Response>();
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.path.contains('panelist-assignments')) {
            return pending.future;
          }
          return http.Response('{"history":[]}', 200);
        }),
      );
      await show(tester);
      await tester.tap(destination('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      pending.complete(http.Response('{"detail":"Try again later"}', 500));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      await tester.tap(destination('Assignments'));
      await tester.pumpAndSettle();
      expect(find.text('Failed to load assignments'), findsOneWidget);
      await tester.tap(destination('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Profile form survives switching faculty tabs', (tester) async {
    await show(tester);
    await tester.tap(destination('Profile'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, 'Current Password');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'unsaved-input');
    await tester.tap(destination('Grade Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(destination('Profile'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(field).controller?.text,
      'unsaved-input',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Guest retains access details and sign out without account settings',
    (tester) async {
      await show(tester, role: 'guest_panelist');
      expect(destination('Profile'), findsNothing);
      expect(find.byType(ProfileScreen), findsNothing);
      await tester.tap(find.byTooltip('Guest access & sign out'));
      await tester.pumpAndSettle();
      expect(find.text('External evaluator'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      expect(find.byType(AppSettingsContent), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
