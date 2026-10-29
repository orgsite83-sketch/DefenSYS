import 'package:defensys/widgets/academic/capstone_history_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';

const options = <String, dynamic>{
  'intakes': [
    {'id': 3, 'label': 'Intake: 2nd Semester, A.Y. 2025–2026'},
    {'id': 7, 'label': 'Intake: 2nd Semester, A.Y. 2026–2027'},
  ],
  'phases': [
    {'value': 'capstone_1', 'label': 'Capstone 1'},
    {'value': 'capstone_2', 'label': 'Capstone 2'},
  ],
  'stages': [
    {
      'value': '3:1',
      'label': 'Capstone 1 · Concept Proposal · 2nd Sem 2025–2026',
    },
  ],
};

void main() {
  testWidgets('phase and intake changes reset dependent stage selection', (
    tester,
  ) async {
    List<String>? selected;
    await pumpDefensysWidget(
      tester,
      CapstoneHistoryFilters(
        options: options,
        intake: '3',
        phase: '',
        stage: '3:1',
        onChanged: (i, p, s) => selected = [i, p, s],
      ),
    );
    await tester.tap(find.byType(DropdownButton<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capstone 2').last);
    await tester.pumpAndSettle();
    expect(selected, ['3', 'capstone_2', '']);
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intake: 2nd Semester, A.Y. 2026–2027').last);
    await tester.pumpAndSettle();
    expect(selected, ['7', '', '']);
  });

  testWidgets('history controls fit narrow layouts with long period labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: CapstoneHistoryFilters(
          options: options,
          intake: '3',
          phase: '',
          stage: '',
          onChanged: (_, _, _) {},
        ),
      ),
    );
    expect(find.text('All phases'), findsOneWidget);
    expect(find.text('All stages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
