import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:defensys/screens/web/admin/audit_compliance/components/audit_report_center_tab.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/defense/defense_stages_provider.dart';
import 'package:defensys/services/grading/grade_center_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/widgets/export/defensys_live_data_preview_pane.dart';
import 'package:defensys/widgets/export/defensys_document_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

const _team = <String, dynamic>{
  'id': 12,
  'name': 'Team Preview',
  'project_title': 'Preview Project',
  'section': 'BSIT-4A',
  'level': 'capstone',
  'year_level': '4th Year',
  'adviser_name': 'Test Adviser',
  'leader': {'id': 3, 'first_name': 'Student', 'last_name': 'Leader'},
  'members': <dynamic>[],
};

const _pitTeam = <String, dynamic>{
  'id': 16, 'name': 'PIT Preview', 'project_title': 'PIT Project',
  'section': 'BSIT-2A', 'level': '2nd Year PIT', 'year_level': '2nd Year',
  'leader': {'id': 5, 'name': 'PIT Student', 'username': 'pit-student'},
  'members': <dynamic>[],
};

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    user: {'role': 'admin', 'first_name': 'Test', 'last_name': 'Admin'},
  );
}

class _PitLeadAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    user: {
      'role': 'faculty', 'is_pit_lead': true,
      'pit_lead_year': '2nd Year', 'first_name': 'PIT', 'last_name': 'Lead',
    },
  );
}

class _Periods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();
  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class _Teams extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState(teams: [_team, _pitTeam]);
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
    bool clearEventName = false,
    bool clearYearLevel = false,
    String? successMessage,
  }) async {}
}

class _Stages extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() => const DefenseStagesState();
  @override
  Future<void> fetchStages({String? scope,
    String? intake,
    String? phase,
    String? stage,
    String? successMessage,}) async {}
}

class _Grades extends GradeCenterNotifier {
  @override
  GradeCenterState build() => const GradeCenterState();
  @override
  Future<void> fetchGrades({
    String? historySemester,
    String? search,
    String? yearLevel,
    String? status,
    String? scope,
    String? successMessage,
  }) async {}
}

class _PreviewClient extends AuthenticatedHttpClient {
  _PreviewClient(super.ref, this.client);
  final http.Client client;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      client.get(url, headers: headers);
}

http.Response _response(String title) => http.Response(
  jsonEncode({
    'title': title,
    'subtitle': '',
    'generated_at': '',
    'columns': [
      {'key': 'score', 'label': 'Score'},
    ],
    'rows': [
      {'score': 90},
    ],
    'summary_kpis': <dynamic>[],
    'assessments': [
      {'id': 21, 'scope': 'capstone', 'stage_label': 'Concept Proposal'},
      {'id': 22, 'scope': 'capstone', 'stage_label': 'Project Proposal'},
    ],
  }),
  200,
);

Future<void> _openReport(
  WidgetTester tester,
  http.Client client, {
  bool openDialog = true,
  bool pitLead = false,
  double viewportWidth = 1500,
}) async {
  final fonts = FontLoader('Inter');
  fonts.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  fonts.addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
  await fonts.load();
  tester.view.physicalSize = Size(viewportWidth, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(pitLead ? _PitLeadAuth.new : _Auth.new),
        academicPeriodProvider.overrideWith(_Periods.new),
        studentTeamsProvider.overrideWith(_Teams.new),
        defenseStagesProvider.overrideWith(_Stages.new),
        gradeCenterProvider.overrideWith(_Grades.new),
        authenticatedHttpClientProvider.overrideWith(
          (ref) => _PreviewClient(ref, client),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: const Scaffold(
          body: SingleChildScrollView(child: AuditReportCenterTab()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!openDialog) return;
  await tester.tap(find.text('Team Grade Report Card'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Team Preview'));
  await tester.pumpAndSettle();
}

Future<void> _toggleSignatures(WidgetTester tester, String badge) async {
  await tester.tap(find.text(badge));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byType(Switch));
  await tester.pump();
  await tester.tap(find.text('Apply Signatories'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('PDF and Excel select their preview without view tabs', (tester,) async {
    final client = MockClient((request) async => _response('Format Preview'));
    addTearDown(client.close);
    await _openReport(tester, client);

    expect(find.text('PDF Document'), findsOneWidget);
    expect(find.text('Excel Spreadsheet'), findsOneWidget);
    expect(find.text('CSV File'), findsNothing);
    expect(find.text('Word Document'), findsNothing);
    expect(find.text('Document Sheet'), findsNothing);
    expect(find.text('Data Table'), findsNothing);
    expect(find.byType(DefensysDocumentSheet), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);

    await tester.tap(find.text('Excel Spreadsheet'));
    await tester.pumpAndSettle();
    expect(find.byType(DefensysDocumentSheet), findsNothing);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Filter table records...'), findsOneWidget);
    expect(find.text('Download XLSX Export'), findsOneWidget);

    await tester.tap(find.text('PDF Document'));
    await tester.pumpAndSettle();
    expect(find.byType(DefensysDocumentSheet), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Download PDF Export'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT Lead sees the same report list locked to the assigned year', (tester) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path.endsWith('assessment-candidates/')) {
        return http.Response(jsonEncode({'teams': [_pitTeam], 'students': [], 'student_contexts': {},}), 200,);
      }
      return _response('PIT Lead Preview');
    });
    addTearDown(client.close);
    await _openReport(tester, client, openDialog: false, pitLead: true);
    expect(find.text('PIT reports · 2nd Year'), findsOneWidget);
    expect(find.text('Capstone Stage Grade Sheet'), findsNothing);
    expect(find.text('PIT Event Grade Sheet'), findsOneWidget);
    expect(find.text('User Directory'), findsNothing);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defense operations & rosters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Capstone Stage Grade Sheet'), findsNothing);
    expect(find.text('PIT Event Grade Sheet'), findsOneWidget);
    await tester.tap(find.text('Team Grade Report Card'));
    await tester.pumpAndSettle();
    expect(find.text('Team Preview'), findsNothing);
    expect(find.text('PIT Preview'), findsOneWidget);
    await tester.tap(find.text('PIT Preview'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['scope'], 'pit');
    expect(find.text('Latest recorded event'), findsOneWidget);
    expect(tester.takeException(), isNull);
  },);

  testWidgets('PIT Lead roster keeps its year after resetting filters', (tester,) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path.endsWith('assessment-candidates/')) {
        return http.Response(jsonEncode({'teams': [_pitTeam], 'students': [], 'student_contexts': {},}), 200,);
      }
      return _response('PIT Roster Preview');
    });
    addTearDown(client.close);
    await _openReport(tester, client, openDialog: false, pitLead: true);
    await tester.ensureVisible(find.text('Team Roster Report'));
    await tester.tap(find.text('Team Roster Report'));
    await tester.pumpAndSettle();
    Uri rosterRequest() => requests.where((url) => url.path.endsWith('/team-roster/')).last;
    expect(rosterRequest().queryParameters['level'], 'pit');
    expect(rosterRequest().queryParameters['year_level'], '2nd Year');
    expect(find.text('1st Year'), findsNothing);
    expect(find.text('3rd Year'), findsNothing);
    final reset = find.text('Reset All Filters');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(rosterRequest().queryParameters['level'], 'pit');
    expect(rosterRequest().queryParameters['year_level'], '2nd Year');
    expect(tester.takeException(), isNull);
  });

  testWidgets('scope filters reports and carries PIT into the team preview', (tester,) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path.endsWith('assessment-candidates/')) {
        return http.Response(jsonEncode({'teams': [_pitTeam], 'students': [], 'student_contexts': {},}), 200,);
      }
      return _response('PIT Preview');
    });
    addTearDown(client.close);
    await _openReport(tester, client, openDialog: false);
    await tester.tap(find.text('PIT').first);
    await tester.pumpAndSettle();
    expect(find.text('Capstone Stage Grade Sheet'), findsNothing);
    expect(find.text('PIT Event Grade Sheet'), findsOneWidget);
    await tester.tap(find.text('Team Grade Report Card'));
    await tester.pumpAndSettle();
    expect(find.text('Team Preview'), findsNothing);
    await tester.tap(find.text('PIT Preview'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['scope'], 'pit');
    expect(requests.last.queryParameters['coverage'], 'latest');
    expect(find.text('Latest recorded event'), findsOneWidget);
  });

  testWidgets('team coverage sends all assessments or a selected record', (tester,) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return _response('Coverage Preview');
    });
    addTearDown(client.close);
    await _openReport(tester, client);
    await tester.tap(find.text('Latest recorded stage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All recorded stages').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['coverage'], 'all');
    await tester.tap(find.text('All recorded stages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capstone · Concept Proposal').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['coverage'], 'specific');
    expect(requests.last.queryParameters['grade_id'], '21');
    expect(tester.takeException(), isNull);
  });

  testWidgets('individual reports use the same scope and coverage controls', (tester,) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return _response('Individual Preview');
    });
    addTearDown(client.close);
    await _openReport(tester, client, openDialog: false);
    await tester.tap(find.text('Individual Student Grade Audit Card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student Leader'));
    await tester.pumpAndSettle();
    expect(requests.last.path, endsWith('/individual-grade/3/'));
    await tester.tap(find.text('Latest recorded assessment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All recorded stages / events').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['coverage'], 'all');
    expect(tester.takeException(), isNull);
  });

  testWidgets('report search narrows grouped rows and can be cleared', (
    tester,
  ) async {
    final client = MockClient((request) async => _response('Report Preview'));
    addTearDown(client.close);
    await _openReport(tester, client, openDialog: false);

    expect(find.text('Team Grade Report Card'), findsOneWidget);
    expect(find.text('Team Roster Report'), findsOneWidget);
    expect(find.text('Audit Trail Export'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'roster');
    await tester.pumpAndSettle();
    expect(find.text('Team Roster Report'), findsOneWidget);
    expect(find.text('Team Grade Report Card'), findsNothing);
    expect(find.text('Audit Trail Export'), findsNothing);
    expect(find.text('2 of 24 reports'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'missing report');
    await tester.pumpAndSettle();
    expect(find.text('No reports found'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear report search'));
    await tester.pumpAndSettle();
    expect(find.text('Team Grade Report Card'), findsOneWidget);
    expect(find.text('Audit Trail Export'), findsOneWidget);
  });

  testWidgets('catalog filters narrow categories and clear the search and scope', (
    tester
  ) async {
    final client = MockClient((request) async => _response('Report Preview'));
    addTearDown(client.close);
    await _openReport(tester, client, openDialog: false);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defense operations & rosters'));
    await tester.pumpAndSettle();
    expect(find.text('Team Roster Report'), findsOneWidget);
    expect(find.text('Team Grade Report Card'), findsNothing);
    expect(find.text('Audit Trail Export'), findsNothing);
    expect(find.text('5 of 24 reports'), findsOneWidget);

    await tester.tap(find.text('PIT').first);
    await tester.enterText(find.byType(TextField).first, 'roster');
    await tester.pumpAndSettle();
    expect(find.text('1 of 23 reports'), findsOneWidget);

    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Team Grade Report Card'), findsOneWidget);
    expect(find.text('Capstone Stage Grade Sheet'), findsOneWidget);
    expect(find.text('Audit Trail Export'), findsOneWidget);
    expect(find.text('Browse reports by category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  },);

  testWidgets('report rows fit a narrow viewport', (tester) async {
    final client = MockClient((request) async => _response('Report Preview'));
    addTearDown(client.close);
    await _openReport(tester, client, openDialog: false, viewportWidth: 390);

    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, 'roster');
    await tester.pumpAndSettle();
    expect(find.text('Team Roster Report'), findsOneWidget);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('All categories'), findsOneWidget);
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Team Grade Report Card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applying signatories refreshes with the same settings as export', (
    tester
  ) async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return _response('Signature Preview');
    });
    addTearDown(client.close);
    await _openReport(tester, client);
    expect(requests.single.queryParameters['include_signatures'], 'false');
    expect(requests.single.queryParameters['export_format'], 'json');
    expect(find.text('Signatures (Off)'), findsOneWidget);

    await tester.tap(find.text('Signatures (Off)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'Test Admin',
      ),
      'Custom Reviewer',
    );
    await tester.tap(find.text('Apply Signatories'));
    await tester.pumpAndSettle();
    final signers = jsonDecode(requests.last.queryParameters['signatories']!) as List;
    expect(signers.first['name'], 'Custom Reviewer');
    expect(requests.last.queryParameters['include_signatures'], 'true');
    expect(requests.length, 2);

    await tester.tap(find.text('Excel Spreadsheet'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Signatories'), findsOneWidget);
    expect(find.text('Custom Reviewer'), findsOneWidget);

    await _toggleSignatures(tester, 'Signatures (3)');
    await tester.pumpAndSettle();
    expect(requests.length, 3);
    expect(requests.last.queryParameters['include_signatures'], 'false');
    expect(find.text('Signatures (Off)'), findsOneWidget);
    expect(find.text('Signatories'), findsNothing);
    expect(find.text('Custom Reviewer'), findsNothing);
    expect(find.byType(DataTable), findsOneWidget);
    expect(
      tester.widget<DefensysLiveDataPreviewPane>(
        find.byType(DefensysLiveDataPreviewPane),
      ).includeSignatures,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  },);

  testWidgets('a slower old signature response cannot replace the latest preview', (
    tester
  ) async {
    var defer = false;
    final pending = <Completer<http.Response>>[];
    final client = MockClient((request) {
      if (!defer) return Future.value(_response('Initial Preview'));
      final response = Completer<http.Response>();
      pending.add(response);
      return response.future;
    });
    addTearDown(client.close);
    await _openReport(tester, client);
    defer = true;
    await _toggleSignatures(tester, 'Signatures (Off)');
    await _toggleSignatures(tester, 'Signatures (3)');
    expect(pending.length, 2);

    pending.last.complete(_response('Latest Preview'));
    await tester.pumpAndSettle();
    pending.first.complete(_response('Stale Preview'));
    await tester.pumpAndSettle();
    final pane = tester.widget<DefensysLiveDataPreviewPane>(
      find.byType(DefensysLiveDataPreviewPane),
    );
    expect(pane.previewData!.title, 'Latest Preview');
    expect(pane.includeSignatures, isFalse);
    expect(pane.isLoading, isFalse);
    expect(tester.takeException(), isNull);
  },);

  testWidgets('view changes keep the PDF loaded and zoom controls work', (
    tester,
  ) async {
    const channel = MethodChannel('syncfusion_flutter_pdfviewer');
    var loads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'initializePdfRenderer':
            case 'loadPdfFromFile':
              loads++;
              return '1';
            case 'getPagesWidth':
              return [612.0];
            case 'getPagesHeight':
              return [792.0];
            case 'getPage':
              final args = call.arguments as Map;
              return Uint8List((args['width'] as int) * (args['height'] as int) * 4,);
            case 'closeDocument':
              return null;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final data = ReportPreviewData(
      title: 'PDF State',
      subtitle: '',
      generatedAt: '',
      summaryKpis: const [],
      columns: const [],
      rows: const [{'score': 90},],
      totalRows: 1,
      pdfBase64: base64Encode(
        File('assets/template/Minutes-Defense-TEMPLATE.pdf').readAsBytesSync(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefensysLiveDataPreviewPane(
            isLoading: false,
            previewData: data,
            onRefresh: () {},
          ),
        ),
      ),
    );
    // Native PDF loading creates a temporary file asynchronously. Let each
    // file operation complete outside the test's fake clock before rendering.
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    expect(loads, 1, reason: 'The native PDF load should finish before settling',);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('1 page'), findsOneWidget);
    final originalState = tester.state(find.byType(SfPdfViewer));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('125%'), findsOneWidget);
    await tester.tap(find.text('Fit width'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('100%'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefensysLiveDataPreviewPane(
            isLoading: false,
            previewData: data,
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.state(find.byType(SfPdfViewer)), same(originalState));
    expect(loads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
