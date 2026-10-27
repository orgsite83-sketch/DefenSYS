import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/grading/rubric_engine_provider.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/defense/defense_stages_provider.dart';
import 'package:defensys/services/grading/grade_center_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/widgets/export/report_catalog.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:defensys/screens/web/admin/audit_compliance/components/audit_report_center_tab.dart';
import 'package:defensys/screens/web/admin/audit_compliance/audit_compliance_screen.dart';
import '../helpers/pump_app.dart';
import 'audit_compliance_redesign_test.dart'
    show
        FakeAuthNotifier,
        FakeAcademicPeriodNotifier,
        FakeStudentTeamsNotifier,
        FakeDefenseStagesNotifier,
        FakeGradeCenterNotifier;

class _Rubrics extends RubricEngineNotifier {
  @override
  RubricEngineState build() => const RubricEngineState(
    scope: 'capstone',
    termContext: 'history',
    search: 'Proposal & Design',
    status: 'published',
  );
}

class _Reports extends ReportsNotifier {
  String? endpoint, format;
  Map<String, String>? params;
  @override
  ReportsState build() => const ReportsState();
  @override
  Future<bool> downloadReport({
    required String endpoint,
    required Map<String, String> queryParams,
    required String defaultFilename,
    String exportFormat = 'pdf',
  }) async {
    this.endpoint = endpoint;
    params = Map.of(queryParams);
    format = exportFormat;
    return true;
  }

  @override
  Future<ReportPreviewData?> fetchReportPreview({
    required String endpoint,
    required Map<String, String> queryParams,
  }) async {
    this.endpoint = endpoint;
    params = Map.of(queryParams);
    return const ReportPreviewData(
      title: 'Rubric Preview',
      subtitle: '',
      generatedAt: '',
      generatedBy: 'Administrator',
      summaryKpis: [],
      columns: [],
      rows: [],
      totalRows: 0,
    );
  }
}

class _Options extends AuthenticatedHttpClient {
  _Options(super.ref);
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async =>
      http.Response(
        jsonEncode({
          'rubrics': [
            {
              'id': 17,
              'label': 'Proposal Quality Guide',
              'scope': 'capstone',
              'semester_id': 3,
            },
          ],
          'semesters': [
            {'id': 3, 'label': '1st Semester, A.Y. 2026-2027'},
          ],
          'teams': [],
          'students': [],
          'stages': [],
          'pit_events': [
            {
              'id': 8,
              'label': 'Prototype showcase',
              'semester_id': 3,
              'year_level': '2nd Year',
              'scope': 'pit',
            },
          ],
        }),
        200,
      );
}

void main() {
  testWidgets(
    'event masterlist configures exports locally with current filters',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reports = _Reports();
      await pumpDefensysWidget(
        tester,
        const ReportExportMenu(
          reportId: 'student-grade-masterlist',
          configureExport: true,
          params: {
            'scope': 'pit',
            'semester_id': '3',
            'pit_event_config_id': '8',
            'year_level': '2nd Year',
            'coverage': 'assessment',
            'detail_level': 'full',
            'search': 'Karen',
          },
        ),
        overrides: [
          authProvider.overrideWith(() => FakeAuthNotifier({'role': 'admin'})),
          academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
          reportsProvider.overrideWith(() => reports),
          authenticatedHttpClientProvider.overrideWith((ref) => _Options(ref)),
        ],
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configure export'));
      await tester.pumpAndSettle();
      expect(find.text('EXPORT FILTERS'), findsOneWidget);
      expect(reports.endpoint, 'grade-masterlist/');
      expect(reports.params?['semester_id'], '3');
      expect(reports.params?['pit_event_config_id'], '8');
      expect(reports.params?['coverage'], 'assessment');
      expect(reports.params?['detail_level'], 'full');
      expect(reports.params?['search'], 'Karen');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'Projects & Concepts appears in the Report Center category and search',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        const SingleChildScrollView(child: AuditReportCenterTab()),
        overrides: [
          authProvider.overrideWith(() => FakeAuthNotifier({'role': 'admin'})),
          academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
          studentTeamsProvider.overrideWith(FakeStudentTeamsNotifier.new),
          defenseStagesProvider.overrideWith(FakeDefenseStagesNotifier.new),
          gradeCenterProvider.overrideWith(FakeGradeCenterNotifier.new),
          reportsProvider.overrideWith(_Reports.new),
        ],
      );
      expect(find.text('PROJECTS & CONCEPTS'), findsOneWidget);
      expect(find.text('Concept Project Register'), findsOneWidget);
    },
  );
  testWidgets('Quick assessment export preserves all-record coverage', (
    tester,
  ) async {
    final reports = _Reports();
    await pumpDefensysWidget(
      tester,
      const ReportExportMenu(
        reportId: 'team-grade',
        params: {'team_id': '12', 'coverage': 'all'},
      ),
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier({'role': 'admin'})),
        academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
        gradeCenterProvider.overrideWith(FakeGradeCenterNotifier.new),
        reportsProvider.overrideWith(() => reports),
      ],
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();
    expect(reports.params?['coverage'], 'all');
    expect(reports.endpoint, 'team-grade/12/');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('Faculty Report Center restores configuration from its URL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reports = _Reports();
    final router = GoRouter(
      initialLocation: reportCenterLocation(
        admin: false,
        reportId: 'rubric-details',
        params: {'rubric_id': '17', 'semester_id': '3', 'scope': 'capstone'},
        source: '/faculty/rubrics',
      ),
      routes: [
        GoRoute(
          path: '/faculty/audit-compliance',
          builder: (_, state) => const Scaffold(body: AuditComplianceScreen()),
        ),
        GoRoute(
          path: '/faculty/rubrics',
          builder: (_, state) => const Scaffold(body: Text('Rubric source')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => FakeAuthNotifier({'role': 'faculty'}),
          ),
          academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
          studentTeamsProvider.overrideWith(FakeStudentTeamsNotifier.new),
          defenseStagesProvider.overrideWith(FakeDefenseStagesNotifier.new),
          gradeCenterProvider.overrideWith(FakeGradeCenterNotifier.new),
          reportsProvider.overrideWith(() => reports),
          authenticatedHttpClientProvider.overrideWith((ref) => _Options(ref)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EXPORT FILTERS'), findsOneWidget);
    expect(find.text('Proposal Quality Guide'), findsOneWidget);
    expect(reports.endpoint, 'rubrics/17/');
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to source'));
    await tester.pumpAndSettle();
    expect(find.text('Rubric source'), findsOneWidget);
  });

  test('Report Center links preserve filters and nested source locations', () {
    final uri = Uri.parse(
      reportCenterLocation(
        admin: true,
        reportId: 'project-records',
        params: {'search': 'AI & IoT', 'stage': 'Concept Proposal'},
        source: '/admin/project-archive?type=capstone',
      ),
    );
    expect(uri.path, '/admin/audit-compliance');
    expect(uri.queryParameters['tab'], 'reports');
    expect(uri.queryParameters['search'], 'AI & IoT');
    expect(
      uri.queryParameters['source'],
      '/admin/project-archive?type=capstone',
    );
  });

  test('Report catalog hides administrator reports from PIT leads', () {
    final ids = ReportCatalog.visible({
      'role': 'faculty',
      'is_pit_lead': true,
    }).map((report) => report.id);
    expect(ids, containsAll(['rubrics', 'project-records', 'pit-event-setup']));
    expect(ids, isNot(contains('academic-periods')));
    expect(ids, isNot(contains('capstone-grade-sheet')));
    expect(
      ReportCatalog.find('rubric-details')!.endpointFor({'rubric_id': '17'}),
      'rubrics/17/',
    );
  });

  testWidgets(
    'Quick Excel and PDF use current source filters without configuration',
    (tester) async {
      final reports = _Reports();
      await pumpDefensysWidget(
        tester,
        const ReportExportMenu(reportId: 'rubrics'),
        overrides: [
          authProvider.overrideWith(() => FakeAuthNotifier({'role': 'admin'})),
          academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
          rubricEngineProvider.overrideWith(_Rubrics.new),
          reportsProvider.overrideWith(() => reports),
        ],
      );
      for (final choice in ['Export Excel', 'Export PDF']) {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        expect(find.text('Report Center'), findsOneWidget);
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
        expect(reports.endpoint, 'rubrics/');
        expect(reports.format, choice == 'Export Excel' ? 'xlsx' : 'pdf');
        expect(reports.params, {
          'scope': 'capstone',
          'term_context': 'history',
          'search': 'Proposal & Design',
          'status': 'published',
        });
        expect(find.text('EXPORT FILTERS'), findsNothing);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'Contextual Report Center opens the selected rubric and returns to source',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reports = _Reports();
      final router = GoRouter(
        initialLocation: '/admin/rubrics',
        routes: [
          GoRoute(
            path: '/admin/rubrics',
            builder: (_, state) => const Scaffold(
              body: ReportExportMenu(
                reportId: 'rubric-details',
                params: {
                  'rubric_id': '17',
                  'semester_id': '3',
                  'term_context': '',
                  'search': '',
                  'status': '',
                },
              ),
            ),
          ),
          GoRoute(
            path: '/admin/audit-compliance',
            builder: (_, state) => Scaffold(
              body: SingleChildScrollView(
                child: AuditReportCenterTab(
                  reportQuery: state.uri.queryParameters,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              () => FakeAuthNotifier({'role': 'admin'}),
            ),
            academicPeriodProvider.overrideWith(FakeAcademicPeriodNotifier.new),
            studentTeamsProvider.overrideWith(FakeStudentTeamsNotifier.new),
            defenseStagesProvider.overrideWith(FakeDefenseStagesNotifier.new),
            gradeCenterProvider.overrideWith(FakeGradeCenterNotifier.new),
            rubricEngineProvider.overrideWith(_Rubrics.new),
            reportsProvider.overrideWith(() => reports),
            authenticatedHttpClientProvider.overrideWith(
              (ref) => _Options(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report Center'));
      await tester.pumpAndSettle();
      expect(find.text('EXPORT FILTERS'), findsOneWidget);
      expect(find.text('Proposal Quality Guide'), findsOneWidget);
      expect(reports.endpoint, 'rubrics/17/');
      expect(reports.params?['semester_id'], '3');
      expect(
        find.text('Selected record unavailable for these filters'),
        findsNothing,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Rubric Catalog'), findsOneWidget);
      expect(find.text('Project Archive Register'), findsOneWidget);
      await tester.tap(find.text('Back to source'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/rubrics');
    },
  );
}
