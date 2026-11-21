import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/widgets/export/defensys_document_sheet.dart';
import 'package:defensys/widgets/export/defensys_live_data_preview_pane.dart';
import 'package:defensys/widgets/export/report_catalog.dart';
import 'package:defensys/widgets/export/report_export_configuration.dart';

import '../helpers/pump_app.dart';
import 'audit_compliance_redesign_test.dart' show FakeAuthNotifier;

class _PreviewClient extends AuthenticatedHttpClient {
  _PreviewClient(super.ref, this.client);
  final http.Client client;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    if (url.path.endsWith('catalog-options/')) {
      return http.Response(
        jsonEncode({
          'default_semester_id': 1,
          'semesters': [
            {'id': 1, 'label': 'Current semester'},
          ],
        }),
        200,
      );
    }
    if (url.path.endsWith('assessment-candidates/')) {
      return http.Response(
        jsonEncode({
          'teams': [
            {
              'id': 12,
              'name': 'Team Preview',
              'project_title': 'Preview project',
              'scope': 'capstone',
              'semester_id': 1,
            },
          ],
          'students': [],
          'student_contexts': {},
        }),
        200,
      );
    }
    return client.get(url, headers: headers);
  }
}

class _Reports extends ReportsNotifier {
  Map<String, String>? downloaded;
  String? format;
  @override
  Future<bool> downloadReport({
    required String endpoint,
    required Map<String, String> queryParams,
    required String defaultFilename,
    String exportFormat = 'pdf',
  }) async {
    downloaded = Map.of(queryParams);
    format = exportFormat;
    return true;
  }
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
    'summary_kpis': [],
    'assessments': [
      {'id': 21, 'scope': 'capstone', 'stage_label': 'Concept Proposal'},
    ],
  }),
  200,
);

Future<_Reports> _openReport(WidgetTester tester, http.Client client) async {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final reports = _Reports();
  await pumpDefensysWidget(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ReportExportWorkspace(
        report: ReportCatalog.find('team-grade')!,
        params: const {
          'team_id': '12',
          'scope': 'capstone',
          'semester_id': '1',
        },
        embedded: true,
      ),
    ),
    overrides: [
      authProvider.overrideWith(
        () => FakeAuthNotifier({
          'role': 'admin',
          'first_name': 'Test',
          'last_name': 'Admin',
        }),
      ),
      reportsProvider.overrideWith(() => reports),
      authenticatedHttpClientProvider.overrideWith(
        (ref) => _PreviewClient(ref, client),
      ),
    ],
  );
  return reports;
}

Future<void> _format(WidgetTester tester, String name) async {
  final select = find.byWidgetPredicate(
    (widget) =>
        widget is ShadSelect<String> &&
        widget.key.toString().contains('report-preview-format'),
  );
  await tester.ensureVisible(select);
  await tester.tap(select);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> _openSignatures(WidgetTester tester) async {
  final button = find.text('Signatures');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _toggleSignatures(WidgetTester tester) async {
  await _openSignatures(tester);
  await tester.tap(find.byType(Switch));
  await tester.pump();
  await tester.tap(find.text('Apply Signatories'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'PDF and Excel previews render their document and table in the report workspace',
    (tester) async {
      final client = MockClient((request) async => _response('Format Preview'));
      addTearDown(client.close);
      await _openReport(tester, client);
      expect(find.byType(DefensysDocumentSheet), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      await _format(tester, 'Excel');
      expect(find.byType(DefensysDocumentSheet), findsNothing);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('Download Excel'), findsOneWidget);
      await _format(tester, 'PDF');
      expect(find.byType(DefensysDocumentSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'More options retains filename and signatories for preview and download',
    (tester) async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return _response('Signature Preview');
      });
      addTearDown(client.close);
      final reports = await _openReport(tester, client);
      expect(requests.single.queryParameters['include_signatures'], 'false');
      expect(find.byKey(const ValueKey('report-filename')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('report-more-options')),
      );
      await tester.tap(find.byKey(const ValueKey('report-more-options')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('report-filename')),
          matching: find.byType(EditableText),
        ),
        'Official report',
      );
      await _openSignatures(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller?.text == 'Test Admin',
        ),
        'Custom Reviewer',
      );
      await tester.tap(find.text('Apply Signatories'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['include_signatures'], 'true');
      final signers =
          jsonDecode(requests.last.queryParameters['signatories']!) as List;
      expect(signers.first['name'], 'Custom Reviewer');
      await _format(tester, 'Excel');
      expect(find.text('Custom Reviewer'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('report-download-xlsx')),
      );
      await tester.tap(find.byKey(const ValueKey('report-download-xlsx')));
      await tester.pumpAndSettle();
      expect(reports.format, 'xlsx');
      expect(reports.downloaded?['custom_filename'], 'Official report');
      expect(
        reports.downloaded?['signatories'],
        requests.last.queryParameters['signatories'],
      );
      expect(reports.downloaded?['include_signatures'], 'true');
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'A slower old signature response cannot replace the latest report preview',
    (tester) async {
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('report-more-options')),
      );
      await tester.tap(find.byKey(const ValueKey('report-more-options')));
      await tester.pumpAndSettle();
      defer = true;
      await _toggleSignatures(tester);
      await _toggleSignatures(tester);
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
    },
  );

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
              return Uint8List(
                (args['width'] as int) * (args['height'] as int) * 4,
              );
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
      rows: const [
        {'score': 90},
      ],
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
    expect(
      loads,
      1,
      reason: 'The native PDF load should finish before settling',
    );
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
