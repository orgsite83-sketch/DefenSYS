import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/widgets/tabular_encoding_review.dart';
import 'package:defensys/utils/csv_file_io.dart';
import '../helpers/capture_preview.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('encoding confirmation fits $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => prepareTabularFiles(context, [
                    PickedTabularFile(
                      name: 'official-faculty.csv',
                      extension: 'csv',
                      bytes: '213,RAY AN,QUI\u00d1ON'.codeUnits,
                    ),
                  ]),
                  child: const Text('Import'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();
        expect(find.text('QUI\u00d1ON'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'encoding-review-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      });
    }
  }
  for (final accept in [true, false]) {
    testWidgets(
      'legacy file confirmation accept=$accept leaves source unchanged',
      (tester) async {
        final file = PickedTabularFile(
          name: 'faculty.csv',
          extension: 'csv',
          bytes: '213,RAY AN,QUI\u00d1ON'.codeUnits,
        );
        List<PickedTabularFile>? prepared;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    prepared = await prepareTabularFiles(context, [file]);
                  },
                  child: const Text('Import'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();
        expect(find.text('QUI\u00d1ON'), findsOneWidget);
        await tester.tap(
          find.text(accept ? 'Names display correctly' : 'Cancel'),
        );
        await tester.pumpAndSettle();
        expect(prepared != null, accept);
        expect(file.encodingConfirmed, isFalse);
        if (accept) {
          expect(prepared!.single.decodedText, contains('QUI\u00d1ON'));
          final reused = await prepareTabularFiles(
            tester.element(find.text('Import')),
            prepared!,
          );
          expect(reused!.single, same(prepared!.single));
          expect(find.text('Legacy CSV: confirm these names'), findsNothing);
        }
      },
    );
  }
  testWidgets('a failed selection does not show partial confirmation', (
    tester,
  ) async {
    String? error;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                try {
                  await prepareTabularFiles(context, [
                    PickedTabularFile(
                      name: 'good.csv',
                      extension: 'csv',
                      bytes: 'QUI\u00d1ON'.codeUnits,
                    ),
                    const PickedTabularFile(
                      name: 'bad.csv',
                      extension: 'csv',
                      bytes: [0x81],
                    ),
                  ]);
                } catch (e) {
                  error = '$e';
                }
              },
              child: const Text('Import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(error, contains('bad.csv'));
    expect(find.text('Legacy CSV: confirm these names'), findsNothing);
  });
}
