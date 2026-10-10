@TestOn('browser')
library;

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:defensys/utils/platform/universal_file_viewer_web.dart';
import 'package:defensys/widgets/export/defensys_pdf_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Browser widget tests do not run the app's generated plugin registrant.
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_pdfviewer_web/pdfviewer_web.dart';

// A complete, two-page PDF with visible text and an accurate cross-reference
// table. Keeping it in memory exercises the same authenticated-byte path as
// defense materials, without logging in or changing development records.
Uint8List _pdfBytes() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    for (final page in [1, 2])
      (() {
        final content =
            'BT /F1 24 Tf 48 700 Td (Defense material page $page) Tj ET\n';
        return '<< /Length ${content.length} >>\nstream\n${content}endstream';
      })(),
  ];
  final pdf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(pdf.length);
    pdf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = pdf.length;
  pdf.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    pdf.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  pdf.write(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(pdf.toString()));
}

Future<void> _waitForPages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (find.text('2 pages').evaluate().isNotEmpty &&
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((page) => page.image != null)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    // Match the PDF.js runtime already configured in web/index.html. Browser
    // tests use their own HTML host instead of the application's index.html.
    final script = html.ScriptElement()
      ..src =
          'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
    final loaded = script.onLoad.first;
    html.document.head!.append(script);
    await loaded.timeout(const Duration(seconds: 30));
    js.context['pdfjsLib']['GlobalWorkerOptions']['workerSrc'] =
        'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
    SyncfusionFlutterPdfViewerPlugin.registerWith(webPluginRegistrar);
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets('PDF pages and controls work at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = _pdfBytes();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => viewFileInDialog(
                  context: context,
                  fileBytes: bytes,
                  fileName: 'Campus Event Hub.pdf',
                ),
                child: const Text('View material'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('View material'));
      await _waitForPages(tester);
      expect(find.text('2 pages'), findsOneWidget);
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((page) => page.image != null),
        isNotEmpty,
        reason: 'At least one PDF page must actually be rasterized.',
      );
      expect(find.byType(DefensysPdfViewer), findsOneWidget);
      expect(
        find.byType(HtmlElementView),
        findsNothing,
        reason: 'PDF previews must not depend on the browser PDF plugin.',
      );
      final viewer = tester.widget<SfPdfViewer>(find.byType(SfPdfViewer));
      expect(viewer.controller!.pageCount, 2);
      expect(find.byTooltip('Download File'), findsOneWidget);
      expect(find.byTooltip('Open in New Tab'), findsOneWidget);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('125%'), findsOneWidget);
      if (size.width < 600) {
        await tester.tap(find.byTooltip('Fit width'));
      } else {
        await tester.tap(find.text('Fit width'));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('100%'), findsOneWidget);
      viewer.controller!.jumpToPage(2);
      await tester.pump(const Duration(milliseconds: 500));
      expect(viewer.controller!.pageNumber, 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pumpAndSettle();
      expect(find.byType(DefensysPdfViewer), findsNothing);
    });
  }

  testWidgets('invalid PDFs show an error and retain download access', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UniversalFileViewerDialog(
            fileBytes: ascii.encode('This is not a PDF'),
            fileName: 'Invalid.pdf',
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    // Syncfusion schedules a one-off 500 ms layout callback even for invalid
    // documents. Advance the test clock before disposing the failed preview.
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text(
        'Unable to preview this PDF. Try opening or downloading the file.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Download File'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
