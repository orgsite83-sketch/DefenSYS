import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/export/defensys_export_format_bar.dart';
import 'package:defensys/widgets/export/defensys_live_data_preview_pane.dart';
import 'package:defensys/widgets/export/defensys_report_dialog_shell.dart';
import 'package:defensys/widgets/export/report_catalog.dart';
import 'package:defensys/widgets/export/report_export_configuration.dart';
import 'audit_compliance_redesign_test.dart' show FakeAuthNotifier;

class _Options extends AuthenticatedHttpClient {
  _Options(super.ref);
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async =>
      http.Response(
        jsonEncode({
          'semesters': [
            {'id': 3, 'label': '1st Semester, A.Y. 2026-2027'},
            {'id': 4, 'label': '2nd Semester, A.Y. 2026-2027'},
          ],
          'rubrics': [
            {
              'id': 17,
              'label': 'Proposal Quality Guide',
              'semester_id': 3,
              'scope': 'capstone',
            },
          ],
          'teams': [],
          'students': [],
          'stages': [
            {'id': 1, 'label': 'Concept Proposal'},
            {'id': 2, 'label': 'Project Proposal'},
          ],
          'default_semester_id': 3,
          'stage_choices': [
            {
              'value': 'Concept Proposal',
              'label': 'Concept Proposal',
              'scope': 'capstone',
            },
            {
              'value': 'Project Proposal',
              'label': 'Project Proposal',
              'scope': 'capstone',
            },
            {
              'value': 'IT Olympics',
              'label': 'IT Olympics',
              'scope': 'pit',
              'semester_id': 3,
            },
            {
              'value': 'Old PIT Event',
              'label': 'Old PIT Event',
              'scope': 'pit',
              'semester_id': 4,
            },
          ],
        }),
        200,
      );
}

class _Reports extends ReportsNotifier {
  final previews = <Map<String, String>>[];
  Map<String, String>? download;
  String? format;
  @override
  ReportsState build() => const ReportsState();
  @override
  Future<ReportPreviewData?> fetchReportPreview({
    required String endpoint,
    required Map<String, String> queryParams,
  }) async {
    previews.add(Map.of(queryParams));
    return const ReportPreviewData(
      title: 'Official Report Preview',
      subtitle: 'Selected records',
      generatedAt: '2026-10-11',
      generatedBy: 'Administrator',
      totalRows: 2,
      summaryKpis: [],
      metadata: [
        {'label': 'Records', 'value': '2'},
      ],
      columns: [
        {'key': 'team', 'label': 'Team', 'width': 30},
        {'key': 'status', 'label': 'Status', 'width': 24},
      ],
      rows: [
        {'team': 'Team AgriSense', 'status': 'Completed'},
        {'team': 'Team BioPulse', 'status': 'Awaiting Evaluation'},
      ],
    );
  }

  @override
  Future<bool> downloadReport({
    required String endpoint,
    required Map<String, String> queryParams,
    required String defaultFilename,
    String exportFormat = 'pdf',
  }) async {
    download = Map.of(queryParams);
    format = exportFormat;
    return true;
  }
}

Future<GlobalKey> _open(
  WidgetTester tester,
  ReportDefinition report,
  _Reports reports, {
  Map<String, String> params = const {},
  Map<String, dynamic> user = const {'role': 'admin'},
}) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier(user)),
        reportsProvider.overrideWith(() => reports),
        authenticatedHttpClientProvider.overrideWith((ref) => _Options(ref)),
      ],
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showReportExportConfiguration(
                  context: context,
                  ref: ref,
                  report: report,
                  params: params,
                ),
                child: const Text('Open report'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open report'));
  await tester.pumpAndSettle();
  return boundary;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('DEFENSYS_EXPORT_QA')) return;
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('../.tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'Stage export uses a named dropdown and clears its selection when the period changes',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reports = _Reports();
      final boundary = await _open(
        tester,
        ReportCatalog.find('defense-stage-setup')!,
        reports,
        params: {'semester_id': '3'},
      );
      expect(find.byKey(const ValueKey('report-filter-stage')), findsNothing);
      final stage = find.byKey(const ValueKey('stage::false'));
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: stage,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items!.map((item) => item.value), [
        '',
        'Concept Proposal',
        'Project Proposal',
      ]);
      await tester.tap(stage);
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'stage-dropdown-dialog-qa');
      await tester.tap(find.text('Project Proposal').last);
      await tester.pumpAndSettle();
      expect(reports.previews.last['stage'], 'Project Proposal');
      await tester.tap(find.byKey(const ValueKey('semester_id:3:false')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2nd Semester, A.Y. 2026-2027').last);
      await tester.pumpAndSettle();
      expect(reports.previews.last['semester_id'], '4');
      expect(reports.previews.last.containsKey('stage'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PIT event dropdown contains only events in the selected academic period',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _open(
        tester,
        ReportCatalog.find('pit-event-setup')!,
        _Reports(),
        params: {'semester_id': '3'},
      );
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const ValueKey('stage::false')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items!.map((item) => item.value), ['', 'IT Olympics']);
      expect(tester.takeException(), isNull);
    },
  );

  setUpAll(() async {
    final fonts = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    if (const bool.fromEnvironment('DEFENSYS_EXPORT_QA')) {
      final serif = FontLoader('serif')
        ..addFont(
          File(
            'C:/Windows/Fonts/times.ttf',
          ).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
        )
        ..addFont(
          File(
            'C:/Windows/Fonts/timesbd.ttf',
          ).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
        );
      await serif.load();
    }
  });

  testWidgets('All new reports share the assessment dialog and pinned footer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final report in ReportCatalog.reports.where(
      (report) => !report.legacy,
    )) {
      final boundary = await _open(tester, report, _Reports());
      expect(find.byType(DefensysReportDialogShell), findsOneWidget);
      expect(find.text(report.title), findsOneWidget);
      expect(find.text(report.category), findsOneWidget);
      expect(find.text('EXPORT FILTERS'), findsOneWidget);
      expect(find.byType(DefensysExportFormatBar), findsOneWidget);
      expect(find.text('PDF Document'), findsOneWidget);
      expect(find.text('Excel Spreadsheet'), findsOneWidget);
      expect(find.text('Signatures (Off)'), findsOneWidget);
      expect(find.text('Download PDF Export'), findsOneWidget);
      expect(find.text('SELECT EXPORT FORMAT'), findsNothing);
      final footer = tester.getRect(
        find.byKey(const ValueKey('report-export-footer')),
      );
      final preview = tester.getRect(find.byType(DefensysLiveDataPreviewPane));
      expect(footer.top, greaterThanOrEqualTo(preview.bottom));
      expect(footer.width, 1120);
      if ([
        'readiness',
        'external-evaluators',
        'project-records',
      ].contains(report.id)) {
        await _capture(tester, boundary, '${report.id}-dialog-qa');
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'Reset clears visible filters and export preserves format, filename and signatories',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reports = _Reports();
      await _open(
        tester,
        ReportCatalog.find('project-records')!,
        reports,
        params: {
          'academic_year': '2026-2027',
          'stage': 'Project Proposal',
          'search': 'AgriSense',
        },
      );
      final search = find.byKey(const ValueKey('report-filter-search'));
      expect(tester.widget<TextField>(search).controller!.text, 'AgriSense');
      await tester.ensureVisible(find.text('Reset All Filters'));
      await tester.tap(find.text('Reset All Filters'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(reports.previews.last.containsKey('search'), isFalse);
      expect(reports.previews.last.containsKey('stage'), isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('report-filename')));
      await tester.enterText(
        find.byKey(const ValueKey('report-filename')),
        'Archive Review',
      );
      await tester.tap(find.text('Excel Spreadsheet'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DefensysLiveDataPreviewPane>(
              find.byType(DefensysLiveDataPreviewPane),
            )
            .selectedFormat,
        'xlsx',
      );
      await tester.tap(find.text('Signatures (Off)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Signatories'));
      await tester.pumpAndSettle();
      final preview = reports.previews.last;
      expect(preview['include_signatures'], 'true');
      await tester.tap(find.text('Download XLSX Export'));
      await tester.pumpAndSettle();
      expect(reports.format, 'xlsx');
      expect(reports.download?['custom_filename'], 'Archive Review');
      expect(reports.download?['signatories'], preview['signatories']);
      expect(
        reports.download?['include_signatures'],
        preview['include_signatures'],
      );
      expect(reports.download?.containsKey('search'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Reset retains the PIT lead assigned scope and year', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reports = _Reports();
    await _open(
      tester,
      ReportCatalog.find('readiness')!,
      reports,
      params: {
        'scope': 'capstone',
        'year_level': '4th Year',
        'search': 'Project',
      },
      user: {
        'role': 'faculty',
        'is_pit_lead': true,
        'pit_lead_year': '2nd Year',
      },
    );
    await tester.ensureVisible(find.text('Reset All Filters'));
    await tester.tap(find.text('Reset All Filters'));
    await tester.pumpAndSettle();
    expect(reports.previews.last['scope'], 'pit');
    expect(reports.previews.last['year_level'], '2nd Year');
    expect(reports.previews.last.containsKey('search'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filters and preview remain usable on smaller screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(900, 600), const Size(600, 800)]) {
      tester.view.physicalSize = size;
      final boundary = await _open(
        tester,
        ReportCatalog.find('project-records')!,
        _Reports(),
      );
      if (size.width < 800) {
        expect(find.text('Filters'), findsOneWidget);
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(find.byType(DefensysLiveDataPreviewPane), findsOneWidget);
      }
      expect(find.text('Download PDF Export'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        boundary,
        'report-dialog-${size.width.toInt()}-qa',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });
}
