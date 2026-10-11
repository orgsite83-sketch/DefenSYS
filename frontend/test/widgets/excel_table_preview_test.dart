import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/admin/reports_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/export/defensys_live_data_preview_pane.dart';
import 'package:defensys/widgets/export/export_dropdown_button.dart';
import 'package:defensys/widgets/export/defensys_pdf_viewer.dart';
import '../helpers/pump_app.dart';

const _data = ReportPreviewData(
  title: 'Capstone Grades',
  subtitle: '',
  generatedAt: '',
  totalRows: 3,
  excelHeader: [
    'Capstone Grades',
    '1st Semester, A.Y. 2026-2027 | Capstone | Concept Proposal',
  ],
  summaryKpis: [
    {'label': 'Mean Recorded Grade', 'value': '46.50%'},
  ],
  columns: [
    {'key': 'student', 'label': 'Student', 'width': 26},
    {'key': 'score', 'label': 'Final Grade', 'type': 'percentage', 'width': 18},
    {'key': 'date', 'label': 'Date', 'type': 'date', 'width': 20},
  ],
  rows: [
    {'student': 'Andrea Santos', 'score': '84.00%', 'date': '2026-10-11'},
    {'student': 'Carlo Reyes', 'score': '9.00%', 'date': '2026-06-18'},
    {'student': 'Student Pending', 'score': 'Pending', 'date': ''},
  ],
  excelSheets: [
    {
      'name': 'Criteria',
      'title': 'Complete Rubric Criteria',
      'excel_header': [
        'Complete Rubric Criteria',
        '1st Semester, A.Y. 2026-2027 | Capstone',
      ],
      'columns': [
        {'key': 'criterion', 'label': 'Criterion', 'width': 26},
        {'key': 'description', 'label': 'Description', 'width': 66},
      ],
      'rows': [
        {
          'criterion': 'Technical Quality',
          'description':
              'Assess the clarity, completeness, and technical accuracy of the proposed design. Include supporting evidence and the rationale for implementation choices.',
        },
      ],
    },
  ],
);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('DEFENSYS_EXPORT_QA')) return;
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
    'Excel renders workbook sheets, preserves bytes on rebuild, and switches worksheets',
    (tester) async {
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
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final encoded = base64Encode(
        File('assets/template/Minutes-Defense-TEMPLATE.pdf').readAsBytesSync(),
      );
      final data = ReportPreviewData.fromJson({
        'title': 'Team Grade',
        'rows': [
          {'student': 'Adrian'},
        ],
        'columns': [
          {'key': 'scope', 'label': 'Repeated Scope'},
        ],
        'excel_workbook_preview': {
          'sheets': [
            {'name': 'Concept Proposal', 'pdf_base64': encoded},
            {'name': 'Project Proposal', 'pdf_base64': encoded},
          ],
        },
      });
      Widget app() => MaterialApp(
        home: Scaffold(
          body: DefensysLiveDataPreviewPane(
            isLoading: false,
            previewData: data,
            onRefresh: () {},
            selectedFormat: 'xlsx',
          ),
        ),
      );
      Future<void> finishNativeLoad() async {
        await tester.runAsync(() async {
          for (var i = 0; i < 10; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.pumpWidget(app());
      await finishNativeLoad();
      expect(find.text('Excel workbook preview'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Repeated Scope'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester
            .widget<DefensysPdfViewer>(find.byType(DefensysPdfViewer))
            .pdfBytes,
        same(data.workbookSheets.first.pdfBytes),
      );
      expect(loads, 1);
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 500));
      expect(loads, 1);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Project Proposal').last);
      await finishNativeLoad();
      expect(
        tester
            .widget<DefensysPdfViewer>(find.byType(DefensysPdfViewer))
            .pdfBytes,
        same(data.workbookSheets.last.pdfBytes),
      );
      expect(loads, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  test(
    'Invalid workbook preview reports failure instead of showing a different table',
    () {
      final data = ReportPreviewData.fromJson({
        'excel_workbook_preview': {
          'sheets': [
            {'name': 'Report', 'pdf_base64': '!invalid!'},
          ],
        },
      });
      expect(data.workbookSheets, isEmpty);
      expect(data.excelPreviewError, isNotNull);
    },
  );

  testWidgets(
    'Excel headings stay compact and numeric/date sorting retains pending records',
    (tester) async {
      final fonts = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final key = GlobalKey();
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: key,
          child: DefensysLiveDataPreviewPane(
            isLoading: false,
            previewData: _data,
            onRefresh: () {},
            selectedFormat: 'xlsx',
          ),
        ),
      );
      expect(find.text('Capstone Grades'), findsOneWidget);
      expect(find.text('Mean Recorded Grade'), findsNothing);
      expect(tester.getSize(find.byType(DataTable)).height, lessThan(180));
      await tester.tap(find.text('Final Grade'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('9.00%')).dy,
        lessThan(tester.getTopLeft(find.text('84.00%')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Pending')).dy,
        greaterThan(tester.getTopLeft(find.text('84.00%')).dy),
      );
      await tester.tap(find.text('Final Grade'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('84.00%')).dy,
        lessThan(tester.getTopLeft(find.text('9.00%')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Pending')).dy,
        greaterThan(tester.getTopLeft(find.text('9.00%')).dy),
      );
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('2026-06-18')).dy,
        lessThan(tester.getTopLeft(find.text('2026-10-11')).dy),
      );
      await _capture(tester, key, 'excel-preview-qa');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Supporting worksheets show complete wrapped text and reset main-sheet sorting',
    (tester) async {
      final key = GlobalKey();
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: key,
          child: DefensysLiveDataPreviewPane(
            isLoading: false,
            previewData: _data,
            onRefresh: () {},
            selectedFormat: 'xlsx',
          ),
        ),
      );
      await tester.tap(find.text('Final Grade'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Andrea');
      await tester.pumpAndSettle();
      expect(find.text('Carlo Reyes'), findsNothing);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criteria').last);
      await tester.pumpAndSettle();
      expect(find.text('Complete Rubric Criteria'), findsOneWidget);
      expect(find.text('Technical Quality'), findsOneWidget);
      expect(
        tester.widget<DataTable>(find.byType(DataTable)).sortColumnIndex,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      final description = tester.widget<Text>(
        find.textContaining('Assess the clarity'),
      );
      expect(description.overflow, isNot(TextOverflow.ellipsis));
      await _capture(tester, key, 'criteria-preview-qa');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Export menu keeps its neutral appearance and actions', (
    tester,
  ) async {
    final choices = <String>[];
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: Stack(
              children: [
                Positioned(
                  top: 36,
                  right: 36,
                  child: ExportDropdownButton(onSelected: choices.add),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Report Center'), findsOneWidget);
    await _capture(tester, key, 'export-menu-qa');
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();
    expect(choices, ['xlsx']);
    expect(tester.takeException(), isNull);
  });
}
