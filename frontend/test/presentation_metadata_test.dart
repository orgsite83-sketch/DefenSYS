import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:defensys/utils/platform/universal_file_viewer_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List presentation({int width = 9144000, int height = 6858000}) {
  final archive = Archive();
  void add(String path, String value) {
    final bytes = utf8.encode(value);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    'ppt/presentation.xml',
    '''<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:sldIdLst><p:sldId id="256" r:id="rId2"/><p:sldId id="257" r:id="rId1"/></p:sldIdLst>
  <p:sldSz cx="$width" cy="$height"/>
  </p:presentation>''',
  );
  add(
    'ppt/_rels/presentation.xml.rels',
    '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>
  </Relationships>''',
  );
  // slide3 is an orphaned part and must not become a presented slide.
  for (var i = 1; i <= 3; i++) {
    add(
      'ppt/slides/slide$i.xml',
      '''<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
    <p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="123456"/></a:solidFill></p:bgPr></p:bg>
    <p:spTree><p:sp><p:spPr><a:xfrm><a:off x="100000" y="100000"/><a:ext cx="8000000" cy="1000000"/></a:xfrm></p:spPr>
    <p:txBody><a:p><a:r><a:t>Slide file $i</a:t></a:r></a:p></p:txBody></p:sp></p:spTree>
    </p:cSld></p:sld>''',
    );
  }
  add(
    'ppt/slides/_rels/slide2.xml.rels',
    '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="notes" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide7.xml"/>
  </Relationships>''',
  );
  add(
    'ppt/notesSlides/notesSlide7.xml',
    '''<p:notes xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld><a:p><a:r><a:t>Notes for the first presented slide</a:t></a:r></a:p></p:cSld>
  </p:notes>''',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  Future<void> open(WidgetTester tester, {Uint8List? bytes}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UniversalPresentationViewer(
            bytes: bytes ?? presentation(),
            fileName: 'reordered-4x3.pptx',
            onDownload: () {},
            onOpenInNewTab: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('respects the stored 4:3 slide dimensions', (tester) async {
    await open(tester);
    final canvas = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == const Color(0xFF123456),
        );
    expect(
      canvas.constraints!.maxWidth / canvas.constraints!.maxHeight,
      closeTo(4 / 3, 0.001),
    );
  });

  testWidgets('uses presentation slide order rather than filenames', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Slide file 2'), findsOneWidget);
    expect(find.text('Slide file 1'), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Next slide'));
    await tester.pumpAndSettle();
    expect(find.text('Slide file 1'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('resolves speaker notes through the slide relationship', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Speaker Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Notes for the first presented slide'), findsOneWidget);
  });

  testWidgets('supports portrait slide dimensions and matching grid previews', (
    tester,
  ) async {
    await open(tester, bytes: presentation(width: 6858000, height: 9144000));
    final canvas = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == const Color(0xFF123456),
        );
    expect(
      canvas.constraints!.maxWidth / canvas.constraints!.maxHeight,
      closeTo(3 / 4, 0.001),
    );
    await tester.tap(find.byTooltip('Grid Overview'));
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent)
          .childAspectRatio,
      closeTo(3 / 4, 0.001),
    );
    expect(tester.takeException(), isNull);
  });
}
