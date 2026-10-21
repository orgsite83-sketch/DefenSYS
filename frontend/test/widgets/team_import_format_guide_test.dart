import 'package:defensys/widgets/team_import_format_guide.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/capture_preview.dart';

void main() {
  for (final width in [390.0, 1400.0]) {
    for (final capstone in [false, true]) {
      testWidgets('format guide fits $width and Capstone=$capstone', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: 660,
                  child: TeamImportFormatGuide(
                    isCapstone: capstone,
                    contextLabel: '1st Semester, A.Y. 2026–2027',
                    onDownload: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(capstone ? 'Capstone Project' : 'PIT Project'),
          findsOneWidget,
        );
        expect(find.text('System Name:'), findsOneWidget);
        expect(find.text('Project Manager:'), findsOneWidget);
        expect(find.text('H'), findsNothing);
        expect(find.text('I'), findsNothing);
        expect(find.text('No team name or project title yet?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 1400 && !capstone) {
          await capturePreview(
            tester,
            find.byType(Scaffold),
            'team-import-guide-implemented',
            viewport: true,
          );
          await tester.tap(find.text('View Sheet Layout Blueprint'));
          await tester.pumpAndSettle();
          expect(
            find.text('Official PIT Team Sheet Blueprint'),
            findsOneWidget,
          );
          expect(find.text('Download Excel Template (.xlsx)'), findsOneWidget);
          expect(find.text('Copy for Excel / Sheets'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(ShadDialog),
              matching: find.byType(TeamImportSetupHelp),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(ShadDialog),
            'team-import-blueprint-implemented',
            viewport: true,
          );
        }
      });
    }
  }
}
