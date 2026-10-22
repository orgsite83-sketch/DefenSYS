import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_deliverable_choices.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_minutes_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('file format uses a shadcn select at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var format = 'any';
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(16),
          child: StageFileFormatPicker(
            value: format,
            onChanged: (value) => update(() => format = value),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Any file type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF document (.pdf)').last);
    await tester.pumpAndSettle();
    expect(format, 'pdf');
    expect(tester.takeException(), isNull);
  });

  testWidgets('post-defense files have no verdict exemption selector', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(16),
          child: const StagePostDefenseReviewNotice(),
        ),
      ),
    );

    expect(find.text('All passing teams'), findsNothing);
    expect(find.text('Approved with revisions only'), findsNothing);
    expect(find.textContaining('faculty acceptance'), findsOneWidget);
  });

  testWidgets('locked rule and minutes fields cannot change', (tester) async {
    final number = TextEditingController(text: 'MINUTES');
    final name = TextEditingController(text: 'Signed Minutes');
    addTearDown(number.dispose);
    addTearDown(name.dispose);
    var expanded = false;
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          child: Column(
            children: [
              const StagePostDefenseReviewNotice(),
              StageMinutesDeliverableCard(
                number: number,
                name: name,
                stageName: 'Proposal',
                enabled: false,
                expanded: expanded,
                onToggle: () => update(() => expanded = !expanded),
                onConfigure: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Approved with revisions only'), findsNothing);
    expect(
      find.byKey(const ValueKey('minutes-deliverable-number')),
      findsNothing,
    );
    await tester.tap(find.text('Signed Minutes').first);
    await tester.pumpAndSettle();
    expect(expanded, true);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('minutes-deliverable-number')),
          )
          .readOnly,
      true,
    );
    expect(find.text('Change in Stage Details'), findsOneWidget);
  });
}
