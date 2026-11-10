import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/academic/capstone_stage_sequence_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  for (final dark in [false, true]) {
    testWidgets(
      'one dropdown keeps same-named stages in their original phases dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        await pumpDefensysWidget(
          tester,
          Padding(
            padding: const EdgeInsets.all(16),
            child: CapstoneStageSequenceSelect(
              value: '14:35',
              options: const [
                {
                  'key': '12:34',
                  'stage_label': 'Project',
                  'phase_label': 'Capstone 1',
                  'read_only': true,
                  'display_semester': '2nd Semester, A.Y. 2025-2026',
                },
                {
                  'key': '14:35',
                  'stage_label': 'Project',
                  'phase_label': 'Capstone 2',
                  'read_only': false,
                  'display_semester': '1st Semester, A.Y. 2026-2027',
                },
              ],
              onChanged: (value) => selected = value,
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        await tester.tap(find.text('Capstone 2 · Project'));
        await tester.pumpAndSettle();
        expect(find.text('Capstone 1'), findsOneWidget);
        expect(find.text('Capstone 2'), findsOneWidget);
        expect(find.textContaining('Read-only ·'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(CapstoneStageSequenceSelect),
          'adviser-stage-sequence-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.byKey(const ValueKey('stage-option-12:34')));
        await tester.pumpAndSettle();
        expect(selected, '12:34');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
