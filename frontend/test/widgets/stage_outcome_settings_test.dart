import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_outcome_settings.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/future_defense_rules_dialog.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

void main() {
  setUpAll(loadPreviewFonts);
  for (final width in [320.0, 1100.0]) {
    testWidgets(
      'locked stages can save future policy without structural changes at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        Map<String, dynamic>? saved;
        await pumpDefensysWidget(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showFutureDefenseRulesDialog(
                context,
                stage: {
                  'is_locked': true,
                  'qualifying_score': 75,
                  'score_carryover': 'reassess',
                  'revision_areas': [
                    {'id': 'system', 'label': 'System', 'allows_demo': true},
                    {
                      'id': 'manuscript',
                      'label': 'Manuscript',
                      'allows_demo': false,
                    },
                  ],
                },
                onSave: (payload) async {
                  saved = payload;
                  return null;
                },
              ),
              child: const Text('Edit future rules'),
            ),
          ),
          theme: width == 320 ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        await tester.tap(find.text('Edit future rules'));
        await tester.pumpAndSettle();
        expect(find.text('Revision areas'), findsNothing);
        expect(find.text('Add revision area'), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('minimum-qualifying-score')),
          '80',
        );
        await tester.ensureVisible(find.text('Save rules'));
        await tester.tap(find.text('Save rules'));
        await tester.pumpAndSettle();
        expect(saved?.keys.toSet(), {'qualifying_score', 'score_carryover'});
        expect(saved?['qualifying_score'], 80);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('qualifying score accepts boundaries and rejects invalid input', () {
    for (final score in ['0', '50', '75', '99.99', '100']) {
      expect(StageOutcomeSettings.validateScore(score), isNull);
    }
    for (final score in ['', '-1', '101', 'NaN', 'Infinity', '75.555']) {
      expect(StageOutcomeSettings.validateScore(score), isNotNull);
    }
  });
  for (final width in [320.0, 1100.0]) {
    for (final dark in [false, true]) {
      for (final concept in [false, true]) {
        testWidgets(
          'outcome and repeat policies fit $width dark=$dark concept=$concept',
          (tester) async {
            tester.view.physicalSize = Size(width, 950);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final score = TextEditingController(text: '75');
            addTearDown(score.dispose);
            var carry = 'reassess';
            await pumpDefensysWidget(
              tester,
              DefensysShadcnScope(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RepaintBoundary(
                      key: const ValueKey('outcome-settings-preview'),
                      child: StatefulBuilder(
                        builder: (_, update) => StageOutcomeSettings(
                          scoreController: score,
                          scoreCarryover: carry,
                          conceptSelection: concept,
                          onChanged: () => update(() {}),
                          onCarryoverChanged: (v) => update(() => carry = v),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
            );
            expect(find.byType(ShadInput), findsOneWidget);
            expect(find.text('Defense rules'), findsOneWidget);
            if (concept) {
              expect(
                find.text('Adviser and peer scores on re-defense'),
                findsNothing,
              );
            } else {
              expect(
                tester
                    .getTopLeft(
                      find.text('Adviser and peer scores on re-defense'),
                    )
                    .dy,
                greaterThan(
                  tester.getTopLeft(find.text('Panel qualifying score')).dy,
                ),
              );
            }
            await tester.enterText(
              find.byKey(const ValueKey('minimum-qualifying-score')),
              '80',
            );
            await tester.pumpAndSettle();
            expect(
              find.text(
                concept
                    ? 'Concepts need 80% to qualify for panel selection.'
                    : 'Below 80% requires re-defense.',
              ),
              findsOneWidget,
            );
            if (!concept) {
              await tester.ensureVisible(find.text('Keep previous scores'));
              await tester.tap(find.text('Keep previous scores'));
              await tester.pumpAndSettle();
              expect(carry, 'retain');
            } else {
              expect(find.text('Keep previous scores'), findsNothing);
            }
            expect(score.text, '80');
            expect(tester.takeException(), isNull);
            await capturePreview(
              tester,
              find.byKey(const ValueKey('outcome-settings-preview')),
              'phase3-outcome-${width.toInt()}-${dark ? 'dark' : 'light'}-$concept',
            );
          },
        );
      }
    }
  }
}
