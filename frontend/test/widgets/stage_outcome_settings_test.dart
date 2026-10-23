import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_outcome_settings.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

void main() {
  setUpAll(loadPreviewFonts);
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
      testWidgets('outcome and repeat policies fit $width dark=$dark', (
        tester,
      ) async {
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
                      conceptSelection: true,
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
        expect(find.byType(TextFormField), findsOneWidget);
        expect(find.text('Defense Outcome'), findsOneWidget);
        final left = tester.getTopLeft(find.text('Defense Outcome'));
        final right = tester.getTopLeft(find.text('Re-defense Assessments'));
        if (width > 760) {
          expect(right.dx, greaterThan(left.dx));
          expect(right.dy, left.dy);
        } else {
          expect(right.dy, greaterThan(left.dy));
        }
        await tester.enterText(
          find.byKey(const ValueKey('minimum-qualifying-score')),
          '80',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('at least 80%'), findsOneWidget);
        await tester.ensureVisible(find.text('Require fresh assessments'));
        await tester.tap(find.text('Require fresh assessments'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retain adviser and peer scores').last);
        await tester.pumpAndSettle();
        expect(carry, 'retain');
        expect(score.text, '80');
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('outcome-settings-preview')),
          'phase3-outcome-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
      });
    }
  }
}
