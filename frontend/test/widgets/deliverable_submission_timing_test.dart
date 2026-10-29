import 'package:defensys/widgets/repository/deliverable_timing_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('retired timing values cannot enable a scheduling bypass', (
    tester,
  ) async {
    var material = false;
    var timing = 'defense';
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, update) => Column(
          children: [
            DefenseMaterialToggle(
              value: material,
              onChanged: (value) => update(() => material = value),
            ),
            DeliverableTimingFields(
              timing: timing,
              hoursBefore: 72,
              showTimingChoices: true,
              onTimingChanged: (value) => timing = value,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Before endorsement'), findsNothing);
    expect(find.text('Before scheduled defense'), findsNothing);
    expect(
      find.textContaining('adviser/instructor acceptance'),
      findsOneWidget,
    );
    await tester.tap(find.text('Defense material for panelists'));
    await tester.pumpAndSettle();
    expect(material, true);
    expect(timing, 'defense');
    expect(tester.takeException(), isNull);
  });
}
