import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_minutes_settings.dart';
import 'package:defensys/widgets/defense/system_defense_records.dart';

Widget host(Widget child, {bool dark = false}) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets(
    'minutes requirement can be selected independently of student submissions',
    (tester) async {
      bool requiredMinutes = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => StageMinutesSettings(
              requiredMinutes: requiredMinutes,
              enabled: true,
              onChanged: (value) => setState(() => requiredMinutes = value),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Signed minutes required'));
      await tester.pump();
      expect(requiredMinutes, isTrue);
      expect(find.textContaining('Adds a system-generated'), findsOneWidget);
      await tester.tap(find.text('Minutes not required'));
      await tester.pump();
      expect(requiredMinutes, isFalse);
    },
  );

  testWidgets(
    'official minutes metadata is editable but PDF source and requirement are fixed',
    (tester) async {
      final number = TextEditingController(text: '5');
      final name = TextEditingController(text: 'Signed Minutes - Concept');
      addTearDown(number.dispose);
      addTearDown(name.dispose);
      bool configured = false;
      await tester.pumpWidget(
        host(
          StageMinutesDeliverableCard(
            number: number,
            name: name,
            stageName: 'Concept Proposal',
            enabled: true,
            onConfigure: () => configured = true,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('minutes-deliverable-number')),
        '12',
      );
      expect(number.text, '12');
      expect(find.text('Format: PDF'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('Required · Set in Stage Details'));
      expect(configured, isTrue);
    },
  );

  testWidgets('pending signed minutes have no student upload or PDF action', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SystemDefenseRecords(
          items: [
            {
              'id': '5',
              'label': 'Signed Minutes - Concept',
              'status_label': 'Awaiting adviser signature',
              'session_status': 'done',
              'completed': false,
            },
          ],
        ),
      ),
    );
    expect(
      find.text('Session finished · Awaiting adviser signature'),
      findsOneWidget,
    );
    expect(find.text('View signed PDF'), findsNothing);
    expect(find.byIcon(Icons.upload_file), findsNothing);
  });

  testWidgets('finalized record and configuration fit a narrow dark screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final number = TextEditingController(text: '5');
    final name = TextEditingController(text: 'Signed Minutes - Concept');
    addTearDown(number.dispose);
    addTearDown(name.dispose);
    await tester.pumpWidget(
      host(
        Column(
          children: [
            StageMinutesDeliverableCard(
              number: number,
              name: name,
              stageName: 'Concept Proposal',
              enabled: false,
              onConfigure: () {},
            ),
            const SystemDefenseRecords(
              items: [
                {
                  'id': '5',
                  'label': 'Signed Minutes - Concept',
                  'status_label': 'Finalized',
                  'session_status': 'done',
                  'completed': true,
                  'schedule_id': 1,
                },
              ],
            ),
          ],
        ),
        dark: true,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('minutes-deliverable-number')),
          )
          .readOnly,
      isTrue,
    );
    expect(find.text('View signed PDF'), findsOneWidget);
    expect(find.text('1/1 completed'), findsOneWidget);
  });
}
