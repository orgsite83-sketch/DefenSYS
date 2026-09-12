import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/pipeline_position_selector.dart';

void main() {
  final sampleStages = [
    {
      'id': 1,
      'label': 'Concept Proposal',
      'display_order': 1,
      'is_locked': true,
      'status': 'locked',
    },
    {
      'id': 2,
      'label': 'Project Proposal',
      'display_order': 2,
      'is_locked': false,
      'status': 'draft',
    },
    {
      'id': 3,
      'label': 'Exhibit',
      'display_order': 3,
      'is_locked': false,
      'status': 'draft',
    },
    {
      'id': 4,
      'label': 'Colloquium',
      'display_order': 4,
      'is_locked': false,
      'status': 'draft',
    },
  ];

  Widget buildTestWidget({
    required int selectedPosition,
    required ValueChanged<int> onPositionChanged,
    int minPosition = 2,
    bool editing = true,
    int? initialOrder = 2,
    bool isLocked = false,
    String stageName = 'Project Proposal',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: PipelinePositionSelector(
              selectedPosition: selectedPosition,
              totalSlots: 4,
              existingStages: sampleStages,
              currentStageName: stageName,
              editing: editing,
              initialOrder: initialOrder,
              isLocked: isLocked,
              minPosition: minPosition,
              onPositionChanged: onPositionChanged,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders stage names, active stage, and locked state accurately', (tester) async {
    int? changedPosition;

    await tester.pumpWidget(
      buildTestWidget(
        selectedPosition: 2,
        onPositionChanged: (pos) => changedPosition = pos,
      ),
    );
    await tester.pumpAndSettle();

    // Verify stage names are visible
    expect(find.text('Concept Proposal'), findsWidgets);
    expect(find.text('Project Proposal'), findsWidgets);
    expect(find.text('Exhibit'), findsWidgets);

    // Verify Concept Proposal has locked status
    expect(find.text('Locked (Completed)'), findsOneWidget);

    // Verify active stage indicator
    expect(find.text('Active Stage'), findsOneWidget);

    // Verify nudge buttons are present
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('tapping "Later" nudge button advances position to 3', (tester) async {
    int? changedPosition;

    await tester.pumpWidget(
      buildTestWidget(
        selectedPosition: 2,
        onPositionChanged: (pos) => changedPosition = pos,
      ),
    );
    await tester.pumpAndSettle();

    final laterButton = find.text('Later');
    expect(laterButton, findsOneWidget);

    await tester.tap(laterButton);
    await tester.pumpAndSettle();

    expect(changedPosition, 3);
  });

  testWidgets('tapping "Earlier" when at minPosition=2 does not move to 1', (tester) async {
    int? changedPosition;

    await tester.pumpWidget(
      buildTestWidget(
        selectedPosition: 2,
        minPosition: 2,
        onPositionChanged: (pos) => changedPosition = pos,
      ),
    );
    await tester.pumpAndSettle();

    final earlierButton = find.text('Earlier');
    expect(earlierButton, findsOneWidget);

    await tester.tap(earlierButton);
    await tester.pumpAndSettle();

    // Should NOT trigger callback because position 1 is locked
    expect(changedPosition, isNull);
  });

  testWidgets('tapping an unlocked stage card (Exhibit) moves position to it', (tester) async {
    int? changedPosition;

    await tester.pumpWidget(
      buildTestWidget(
        selectedPosition: 2,
        onPositionChanged: (pos) => changedPosition = pos,
      ),
    );
    await tester.pumpAndSettle();

    // Tap on Exhibit (which is at position 3)
    final exhibitNode = find.text('Exhibit').first;
    await tester.tap(exhibitNode);
    await tester.pumpAndSettle();

    expect(changedPosition, 3);
  });

  testWidgets('tapping a locked stage card (Concept Proposal) is blocked', (tester) async {
    int? changedPosition;

    await tester.pumpWidget(
      buildTestWidget(
        selectedPosition: 2,
        minPosition: 2,
        onPositionChanged: (pos) => changedPosition = pos,
      ),
    );
    await tester.pumpAndSettle();

    // Tap on Concept Proposal
    final conceptNode = find.text('Concept Proposal').first;
    await tester.tap(conceptNode);
    await tester.pumpAndSettle();

    // Callback should NOT be invoked
    expect(changedPosition, isNull);
  });
}
