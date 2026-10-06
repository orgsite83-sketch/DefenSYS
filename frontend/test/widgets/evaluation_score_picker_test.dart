import 'package:defensys/screens/app/panelist/widgets/evaluation_score_picker.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets(
    'Exact decimal scores survive opening, cancellation and explicit apply',
    (tester) async {
      double? score = 8.25;
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: StatefulBuilder(
            builder: (context, update) => EvaluationScorePicker(
              label: 'Technical competency',
              maximum: 10,
              value: score,
              onChanged: (value) => update(() => score = value),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Fine score'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsNWidgets(3));
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('8.25 / 10'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(score, 8.25);
      await tester.tap(find.text('+0.5'));
      await tester.pumpAndSettle();
      expect(score, 8.75);
      await tester.tap(find.text('Fine score'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply score'));
      await tester.pumpAndSettle();
      expect(score, 8.75);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(score, isNull);
      await tester.tap(find.text('Fine score'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(score, isNull);
    },
  );

  testWidgets(
    '100-point scales use touch wheels and reject a score above maximum',
    (tester) async {
      double? score = 100;
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: EvaluationScorePicker(
            label: 'Technical competency',
            maximum: 100,
            value: score,
            onChanged: (value) => score = value,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('score-value-100')), findsOneWidget);
      await tester.tap(find.text('Fine score'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CupertinoPicker).at(1),
        const Offset(0, -44),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Apply score'))
            .enabled,
        isFalse,
      );
      expect(score, 100);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
