import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:defensys/widgets/table/defensys_segmented_control.dart';
import 'package:defensys/screens/web/admin/audit_compliance/components/event_details_panel.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/audit_compliance/audit_compliance_screen.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/system_audit_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/defense/defense_stages_provider.dart';
import 'package:defensys/services/grading/grade_center_provider.dart';
import 'package:defensys/services/admin/reports_provider.dart';

import '../helpers/pump_app.dart';

class FakeAuthNotifier extends AuthNotifier {
  final Map<String, dynamic> _user;

  FakeAuthNotifier(this._user);

  @override
  AuthState build() {
    return AuthState(isRestoring: false, user: _user, token: 'fake_jwt_token');
  }
}

class FakeSystemAuditNotifier extends SystemAuditNotifier {
  int reviewUpdateCount = 0;
  int fetchCount = 0;
  final SystemAuditState _initialState;

  FakeSystemAuditNotifier(this._initialState);

  @override
  SystemAuditState build() => _initialState;

  @override
  Future<void> fetch({int? page}) async {
    fetchCount++;
  }

  @override
  Future<bool> updateReviewStatus(
    int logId,
    String reviewStatus, {
    String? reason,
  }) async {
    reviewUpdateCount++;
    return false;
  }
}

class FakeAuditReportsNotifier extends ReportsNotifier {
  String? lastFormat;
  String? lastFilename;
  String? lastEndpoint;
  Map<String, String>? lastParams;

  @override
  ReportsState build() => const ReportsState();

  @override
  Future<bool> downloadReport({
    required String endpoint,
    required Map<String, String> queryParams,
    required String defaultFilename,
    String exportFormat = 'pdf',
  }) async {
    lastFormat = exportFormat;
    lastFilename = defaultFilename;
    lastEndpoint = endpoint;
    lastParams = Map.of(queryParams);
    return true;
  }
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeStudentTeamsNotifier extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();

  @override
  Future<void> fetchTeams({
    String? historyIntake,
    String? historyPhase,
    String? historyStage,
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearYearLevel = false,
    bool clearEventName = false,
    String? successMessage,
  }) async {}
}

class FakeDefenseStagesNotifier extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() => const DefenseStagesState();

  @override
  Future<void> fetchStages({
    String? scope,
    String? intake,
    String? phase,
    String? stage,
    String? successMessage,
  }) async {}
}

class FakeGradeCenterNotifier extends GradeCenterNotifier {
  @override
  GradeCenterState build() => const GradeCenterState();

  @override
  Future<void> fetchGrades({
    String? historySemester,
    String? search,
    String? level,
    String? stage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

void main() {
  const logs = <Map<String, dynamic>>[
    {
      'id': 45,
      'actor_name': 'Admin User',
      'action': 'rubric.create',
      'category': 'rubrics',
      'category_label': 'Rubrics',
      'target_type': 'Rubric',
      'target_id': '9',
      'target_label': 'Capstone Final Defense Rubric',
      'old_values': <String, dynamic>{},
      'new_values': {'name': 'Capstone Final Defense Rubric'},
      'reason': 'Configured evaluation criteria',
      'review_status': 'reviewed',
      'reviewed_by_name': 'Historical Reviewer',
      'review_history': [
        {'to_status': 'reviewed', 'reviewer_name': 'Historical Reviewer'},
      ],
      'created_at': '2026-08-30T07:38:00Z',
    },
    {
      'id': 44,
      'actor_name': 'Admin User',
      'action': 'rubric.update',
      'category': 'rubrics',
      'category_label': 'Rubrics',
      'target_type': 'Rubric',
      'target_id': '9',
      'target_label': 'Capstone Final Defense Rubric',
      'old_values': {'name': 'Original Rubric'},
      'new_values': {'name': 'Revised Rubric'},
      'reason': 'Clarified criteria',
      'review_status': 'needs_review',
      'evidence': {
        'label': 'Before and after captured',
        'reason_required': true,
      },
      'created_at': '2026-08-30T07:39:00Z',
    },
    {
      'id': 43,
      'actor_name': 'Admin User',
      'action': 'rubric.delete',
      'category': 'rubrics',
      'category_label': 'Rubrics',
      'target_type': 'Rubric',
      'target_id': '8',
      'target_label': 'Deleted Rubric',
      'old_values': {'name': 'Deleted Rubric'},
      'new_values': {'deleted': true},
      'reason': 'Deprecated criteria',
      'review_status': 'needs_review',
      'created_at': '2026-08-30T07:40:00Z',
    },
  ];
  const initialState = SystemAuditState(
    logs: logs,
    totalCount: 3,
    options: {
      'categories': [
        {'value': 'rubrics', 'label': 'Rubrics'},
      ],
      'actions': ['rubric.create', 'rubric.update', 'rubric.delete'],
    },
  );

  Future<FakeSystemAuditNotifier> pumpWorkspace(
    WidgetTester tester, {
    SystemAuditState state = initialState,
    Map<String, dynamic> user = const {'id': 1, 'role': 'admin'},
    FakeAuditReportsNotifier? reports,
    Widget child = const AuditComplianceScreen(),
    Size size = const Size(1400, 1200),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifier = FakeSystemAuditNotifier(state);
    await pumpDefensysWidget(
      tester,
      child,
      theme: theme,
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier(user)),
        systemAuditProvider.overrideWith(() => notifier),
        academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
        studentTeamsProvider.overrideWith(FakeStudentTeamsNotifier.new),
        defenseStagesProvider.overrideWith(FakeDefenseStagesNotifier.new),
        gradeCenterProvider.overrideWith(FakeGradeCenterNotifier.new),
        if (reports != null) reportsProvider.overrideWith(() => reports),
      ],
    );
    return notifier;
  }

  Future<void> openLogs(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('logs-tab')));
    await tester.pumpAndSettle();
  }

  test(
    'Logs default to all activity for admin and assigned PIT year for leads',
    () {
      for (final user in [
        {'id': 1, 'role': 'admin'},
        {
          'id': 2,
          'role': 'faculty',
          'is_pit_lead': true,
          'pit_lead_year': '1st Year',
        },
      ]) {
        final container = ProviderContainer(
          overrides: [authProvider.overrideWith(() => FakeAuthNotifier(user))],
        );
        final state = container.read(systemAuditProvider);
        expect(state.track, user['role'] == 'admin' ? '' : 'pit');
        expect(state.yearLevel, user['role'] == 'admin' ? '' : '1st Year');
        container.dispose();
      }
    },
  );

  testWidgets('Report Center is first and selected without fetching logs', (
    tester,
  ) async {
    final notifier = await pumpWorkspace(tester);
    final tabs = tester.widget<DefensysSegmentedControl<int>>(
      find.byType(DefensysSegmentedControl<int>),
    );
    expect(tabs.items.map((item) => item.label), ['Report Center', 'Logs']);
    expect(tabs.value, 0);
    expect(find.text('Choose what you need to report.'), findsOneWidget);
    expect(find.text('Activity register'), findsNothing);
    expect(notifier.fetchCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Logs show activity and optional evidence details without review controls',
    (tester) async {
      final notifier = await pumpWorkspace(tester);
      await openLogs(tester);
      expect(notifier.fetchCount, 1);
      expect(find.text('Activity register'), findsOneWidget);
      expect(find.byType(EventDetailsPanel), findsNothing);
      for (final label in [
        'Review coverage',
        'Needs Review',
        'Reviewed',
        'REVIEW STATUS',
        'Human review',
        'Mark as reviewed',
        'Reopen review',
      ]) {
        expect(find.text(label), findsNothing);
      }
      final register = tester.widget<DataTable>(find.byType(DataTable).first);
      expect(register.rows.every((row) => !row.selected), isTrue);
      await tester.tap(find.text('Rubric created').first);
      await tester.pumpAndSettle();
      expect(find.text('Event Details'), findsOneWidget);
      expect(find.text('Configured evaluation criteria'), findsOneWidget);
      expect(find.text('Resource Details'), findsOneWidget);
      expect(find.text('Historical Reviewer'), findsNothing);
      expect(
        notifier.state.logs.first['review_history'],
        logs.first['review_history'],
      );
      await tester.ensureVisible(find.byTooltip('Close event details'));
      await tester.tap(find.byTooltip('Close event details'));
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailsPanel), findsNothing);
      expect(notifier.state.selectedLog, isNull);
      expect(notifier.reviewUpdateCount, 0);
    },
  );

  testWidgets('Log polling runs only while the Logs tab is active', (
    tester,
  ) async {
    final notifier = await pumpWorkspace(tester);
    await tester.pump(const Duration(seconds: 31));
    expect(notifier.fetchCount, 0);
    await openLogs(tester);
    expect(notifier.fetchCount, 1);
    await tester.pump(const Duration(seconds: 31));
    expect(notifier.fetchCount, 2);
    await tester.tap(find.byKey(const ValueKey('report-center-tab')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));
    expect(notifier.fetchCount, 2);
  });

  for (final format in ['xlsx', 'pdf']) {
    testWidgets('Logs export $format preserves activity filters', (
      tester,
    ) async {
      final reports = FakeAuditReportsNotifier();
      await pumpWorkspace(
        tester,
        reports: reports,
        state: initialState.copyWith(
          category: 'rubrics',
          action: 'rubric.update',
          search: 'rubric',
          startDate: '2026-08-01',
          endDate: '2026-08-31',
          track: 'pit',
          yearLevel: '2nd Year',
        ),
      );
      await openLogs(tester);
      await tester.tap(find.byTooltip('Export Options'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(format == 'xlsx' ? 'Export Excel' : 'Export PDF'),
      );
      await tester.pumpAndSettle();
      expect(reports.lastFormat, format);
      expect(reports.lastEndpoint, 'audit-trail/');
      expect(reports.lastFilename, 'DefenSYS_Audit_Register.$format');
      expect(reports.lastParams, {
        'category': 'rubrics',
        'action': 'rubric.update',
        'search': 'rubric',
        'start_date': '2026-08-01',
        'end_date': '2026-08-31',
        'track': 'pit',
        'year_level': '2nd Year',
      });
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'Scope filters retain System, all activity, and PIT year access',
    (tester) async {
      final notifier = await pumpWorkspace(tester);
      await openLogs(tester);
      for (final scope in [
        ('System & other activity', 'system', ''),
        ('All activity', '', ''),
        ('PIT – 2nd Year', 'pit', '2nd Year'),
      ]) {
        await tester.tap(find.text('More Filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(scope.$1));
        await tester.tap(find.text('Apply Filter'));
        await tester.pumpAndSettle();
        expect(notifier.state.track, scope.$2);
        expect(notifier.state.yearLevel, scope.$3);
      }
    },
  );

  testWidgets('PIT Lead logs remain locked to the assigned year', (
    tester,
  ) async {
    final notifier = await pumpWorkspace(
      tester,
      user: {
        'id': 2,
        'role': 'faculty',
        'is_pit_lead': true,
        'pit_lead_year': '1st Year',
      },
      state: initialState.copyWith(track: 'pit', yearLevel: '1st Year'),
    );
    await openLogs(tester);
    await tester.tap(find.text('More Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Capstone Only'), findsNothing);
    expect(
      find.textContaining('limited to your assigned year'),
      findsOneWidget,
    );
    expect(notifier.state.track, 'pit');
    expect(notifier.state.yearLevel, '1st Year');
  });

  testWidgets('Update and deletion snapshots remain available', (tester) async {
    await pumpWorkspace(tester);
    await openLogs(tester);
    await tester.tap(find.text('Rubric updated').first);
    await tester.pumpAndSettle();
    expect(find.text('Original Rubric'), findsOneWidget);
    expect(find.text('Revised Rubric'), findsOneWidget);
    expect(find.text('Before and after captured'), findsOneWidget);
    await tester.ensureVisible(find.text('Rubric deleted').first);
    await tester.tap(find.text('Rubric deleted').first);
    await tester.pumpAndSettle();
    expect(find.text('This resource has been deleted'), findsOneWidget);
    expect(find.text('Last Known State'), findsOneWidget);
  });

  testWidgets('Raw event payload remains available from the details menu', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    await openLogs(tester);
    await tester.tap(find.text('Rubric created').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('More options'));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as reviewed'), findsNothing);
    expect(find.text('Open Rubric'), findsOneWidget);
    await tester.tap(find.text('View Raw JSON'));
    await tester.pumpAndSettle();
    expect(find.text('Raw Log Payload'), findsOneWidget);
    expect(find.text('Copy JSON'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'An explicit Logs deep link opens Logs instead of the default report tab',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/?tab=logs',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: AuditComplianceScreen()),
          ),
        ],
      );
      addTearDown(router.dispose);
      final notifier = await pumpWorkspace(
        tester,
        child: MaterialApp.router(routerConfig: router),
      );
      expect(find.text('Activity register'), findsOneWidget);
      expect(find.text('Choose what you need to report.'), findsNothing);
      expect(notifier.fetchCount, 1);
    },
  );

  testWidgets('Logs reflow in dark mode on a small display', (tester) async {
    await pumpWorkspace(
      tester,
      size: const Size(600, 1000),
      theme: AppTheme.mistDarkTheme,
    );
    await openLogs(tester);
    expect(find.text('Activity register'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Report Center opened from Logs returns to the Logs tab', (
    tester,
  ) async {
    Uri? reportDestination;
    final router = GoRouter(
      initialLocation: '/admin/audit-compliance',
      routes: [
        GoRoute(
          path: '/admin/audit-compliance',
          builder: (context, state) {
            if (state.uri.queryParameters['tab'] == 'reports') {
              reportDestination = state.uri;
              return const Scaffold(body: Text('Selected report'));
            }
            return const Scaffold(body: AuditComplianceScreen());
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpWorkspace(
      tester,
      child: MaterialApp.router(routerConfig: router),
    );
    await openLogs(tester);
    await tester.tap(find.byTooltip('Export Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report Center').last);
    await tester.pumpAndSettle();
    expect(reportDestination?.queryParameters['report'], 'audit-trail');
    final source = Uri.parse(reportDestination!.queryParameters['source']!);
    expect(source.path, '/admin/audit-compliance');
    expect(source.queryParameters['tab'], 'logs');
  });

  testWidgets('Selecting a log brings its evidence header into view', (
    tester,
  ) async {
    await pumpWorkspace(tester, size: const Size(600, 650));
    await openLogs(tester);
    await tester.ensureVisible(find.text('Rubric updated').first);
    await tester.tap(find.text('Rubric updated').first);
    await tester.pumpAndSettle();
    final detailsTop = tester.getTopLeft(find.text('Event Details')).dy;
    expect(detailsTop, greaterThanOrEqualTo(0));
    expect(detailsTop, lessThan(650));
    expect(tester.takeException(), isNull);
  });
}
