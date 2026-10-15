import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/platform/universal_file_viewer_models.dart';
import 'package:defensys/utils/platform/universal_file_viewer_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _createSamplePptxBytes() {
  final archive = Archive();
  const slide1Xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="1" name="Title 1"/>
          <p:nvPr><p:ph type="title"/></p:nvPr>
        </p:nvSpPr>
        <p:txBody>
          <a:p><a:r><a:t>TechNest Presentation</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Content 1"/>
          <p:nvPr><p:ph/></p:nvPr>
        </p:nvSpPr>
        <p:txBody>
          <a:p><a:r><a:t>First key milestone accomplished</a:t></a:r></a:p>
          <a:p><a:r><a:t>Intranet integration completed</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';

  archive.addFile(
    ArchiveFile('ppt/slides/slide1.xml', slide1Xml.length, utf8.encode(slide1Xml)),
  );
  final encoded = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(encoded);
}

Uint8List _createSampleDocxBytes() {
  final archive = Archive();
  const docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Title"/></w:pPr>
      <w:r><w:t>Project Concept Paper</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>This proposal outlines automated kiosk dispatching.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';

  archive.addFile(
    ArchiveFile('word/document.xml', docXml.length, utf8.encode(docXml)),
  );
  final encoded = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(encoded);
}

Uint8List _createSampleZipBytes() {
  final archive = Archive();
  final content1 = utf8.encode('def test(): pass');
  final content2 = utf8.encode('readme content');
  archive.addFile(ArchiveFile('main.py', content1.length, content1));
  archive.addFile(ArchiveFile('docs/README.md', content2.length, content2));
  final encoded = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(encoded);
}

void main() {
  group('File Viewer Category & Metadata Detection', () {
    test('detects all standard academic deliverable extensions', () {
      expect(
        FileViewerMetadata.detectCategory('Project_Proposal.pdf'),
        FileCategory.pdf,
      );
      expect(
        FileViewerMetadata.detectCategory('Pitch_Deck.pptx'),
        FileCategory.officePresentation,
      );
      expect(
        FileViewerMetadata.detectCategory('Legacy_Deck.ppt'),
        FileCategory.officePresentation,
      );
      expect(
        FileViewerMetadata.detectCategory('Manuscript.docx'),
        FileCategory.officeDoc,
      );
      expect(
        FileViewerMetadata.detectCategory('Old_Doc.doc'),
        FileCategory.officeDoc,
      );
      expect(
        FileViewerMetadata.detectCategory('Budget.xlsx'),
        FileCategory.spreadsheet,
      );
      expect(
        FileViewerMetadata.detectCategory('Data.csv'),
        FileCategory.spreadsheet,
      );
      expect(
        FileViewerMetadata.detectCategory('Deliverables.zip'),
        FileCategory.archive,
      );
      expect(
        FileViewerMetadata.detectCategory('Mockup.png'),
        FileCategory.image,
      );
      expect(
        FileViewerMetadata.detectCategory('Diagram.svg'),
        FileCategory.image,
      );
      expect(
        FileViewerMetadata.detectCategory('script.py'),
        FileCategory.codeOrText,
      );
    });

    test('formats bytes into clean human readable strings', () {
      expect(FileViewerMetadata.formatBytes(0), '0 B');
      expect(FileViewerMetadata.formatBytes(512), '512 B');
      expect(FileViewerMetadata.formatBytes(59 * 1024), '59 KB');
      expect(FileViewerMetadata.formatBytes(188 * 1024), '188 KB');
      expect(FileViewerMetadata.formatBytes(4 * 1024 * 1024), '4.0 MB');
    });
  });

  group('UniversalPresentationViewer', () {
    testWidgets('renders presentation slides and extracts title and bullets', (
      tester,
    ) async {
      final bytes = _createSamplePptxBytes();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: UniversalPresentationViewer(
              bytes: bytes,
              fileName: '07_TechNest_Pitch_Deck.pptx',
              onDownload: () {},
              onOpenInNewTab: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TechNest Presentation'), findsOneWidget);
      expect(find.text('First key milestone accomplished'), findsOneWidget);
      expect(find.text('Intranet integration completed'), findsOneWidget);
      expect(find.text('1 slide • Slide 1'), findsOneWidget);
    });
  });

  group('UniversalDocxViewer', () {
    testWidgets('renders Word document and extracts headings and text', (
      tester,
    ) async {
      final bytes = _createSampleDocxBytes();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: UniversalDocxViewer(
              bytes: bytes,
              fileName: 'TechNest_Concept_Paper.docx',
              onDownload: () {},
              onOpenInNewTab: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Project Concept Paper'), findsOneWidget);
      expect(
        find.text('This proposal outlines automated kiosk dispatching.'),
        findsOneWidget,
      );
    });
  });

  group('UniversalArchiveViewer', () {
    testWidgets('renders zip archive file explorer', (tester) async {
      final bytes = _createSampleZipBytes();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: UniversalArchiveViewer(
              bytes: bytes,
              fileName: 'SourceCode.zip',
              onDownload: () {},
              onOpenInNewTab: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main.py'), findsOneWidget);
      expect(find.text('docs/README.md'), findsOneWidget);
      expect(find.textContaining('2 contained files'), findsOneWidget);
    });
  });

  group('UniversalSpreadsheetViewer', () {
    testWidgets('renders CSV data table with clean Image 2 layout', (
      tester,
    ) async {
      final csvBytes = Uint8List.fromList(
        utf8.encode('Name,Score,Status\nTeam TechNest,95,Passed\nTeam Apex,88,Passed'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: UniversalSpreadsheetViewer(
              bytes: csvBytes,
              fileName: 'Grades.csv',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Team TechNest'), findsOneWidget);
      expect(find.text('Team Apex'), findsOneWidget);
      expect(find.text('95'), findsOneWidget);
    });
  });
}
