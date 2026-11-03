import 'package:defensys/screens/app/panelist/widgets/evaluation_score_input.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Future<void> _showInput(
  WidgetTester tester, {
  double? initial,
  double maximum = 100,
  bool enabled = true,
  ValueChanged<double?>? onChanged,
}) async {
  double? score = initial;
  await pumpDefensysWidget(
    tester,
    DefensysShadcnScope(
      child: StatefulBuilder(
        builder: (context, update) => EvaluationScoreInput(
          label: 'Technique',
          maximum: maximum,
          value: score,
          enabled: enabled,
          onChanged: (value) {
            update(() => score = value);
            onChanged?.call(value);
          },
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('numeric decimal keypad preserves blank, zero and exact scores', (
    tester,
  ) async {
    double? score;
    await _showInput(tester, onChanged: (value) => score = value);
    final input = tester.widget<ShadInput>(find.byType(ShadInput));
    expect(
      input.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(input.textInputAction, TextInputAction.done);
    expect(input.style?.fontFamily, DefensysTokens.fontFamilyInter);
    expect(input.style?.fontSize, 16);
    expect(input.controller!.text, isEmpty);
    expect(find.text('/ 100'), findsOneWidget);
    for (final entry in {
      '0': 0.0,
      '87.5': 87.5,
      '87.25': 87.25,
      '87,5': 87.5,
      '.5': .5,
      '100': 100.0,
    }.entries) {
      await tester.enterText(find.byType(EditableText), entry.key);
      await tester.pump();
      expect(score, entry.value);
      expect(input.controller!.text, entry.key);
    }
    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();
    expect(score, isNull);
    expect(find.textContaining('Enter a'), findsNothing);
  });

  testWidgets('invalid typed or pasted text clears the previous valid score', (
    tester,
  ) async {
    double? score = 85;
    await _showInput(
      tester,
      initial: score,
      onChanged: (value) => score = value,
    );
    for (final text in [
      '101',
      '-1',
      '85.555',
      '8abc5',
      '1e2',
      'NaN',
      'Infinity',
      '85,5.5',
    ]) {
      await tester.enterText(find.byType(EditableText), text);
      await tester.pump();
      expect(score, isNull, reason: text);
      expect(
        tester.widget<ShadInput>(find.byType(ShadInput)).controller!.text,
        text,
      );
      expect(
        find.textContaining(text == '85.555' ? 'Use up to 2' : 'Enter a'),
        findsOneWidget,
      );
    }
    await tester.enterText(find.byType(EditableText), '85.5');
    await tester.pump();
    expect(score, 85.5);
    expect(find.textContaining('Enter a'), findsNothing);
    expect(find.textContaining('Use up to 2'), findsNothing);
  });

  testWidgets('configured maximum applies to small and fractional scales', (
    tester,
  ) async {
    double? score;
    await _showInput(tester, maximum: 5, onChanged: (value) => score = value);
    await tester.enterText(find.byType(EditableText), '5.01');
    await tester.pump();
    expect(score, isNull);
    expect(find.text('Enter a score from 0 to 5.'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '4.75');
    await tester.pump();
    expect(score, 4.75);
  });

  testWidgets(
    'parent rebuilds retain the decimal being edited and external values restore',
    (tester) async {
      double? score = 8;
      late StateSetter rebuild;
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: StatefulBuilder(
            builder: (context, update) {
              rebuild = update;
              return EvaluationScoreInput(
                label: 'Technique',
                maximum: 100,
                value: score,
                onChanged: (value) => update(() => score = value),
              );
            },
          ),
        ),
      );
      await tester.enterText(find.byType(EditableText), '8.');
      await tester.pump();
      expect(
        tester.widget<ShadInput>(find.byType(ShadInput)).controller!.text,
        '8.',
      );
      rebuild(() => score = 3.75);
      await tester.pump();
      expect(
        tester.widget<ShadInput>(find.byType(ShadInput)).controller!.text,
        '3.75',
      );
    },
  );

  testWidgets(
    'Next and Done traverse fields without submitting or skipping errors',
    (tester) async {
      final second = GlobalKey<EvaluationScoreInputState>();
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: Column(
            children: [
              EvaluationScoreInput(
                label: 'Technique',
                maximum: 100,
                value: null,
                onChanged: (_) {},
                onNext: () => second.currentState!.requestScoreFocus(),
              ),
              EvaluationScoreInput(
                key: second,
                label: 'Clarity',
                maximum: 10,
                value: null,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );
      final firstField = find.byType(EditableText).first;
      final lastField = find.byType(EditableText).last;
      await tester.enterText(firstField, '101');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        tester.widget<EditableText>(firstField).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(firstField, '87.5');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(lastField).focusNode.hasFocus, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(lastField).focusNode.hasFocus,
        isFalse,
      );
      await tester.tap(firstField);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.widget<EditableText>(lastField).focusNode.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        tester.widget<EditableText>(firstField).focusNode.hasFocus,
        isTrue,
      );
    },
  );

  testWidgets('iPhone numeric keypad has visible Next and Done controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var next = false;
    await pumpDefensysWidget(
      tester,
      DefensysShadcnScope(
        child: EvaluationScoreInput(
          label: 'Technique',
          maximum: 100,
          value: null,
          onChanged: (_) {},
          onNext: () => next = true,
        ),
      ),
    );
    await tester.tap(find.byType(EditableText));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    // The bundled toolbar reads the real PlatformDispatcher instead of the
    // test view's metrics. Mirror the simulated OS height in its notifier.
    final dynamic toolbar = tester.state(find.byType(ShadKeyboardToolbar));
    toolbar.keyboardHeight.value = 300.0;
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(next, isTrue);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('temporarily disabled inputs preserve the entered text', (
    tester,
  ) async {
    await _showInput(tester, initial: 87.5, enabled: false);
    expect(tester.widget<ShadInput>(find.byType(ShadInput)).enabled, isFalse);
    expect(
      tester.widget<ShadInput>(find.byType(ShadInput)).controller!.text,
      '87.5',
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('score entry fits at $width in ${dark ? 'dark' : 'light'} mode', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        await pumpDefensysWidget(
          tester,
          DefensysShadcnScope(
            child: RepaintBoundary(
              key: const ValueKey('score-input-preview'),
              child: ColoredBox(
                color: dark
                    ? DefensysTokens.mistSurface
                    : DefensysTokens.surface,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EvaluationScoreInput(
                        label: 'Technique',
                        description:
                            'Apply the rubric guidelines when entering a score.',
                        maximum: 100,
                        value: 87.5,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 24),
                      EvaluationScoreInput(
                        label:
                            'Technical understanding and individual contribution',
                        maximum: 10,
                        value: null,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        );
        await capturePreview(
          tester,
          find.byKey(const ValueKey('score-input-preview')),
          'typed-score-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
        final longLabel = find.text(
          'Technical understanding and individual contribution',
        );
        final scoreField = find.byType(ShadInput).last;
        final maximum = find.text('/ 10');
        expect(
          tester.getRect(scoreField).left,
          greaterThan(tester.getRect(longLabel).right),
        );
        expect(
          tester.getRect(scoreField).top,
          lessThanOrEqualTo(tester.getRect(longLabel).top),
        );
        expect(
          tester.getRect(maximum).left,
          greaterThan(tester.getRect(scoreField).right),
        );
        if (width == 320) {
          expect(tester.getSize(longLabel).height, greaterThan(30));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
