import 'dart:convert';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/screens/web/admin/user_management/access_control/access_control_view.dart';
import 'package:defensys/screens/web/admin/user_management/access_control/panelist_eligibility_view.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod/misc.dart' show Override;
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';

const _preview = ValueKey('roles-access-preview');
const _user = <String, dynamic>{
  'id': 206,
  'username': '206',
  'name': 'Ricardo Fontanilla',
  'email': '206@ustp.edu.ph',
  'role': 'faculty',
  'is_panelist': true,
  'is_pit_lead': true,
  'pit_lead_year': '1st Year',
  'is_adviser': true,
  'is_documenter': false,
};

class _Users extends UserManagementNotifier {
  bool failHistory = false;
  @override
  UserManagementState build() => const UserManagementState(users: [_user]);
  @override
  Future<void> fetchUsers({
    String? search,
    String? role,
    String? successMessage,
  }) async {}
  @override
  Future<List<Map<String, dynamic>>> fetchRoleAssignmentHistory(int id) async {
    if (failHistory) throw Exception('Unavailable');
    return [
      {
        'id': 1,
        'role_key': 'panelist',
        'role_label': 'Defense Panelist',
        'semester': '1st Semester, A.Y. 2026-2027',
        'changed_at': '2026-10-10T08:00:00Z',
        'changed_by_name': 'Administrator',
        'action': 'assigned',
      },
    ];
  }
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'admin'});
}

class _Schedules extends DefenseSchedulerNotifier {
  @override
  DefenseSchedulerState build() => const DefenseSchedulerState(
    canApprovePanelists: true,
    faculty: [
      {
        'id': 39,
        'name': 'Lina Santos',
        'username': '207',
        'is_panelist': false,
      },
      _user,
    ],
  );
  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}
}

class _Client implements AuthenticatedHttpClient {
  String status = 'pending';
  final patches = <Map<String, dynamic>>[];
  Map<String, dynamic> get request => {
    'id': 42,
    'faculty_id': 39,
    'faculty_name': 'Lina Santos',
    'requested_by_name': 'Ricardo Fontanilla',
    'pit_year': '1st Year',
    'reason': 'Relevant project expertise.',
    'status': status,
    'created_at': '2026-10-05T08:00:00Z',
    'reviewed_at': status == 'pending' ? null : '2026-10-10T09:00:00Z',
    'reviewed_by_name': status == 'pending' ? null : 'Administrator',
  };
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    if (uri.path.endsWith('/42/')) {
      return http.Response(
        jsonEncode({'request': request, 'can_review': true}),
        200,
      );
    }
    final reviewed = uri.queryParameters['status'] == 'reviewed';
    final matches = reviewed ? status != 'pending' : status == 'pending';
    return http.Response(
      jsonEncode({
        'panelist_requests': matches ? [request] : [],
        'count': matches ? 1 : 0,
        'pending_count': status == 'pending' ? 1 : 0,
        'reviewed_count': status == 'pending' ? 0 : 1,
        'next': null,
      }),
      200,
    );
  }

  @override
  Future<http.Response> patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final data = Map<String, dynamic>.from(jsonDecode(body as String));
    patches.add(data);
    status = data['decision'];
    return http.Response(jsonEncode({'request': request}), 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1366, 1000),
  bool dark = false,
  _Users? users,
  _Client? client,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  final container = ProviderContainer(
    overrides: <Override>[
      authProvider.overrideWith(_Auth.new),
      userManagementProvider.overrideWith(() => users ?? _Users()),
      defenseSchedulerProvider.overrideWith(_Schedules.new),
      if (client != null)
        authenticatedHttpClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: _preview,
        child: MaterialApp(
        debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.mistDarkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

AccessControlView _editor({
  Map<String, dynamic> user = _user,
  ValueChanged<Map<String, dynamic>>? save,
}) => AccessControlView(
  user: user,
  state: const UserManagementState(),
  onBack: () {},
  onSaveRoles: save ?? (_) {},
  onEditProfile: () {},
  onResetPassword: () {},
  onOpenPanelistAccess: () {},
);

void main() {
  for (final variant in [
    ('roles_access_desktop', const Size(1366, 1200), false),
    ('roles_access_mobile', const Size(360, 780), false),
    ('roles_access_dark', const Size(1366, 1200), true),
  ]) {
    testWidgets('role editor is responsive: ${variant.$1}', (tester) async {
      await _pump(tester, _editor(), size: variant.$2, dark: variant.$3);
      expect(find.text('Roles & access'), findsOneWidget);
      expect(find.text('Assigned roles'), findsOneWidget);
      await capturePreview(tester, find.byKey(_preview), variant.$1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'role history displays actual actor, timestamp and semester fields',
    (tester) async {
      await _pump(tester, _editor());
      await tester.tap(find.text('Role history'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Administrator · Oct 10, 2026'),
        findsOneWidget,
      );
      expect(find.text('1st Semester, A.Y. 2026-2027'), findsOneWidget);
      expect(find.text('Assigned'), findsOneWidget);
      await capturePreview(
        tester,
        find.byKey(_preview),
        'roles_access_history',
      );
    },
  );
  testWidgets(
    'a failed history request offers refresh instead of claiming no history exists',
    (tester) async {
      final users = _Users()..failHistory = true;
      await _pump(tester, _editor(), users: users);
      await tester.tap(find.text('Role history'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load role history. Try again.'),
        findsOneWidget,
      );
      users.failHistory = false;
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned'), findsOneWidget);
    },
  );
  testWidgets(
    'role changes save existing duties and discard restores the saved configuration',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      final container = await _pump(tester, _editor(save: writes.add));
      final toggle = find.byKey(const ValueKey('role-documenter'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(container.read(unsavedChangesProvider), true);
      final save = find.text('Save Role Configuration');
      await tester.ensureVisible(save);
      await tester.tap(save);
      expect(writes.single, {
        'role': 'faculty',
        'is_panelist': true,
        'is_pit_lead': true,
        'pit_lead_year': '1st Year',
        'is_adviser': true,
        'is_documenter': true,
      });
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(tester.widget<ShadSwitch>(toggle).value, false);
      expect(container.read(unsavedChangesProvider), false);
    },
  );
  testWidgets('PIT lead assignment requires choosing a year before saving', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    await _pump(
      tester,
      _editor(
        user: {..._user, 'is_pit_lead': false, 'pit_lead_year': null},
        save: writes.add,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('role-pit-lead')));
    await tester.pumpAndSettle();
    final save = find.text('Save Role Configuration');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Choose a year level for the PIT Lead.'), findsOneWidget);
    expect(writes, isEmpty);
  });
  testWidgets('administrator access still requires explicit confirmation', (
    tester,
  ) async {
    await _pump(tester, _editor());
    await tester.tap(find.byKey(const ValueKey('role-admin')));
    await tester.pumpAndSettle();
    expect(find.text('Grant Administrator Privileges?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ShadSwitch>(find.byKey(const ValueKey('role-admin'))).value,
      false,
    );
  });
  testWidgets(
    'central request sheet approves and moves the decision into history',
    (tester) async {
      final client = _Client();
      await _pump(
        tester,
        PanelistEligibilityView(
          initialTab: 'requests',
          initialRequestId: 42,
          onBack: () {},
        ),
        client: client,
      );
      expect(
        find.byKey(const ValueKey('panelist-request-sheet')),
        findsOneWidget,
      );
      expect(find.text('Relevant project expertise.'), findsWidgets);
      await capturePreview(
        tester,
        find.byKey(_preview),
        'panelist_request_central_sheet',
      );
      await tester.tap(find.text('Approve request'));
      await tester.pumpAndSettle();
      expect(client.patches.single['decision'], 'approved');
      expect(
        find.text('This request has already been reviewed.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close request'));
      await tester.pumpAndSettle();
      expect(find.text('All requests reviewed'), findsOneWidget);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('View decision'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      await capturePreview(
        tester,
        find.byKey(_preview),
        'panelist_access_history',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('central pool sends role editing to the existing RBAC editor', (
    tester,
  ) async {
    int? edited;
    await _pump(
      tester,
      PanelistEligibilityView(onBack: () {}, onEditRoles: (id) => edited = id),
      client: _Client(),
    );
    await tester.tap(find.byKey(const ValueKey('panelist-eligibility-39')));
    expect(edited, 39);
    expect(find.text('Grant eligibility'), findsNothing);
    await capturePreview(
      tester,
      find.byKey(_preview),
      'panelist_access_directory',
    );
  });

  for (final variant in [
    ('panelist_request_mobile', const Size(360, 780), false),
    ('panelist_request_dark', const Size(1366, 1000), true),
  ]) {
    testWidgets('central request sheet is responsive: ${variant.$1}', (
      tester,
    ) async {
      await _pump(
        tester,
        PanelistEligibilityView(
          initialTab: 'requests',
          initialRequestId: 42,
          onBack: () {},
        ),
        size: variant.$2,
        dark: variant.$3,
        client: _Client(),
      );
      await capturePreview(tester, find.byKey(_preview), variant.$1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close request'));
      await tester.pumpAndSettle();
      expect(find.text('Review request'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
