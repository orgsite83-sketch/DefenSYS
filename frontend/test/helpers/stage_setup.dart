import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

bool stagePublishEnabled(WidgetTester tester) {
  if (find.text('Publish stage').evaluate().isEmpty) return false;
  return tester
          .widget<ShadButton>(
            find
                .ancestor(
                  of: find.text('Publish stage'),
                  matching: find.byType(ShadButton),
                )
                .first,
          )
          .onPressed !=
      null;
}

Future<void> chooseStagePublication(WidgetTester tester, bool published) async {
  final originalTab = [0, 1, 2].firstWhere(
    (tab) =>
        find.byKey(ValueKey('stage-dialog-step-$tab')).evaluate().isNotEmpty ||
        find.byKey(ValueKey('stage-editor-step-$tab')).evaluate().isNotEmpty,
  );
  if (originalTab != 0) {
    await tester.ensureVisible(find.text('1. Stage Details'));
    await tester.tap(find.text('1. Stage Details'));
    await tester.pumpAndSettle();
  }
  final toggle = find.byKey(const ValueKey('stage-publication-switch'));
  if (tester.widget<ShadSwitch>(toggle).value != published) {
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
  if (originalTab != 0) {
    final label = originalTab == 1 ? '2. Grading & Rubrics' : '3. Deliverables';
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }
}

Future<void> chooseStageMinutes(WidgetTester tester, bool required) async {
  final toggle = find.byKey(const ValueKey('stage-minutes-switch'));
  if (tester.widget<ShadSwitch>(toggle).value != required) {
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
}

Future<void> chooseStageRubrics(WidgetTester tester) async {
  for (final role in ['panel', 'adviser', 'peer']) {
    final picker = find.byKey(ValueKey('$role-rubric-0'));
    if (picker.evaluate().isEmpty) continue;
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test $role rubric').last);
    await tester.pumpAndSettle();
  }
}
