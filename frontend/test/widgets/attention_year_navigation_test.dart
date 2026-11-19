import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/navigation/admin_attention_context.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/user_management/user_management_screen.dart';
import 'package:defensys/screens/web/admin/user_management/components/students_enrollment_view.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/student_batch_enrollment_hub_view.dart';
import 'package:defensys/screens/web/admin/student_teams/student_teams_screen.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/network/connectivity_provider.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/admin_overview_scope_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/academic/admin_attention_students.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';
import '../helpers/auth_test_overrides.dart';
import 'defensys_admin_shell_test.dart' show FakeNotificationsNotifier;

const _term = {'id': 2, 'label': '2nd Semester', 'school_year': '2026-2027'};

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

final _years = [
  for (final year in AdminAttentionContext.years)
    {
      'year_level': year,
      'enrolled': 12,
      'known_pending': year == '4th Year' ? 3 : 0,
      'without_team': year == '3rd Year' ? 2 : 0,
      'team_scope': year == '1st Year' || year == '2nd Year'
          ? 'pit'
          : 'capstone',
      'team_state': 'available',
      'can_assign': year == '3rd Year',
    },
];

class _Periods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() =>
      const AcademicPeriodState(activeSemester: _term);
  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
  void change() => state = const AcademicPeriodState(activeSemester: {'id': 3});
}

class _Records extends StudentAcademicRecordsNotifier {
  _Records({this.emptyYears = const []});
  final List<String> emptyYears;

  @override
  StudentAcademicRecordsState build() => StudentAcademicRecordsState(
    activeSemester: _term,
    counts: {
      'year_summary': _years,
      'enrollment': {
        'semester_id': 2,
        'enrolled': (4 - emptyYears.length) * 12,
        'pending_continuations': 3,
        'by_year': [
          for (final row in _years)
            {...row, if (emptyYears.contains(row['year_level'])) 'enrolled': 0},
        ],
      },
    },
  );
  @override
  Future<void> fetchRecords({
    String? search,
    String? schoolYear,
    String? semester,
    String? successMessage,
  }) async {}
}

class _Users extends UserManagementNotifier {
  int imports = 0;
  @override
  UserManagementState build() => const UserManagementState();
  @override
  Future<void> fetchUsers({
    String? search,
    String? role,
    String? successMessage,
  }) async {}
  @override
  Future<List<Map<String, dynamic>>> previewEnrollmentSections(
    List<Map<String, dynamic>> students,
    int semesterId, {
    bool unifiedEnrollment = false,
  }) async => [
    for (final row in students)
      {
        'id_number': row['id_number'],
        'section': 'BSIT-4A',
        'source': 'explicit',
        'status_code': 'existing_student',
        'blocking': false,
      },
  ];
  @override
  Future<bool> bulkImport(
    List<Map<String, dynamic>> rows, {
    Map<String, dynamic>? studentContext,
  }) async {
    imports++;
    return true;
  }
}

class _Evaluators extends ExternalEvaluatorNotifier {
  @override
  Future<bool> fetch() async => true;
}

class _Draft extends StudentBatchDraftNotifier {
  @override
  StudentBatchDraftState build() => const StudentBatchDraftState(
    freshParsedStudents: [
      {
        'id_number': 'existing-draft',
        'first_name': 'Previous',
        'last_name': 'Draft',
        'year_level': '1st Year',
        'role': 'student',
      },
    ],
  );
}

class _Teams extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState(
    activeSemester: _term,
    canCreateCapstoneTeams: true,
    capstoneMode: 'capstone_1_intake',
  );
  @override
  Future<void> fetchTeams({
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? historyIntake,
    String? historyPhase,
    String? historyStage,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearEventName = false,
    bool clearYearLevel = false,
    String? successMessage,
  }) async {}
}

class _GroupDashboard extends DashboardNotifier {
  _GroupDashboard() : super('admin');
  @override
  DashboardState build() => DashboardState(
    data: {
      'overview': {
        'semester_id': 2,
        'action_items': [
          for (final id in [
            'enrollment:2:year:2nd Year',
            'enrollment:2:year:4th Year',
            'pending_panelist_requests',
          ])
            {'id': id, 'target_section': 'userManagement'},
        ],
      },
    },
  );
  void resolveOne() => state = DashboardState(
    data: {
      'overview': {
        'semester_id': 2,
        'action_items': [
          for (final id in [
            'enrollment:2:year:4th Year',
            'pending_panelist_requests',
          ])
            {'id': id, 'target_section': 'userManagement'},
        ],
      },
    },
  );
}

class _Client implements AuthenticatedHttpClient {
  final requested = <Uri>[];
  bool fail = false, resolved = false;
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    requested.add(uri);
    if (fail) {
      return http.Response(
        jsonEncode({'detail': 'Could not load students.'}),
        503,
      );
    }
    final year = uri.queryParameters['year_level'];
    return http.Response(
      jsonEncode({
        'semester_id': 2,
        'year_level': year,
        'page': 1,
        'count': resolved ? 0 : 3,
        'state': 'available',
        'students': resolved
            ? []
            : [
                for (var i = 0; i < 3; i++)
                  {
                    'id': i + 1,
                    'username': 'pending-$i',
                    'first_name': 'Student',
                    'last_name': '$i',
                    'name': 'Student $i',
                    'section': 'BSIT-${year == '3rd Year' ? '3' : '4'}A',
                    'year_level': year,
                  },
              ],
      }),
      200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<(GoRouter, ProviderContainer, _Client)> open(
    WidgetTester tester, {
    String? initial,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts();
    final client = _Client();
    final router = GoRouter(
      initialLocation: initial ?? AdminRoutes.users,
      routes: [
        GoRoute(
          path: AdminRoutes.users,
          builder: (_, state) => Scaffold(
            body: UserManagementScreen(
              initialEnrollment:
                  state.uri.queryParameters['view'] == 'enrollment',
              attentionContext: AdminAttentionContext.fromQuery(
                state.uri.queryParameters,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '${AdminRoutes.studentTeams}/creation',
          builder: (_, state) => Scaffold(
            body: StudentTeamsScreen(
              initialBulkImport: true,
              attentionContext: AdminAttentionContext.fromQuery(
                state.uri.queryParameters,
              ),
            ),
          ),
        ),
        GoRoute(
          path: AdminRoutes.overview,
          builder: (_, __) =>
              const Scaffold(body: Text('Overview destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...authTestOverrides(),
          connectivityProvider.overrideWith(_Online.new),
          academicPeriodProvider.overrideWith(_Periods.new),
          studentAcademicRecordsProvider.overrideWith(_Records.new),
          userManagementProvider.overrideWith(_Users.new),
          externalEvaluatorProvider.overrideWith(_Evaluators.new),
          studentBatchDraftProvider.overrideWith(_Draft.new),
          studentTeamsProvider.overrideWith(_Teams.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp.router(
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      router,
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)),
      client,
    );
  }

  testWidgets(
    'year enrollment opens pending records and stages review without replacing the draft or importing',
    (tester) async {
      final (_, container, client) = await open(
        tester,
        initial: const AdminAttentionContext(
          kind: 'enrollment',
          year: '4th Year',
          semesterId: 2,
        ).location,
      );
      expect(find.byType(StudentBatchEnrollmentHubView), findsOneWidget);
      expect(find.byType(AdminAttentionStudents), findsOneWidget);
      expect(client.requested.last.queryParameters['year_level'], '4th Year');
      expect(client.requested.last.queryParameters['attention'], 'enrollment');
      final review = find.text('Add this page to enrollment review');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      final rows = container
          .read(studentBatchDraftProvider)
          .freshParsedStudents;
      expect(
        rows.map((r) => r['id_number']),
        containsAll(['existing-draft', 'pending-0', 'pending-1', 'pending-2']),
      );
      expect(
        (container.read(userManagementProvider.notifier) as _Users).imports,
        0,
      );
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byType(StudentBatchEnrollmentHubView),
        'attention-enrollment-review',
        viewport: true,
      );
    },
  );

  testWidgets(
    'team gap opens import with affected students and guards a semester change',
    (tester) async {
      final (_, container, client) = await open(
        tester,
        initial: const AdminAttentionContext(
          kind: 'team_assignment',
          year: '3rd Year',
          semesterId: 2,
          fromOverview: true,
        ).location,
      );
      expect(find.text('Bulk Import Student Teams'), findsOneWidget);
      expect(find.text('Student 0'), findsOneWidget);
      expect(
        client.requested.last.queryParameters['attention'],
        'team_assignment',
      );
      expect(find.text('Add this page to enrollment review'), findsNothing);
      await capturePreview(
        tester,
        find.byType(StudentTeamsScreen),
        'attention-team-import',
        viewport: true,
      );
      (container.read(academicPeriodProvider.notifier) as _Periods).change();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This task context is unavailable. Return to Overview and refresh.',
        ),
        findsOneWidget,
      );
      expect(find.text('Bulk Import Student Teams'), findsNothing);
      await tester.tap(find.text('Back to Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Overview destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('year team task opens the actual filtered import destination', (
    tester,
  ) async {
    final (router, _, client) = await open(
      tester,
      initial: const AdminAttentionContext(
        kind: 'team_assignment',
        year: '3rd Year',
        semesterId: 2,
      ).location,
    );
    expect(
      router.routeInformationProvider.value.uri.path,
      '${AdminRoutes.studentTeams}/creation',
    );
    expect(
      router.routeInformationProvider.value.uri.queryParameters['tab'],
      'import',
    );
    expect(client.requested.last.queryParameters['year_level'], '3rd Year');
    expect(find.text('Student 0'), findsOneWidget);
    expect(find.text('Bulk Import Student Teams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar counts year task groups and approvals in both scopes and refreshes',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts();
      await pumpDefensysWidget(
        tester,
        DefensysAdminShell(
          activeSection: DefensysAdminSection.userManagement,
          activeSemesterLabel: '2nd Semester · 2026-2027',
          onNavigate: (_) {},
          onLogout: () {},
          child: StudentsEnrollmentView(onOpenBulkImport: () {}),
        ),
        overrides: [
          ...authTestOverrides(),
          academicPeriodProvider.overrideWith(_Periods.new),
          studentAcademicRecordsProvider.overrideWith(_Records.new),
          dashboardProvider('admin').overrideWith(_GroupDashboard.new),
          connectivityProvider.overrideWith(_Online.new),
          notificationsProvider.overrideWith2(
            (workspace) => FakeNotificationsNotifier(workspace),
          ),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DefensysAdminShell)),
      );
      for (final scope in ['capstone', 'pit']) {
        container.read(adminOverviewScopeProvider.notifier).select(scope);
        await tester.pumpAndSettle();
        expect(find.byTooltip('3 administrative tasks'), findsOneWidget);
      }
      await capturePreview(
        tester,
        find.byType(DefensysAdminShell),
        'attention-sidebar-year-counts',
        viewport: true,
      );
      (container.read(dashboardProvider('admin').notifier) as _GroupDashboard)
          .resolveOne();
      await tester.pumpAndSettle();
      expect(find.byTooltip('2 administrative tasks'), findsOneWidget);
      expect(find.byTooltip('3 administrative tasks'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh failure is retryable and confirmed resolution clears the task list',
    (tester) async {
      final (_, container, client) = await open(
        tester,
        initial: const AdminAttentionContext(
          kind: 'enrollment',
          year: '4th Year',
          semesterId: 2,
          fromOverview: true,
        ).location,
      );
      client.fail = true;
      container.read(dataRefreshProvider.notifier).markChanged([
        DataArea.academicRecords,
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Could not load students.'), findsOneWidget);
      expect(find.text('No students remain in this task.'), findsNothing);
      client.fail = false;
      client.resolved = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No students remain in this task.'), findsOneWidget);
      expect(find.text('Student 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 800.0, 1280.0, 1920.0]) {
    for (final dark in [false, true]) {
      testWidgets('compact enrollment warning at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (width < 600) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StudentsEnrollmentView(onOpenBulkImport: () {}),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          overrides: [
            ...authTestOverrides(),
            academicPeriodProvider.overrideWith(_Periods.new),
            studentAcademicRecordsProvider.overrideWith(
              () => _Records(emptyYears: ['3rd Year', '4th Year']),
            ),
          ],
        );
        expect(
          find.text(
            'No students are enrolled in 3rd Year and 4th Year this semester. '
            '3 continuing students still need enrollment.',
          ),
          findsOneWidget,
        );
        expect(find.text('Enrollment by year'), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(StudentsEnrollmentView),
          'enrollment-warning-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }
}
