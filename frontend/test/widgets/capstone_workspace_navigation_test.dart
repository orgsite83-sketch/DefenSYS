import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/academic/capstone_workspace_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'batch navigation without phase buttons at $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          List<String>? selection;
          const preview = ValueKey('phase-preview');
          await pumpDefensysWidget(
            tester,
            Padding(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: preview,
                child: Builder(
                  builder: (context) => ColoredBox(
                    color: DefensysTokens.surfaceOf(context),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CapstoneWorkspaceNavigation(
                        data: const {
                          'view': 'ongoing',
                          'batch_id': '12',
                          'phase_semester_id': 14,
                          'batches': [
                            {
                              'value': '12',
                              'label': '2nd Semester, A.Y. 2025-2026',
                            },
                          ],
                          'phase_groups': [
                            {
                              'semester_id': 12,
                              'phase_label': 'Capstone 1',
                              'display_semester':
                                  '2nd Semester, A.Y. 2025-2026',
                              'read_only': true,
                              'stage_count': 2,
                            },
                            {
                              'semester_id': 14,
                              'phase_label': 'Capstone 2',
                              'display_semester':
                                  '1st Semester, A.Y. 2026-2027',
                              'read_only': false,
                              'stage_count': 0,
                            },
                          ],
                        },
                        onChanged: (view, batch, term) =>
                            selection = [view, batch, term],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          );
          expect(find.text('Capstone 1'), findsNothing);
          expect(find.text('Capstone 2'), findsNothing);
          await capturePreview(
            tester,
            find.byKey(preview),
            'capstone-workspace-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('History'));
          await tester.pumpAndSettle();
          expect(selection, ['history', '', '']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('empty history explains that no previous batches exist', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      CapstoneWorkspaceNavigation(
        data: const {'view': 'history'},
        onChanged: (_, _, _) {},
      ),
    );
    expect(find.text('No previous batches.'), findsOneWidget);
    expect(find.text('No ongoing batches.'), findsNothing);
  });
}
