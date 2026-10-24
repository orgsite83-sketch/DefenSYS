import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/pipeline_position_selector.dart';

void main() {
  Future<void> pumpPosition(WidgetTester tester, int count, {bool locked = false}) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 320,
      child: PipelinePositionSelector(selectedPosition: count, totalSlots: count,
        existingStages: List.generate(count, (i) => {'id': i + 1, 'label': 'Milestone ${i + 1}'}),
        currentStageName: 'Current milestone', onPositionChanged: (_) {}, isLocked: locked,
        lockReason: locked ? 'This stage already has assessment records.' : null))))));

  testWidgets('adding more stages does not make stage details taller', (tester) async {
    await pumpPosition(tester, 1);
    final firstHeight = tester.getSize(find.byType(PipelinePositionSelector)).height;
    await pumpPosition(tester, 20);
    expect(tester.getSize(find.byType(PipelinePositionSelector)).height, firstHeight);
    expect(firstHeight, lessThan(100));
    expect(find.text('Position 20 of 20'), findsOneWidget);
    expect(find.text('Manage the order on the main stage sequence.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked position explains why ordering is protected', (tester) async {
    await pumpPosition(tester, 4, locked: true);
    expect(find.text('This stage already has assessment records.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
