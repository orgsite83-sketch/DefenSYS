import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_deliverable_choices.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_minutes_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('file format uses a shadcn select at narrow width', (tester) async {
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

  testWidgets('post-defense rule exposes both stored values', (tester) async {
    var rule = 'all_pass';
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(16),
          child: StageVerdictConditionChoices(
            value: rule,
            onChanged: (value) => update(() => rule = value),
          ),
        ),
      ),
    );

    expect(find.text('All passing teams'), findsOneWidget);
    expect(find.text('Approved with revisions only'), findsOneWidget);
    await tester.tap(find.text('Approved with revisions only'));
    await tester.pumpAndSettle();
    expect(rule, 'revisions_only');
    await tester.tap(find.text('All passing teams'));
    await tester.pumpAndSettle();
    expect(rule, 'all_pass');
  });

  testWidgets('locked rule and minutes fields cannot change', (tester) async {
    final number = TextEditingController(text: 'MINUTES');
    final name = TextEditingController(text: 'Signed Minutes');
    addTearDown(number.dispose);
    addTearDown(name.dispose);
    var rule = 'all_pass';
    var expanded = false;
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          child: Column(
            children: [
              StageVerdictConditionChoices(
                value: rule,
                enabled: false,
                onChanged: (value) => update(() => rule = value),
              ),
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

    await tester.tap(find.text('Approved with revisions only'));
    await tester.pumpAndSettle();
    expect(rule, 'all_pass');
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
