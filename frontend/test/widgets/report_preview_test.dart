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

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    user: {'role': 'admin', 'first_name': 'Test', 'last_name': 'Admin'},
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
  StudentTeamsState build() => const StudentTeamsState(teams: [_team]);
  @override
  Future<void> fetchTeams({
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
  Future<void> fetchStages({String? successMessage}) async {}
}

class _Grades extends GradeCenterNotifier {
  @override
  GradeCenterState build() => const GradeCenterState();
  @override
  Future<void> fetchGrades({
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
  }),
  200,
);

Future<void> _openReport(WidgetTester tester, http.Client client) async {
  final fonts = FontLoader('Inter');
  fonts.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  fonts.addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
  await fonts.load();
  tester.view.physicalSize = const Size(1500, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
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
  testWidgets('applying signatories refreshes with the same settings as export', (
    tester,
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

    await _toggleSignatures(tester, 'Signatures (3)');
    await tester.pumpAndSettle();
    expect(requests.length, 3);
    expect(requests.last.queryParameters['include_signatures'], 'false');
    expect(find.text('Signatures (Off)'), findsOneWidget);
    expect(
      tester.widget<DefensysLiveDataPreviewPane>(
        find.byType(DefensysLiveDataPreviewPane),
      ).includeSignatures,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slower old signature response cannot replace the latest preview', (
    tester,
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
  });

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
              return Uint8List((args['width'] as int) * (args['height'] as int) * 4);
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
      rows: const [{'score': 90}],
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
    expect(loads, 1, reason: 'The native PDF load should finish before settling');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('1 page'), findsOneWidget);
    final originalState = tester.state(find.byType(SfPdfViewer));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('125%'), findsOneWidget);
    await tester.tap(find.text('Fit width'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.text('Document Sheet'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.state(find.byType(SfPdfViewer)), same(originalState));
    expect(loads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
