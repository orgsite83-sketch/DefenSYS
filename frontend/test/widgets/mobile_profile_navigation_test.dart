import 'dart:async';

import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/app/app_settings_screen.dart';
import 'package:defensys/screens/app/documenter_dashboard.dart';
import 'package:defensys/screens/app/panelist_dashboard.dart';
import 'package:defensys/screens/app/student/profile_edit_screen.dart';
import 'package:defensys/screens/app/student_dashboard.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/documenter_provider.dart';
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
  _Auth(this.role, this.documenter);
  final String role;
  final bool documenter;

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
      'is_panelist': role == 'faculty' || role == 'admin',
      'is_documenter': documenter,
    },
  );
}

class _Notifications extends NotificationsNotifier {
  _Notifications([super.workspace = 'admin']);
  @override
  NotificationsState build() => const NotificationsState();
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

class _Dashboard extends DashboardNotifier {
  _Dashboard([this.initialState]) : super('student');
  final DashboardState? initialState;
  @override
  DashboardState build() =>
      initialState ?? DashboardState(error: 'Connection unavailable');
  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}

  void update(DashboardState next) => state = next;
}

class _Connectivity extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _Documenter extends DocumenterNotifier {
  @override
  DocumenterState build() => const DocumenterState();
  @override
  Future<void> fetchAssignments() async {}
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
    DashboardState? dashboardState,
    bool documenter = false,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts(force: true);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _Auth(role, documenter)),
        notificationsProvider.overrideWith2(_Notifications.new),
        dashboardProvider(
          'student',
        ).overrideWith(() => _Dashboard(dashboardState)),
        connectivityProvider.overrideWith(_Connectivity.new),
        documenterProvider.overrideWith(_Documenter.new),
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
                  : documenter
                  ? const DocumenterDashboard()
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

  for (final role in ['faculty', 'admin']) {
    for (final documenter in [false, true]) {
      testWidgets(
        '$role opens phone Profile in ${documenter ? 'documenter' : 'panelist'} workspace',
        (tester) async {
          await show(tester, role: role, documenter: documenter, width: 320);
          await tester.tap(destination('Profile'));
          await tester.pumpAndSettle();
          expect(find.byType(ProfileScreen), findsOneWidget);
          expect(find.text('Account'), findsOneWidget);
          expect(find.text('Settings'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final (description, data) in <(String, Map<String, dynamic>)>[
    (
      'section project member',
      {
        'team': {'section_project_id': 7},
      },
    ),
    (
      'system team member',
      {
        'team': {'system_name': 'Shared system'},
      },
    ),
    (
      'managed section member',
      {
        'student': {'managed_section': 'BSIT-2A'},
      },
    ),
    (
      'project manager',
      {
        'student': {'is_project_manager': true},
      },
    ),
  ]) {
    testWidgets('Student $description opens Profile from the bottom bar', (
      tester,
    ) async {
      await show(
        tester,
        role: 'student',
        dashboardState: DashboardState(data: data),
      );
      expect(destination('Integration'), findsOneWidget);
      await tester.tap(destination('Profile'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Account & Security'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  }

  testWidgets('Student section member opens Profile from the drawer', (
    tester,
  ) async {
    await show(
      tester,
      role: 'student',
      dashboardState: DashboardState(
        data: {
          'team': {'section_project_id': 7},
        },
      ),
    );
    await tester.tap(find.byTooltip('Navigation Menu'));
    await tester.pumpAndSettle();
    final shortcut = find.text('Profile & Settings');
    await tester.ensureVisible(shortcut);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Account & Security'), findsOneWidget);
  });

  testWidgets(
    'Student Profile stays selected when Integration appears or disappears',
    (tester) async {
      final container = await show(tester, role: 'student');
      await tester.tap(destination('Profile'));
      await tester.pumpAndSettle();
      final dashboard =
          container.read(dashboardProvider('student').notifier) as _Dashboard;
      for (final data in <Map<String, dynamic>>[
        {
          'team': {'section_project_id': 7},
        },
        {},
      ]) {
        dashboard.update(DashboardState(data: data));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(find.text('Account & Security'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
      }
    },
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
          expect(
            find.byType(AppSettingsContent, skipOffstage: false),
            findsOneWidget,
          );
          expect(find.text('Account'), findsOneWidget);
          expect(find.text('Settings'), findsOneWidget);
          expect(find.text('Security'), findsOneWidget);
          expect(find.text('Guides & information'), findsOneWidget);
          expect(find.text('Account activity'), findsOneWidget);
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

  testWidgets('Student library stays above the grouped profile sections', (
    tester,
  ) async {
    await show(tester, role: 'student', width: 320);
    await tester.tap(destination('Profile'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Change Photo')).dy,
      lessThan(tester.getTopLeft(find.text('My library')).dy),
    );
    expect(
      tester.getTopLeft(find.text('My library')).dy,
      lessThan(tester.getTopLeft(find.text('Account')).dy),
    );
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);

    await tester.ensureVisible(find.text('Account'));
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Identity & Account Details'), findsOneWidget);

    await tester.ensureVisible(find.text('Guides & information'));
    await tester.tap(find.text('Guides & information'));
    await tester.pumpAndSettle();
    expect(find.text('About DefenSYS'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

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
    await tester.tap(find.text('Security'));
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
