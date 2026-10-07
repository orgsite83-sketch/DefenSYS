import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_team_picker.dart';

void main() {
  final testTeams = [
    {
      'id': 1,
      'name': 'Team BioPulse',
      'adviser': 10,
      'adviser_name': 'Prof Smith',
      'project_title': 'AI Triage',
      'section': 'CS4A',
    },
    {
      'id': 2,
      'name': 'Team CodeLearners',
      'adviser': 10,
      'adviser_name': 'Prof Smith',
      'project_title': 'Event Hub',
      'section': 'CS4A',
    },
    {
      'id': 3,
      'name': 'Team SafeCity',
      'adviser': 20,
      'adviser_name': 'Prof Jones',
      'project_title': 'Smart City',
      'section': 'CS4B',
    },
  ];

  Widget buildPicker({
    Set<int> initialSelected = const {},
    Map<int, String> assignedElsewhere = const {},
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SchedulerTeamPicker(
          teams: testTeams,
          selected: initialSelected,
          assignedElsewhere: assignedElsewhere,
          sessionNumber: 1,
        ),
      ),
    );
  }

  testWidgets('renders shadcn styled select and clear buttons with icons', (tester) async {
    await tester.pumpWidget(buildPicker());
    await tester.pumpAndSettle();

    final selectButtonFinder = find.byKey(const ValueKey('session-select-shown-teams'));
    final clearButtonFinder = find.byKey(const ValueKey('session-clear-shown-teams'));

    expect(selectButtonFinder, findsOneWidget);
    expect(clearButtonFinder, findsOneWidget);

    final selectButton = tester.widget<ShadButton>(selectButtonFinder);
    final clearButton = tester.widget<ShadButton>(clearButtonFinder);

    // Both are ShadButton widgets with small size
    expect(selectButton.size, ShadButtonSize.sm);
    expect(clearButton.size, ShadButtonSize.sm);

    // Verify icons
    expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);

    // Initially, select is enabled and clear is disabled (nothing selected)
    expect(selectButton.enabled, isTrue);
    expect(clearButton.enabled, isFalse);

    // Tap "Select shown teams"
    await tester.tap(selectButtonFinder);
    await tester.pumpAndSettle();

    // Now clear button should be enabled
    final clearButtonAfterSelect = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButtonAfterSelect.enabled, isTrue);

    // Tap "Clear shown teams"
    await tester.tap(clearButtonFinder);
    await tester.pumpAndSettle();

    // Clear button should be disabled again
    final clearButtonAfterClear = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButtonAfterClear.enabled, isFalse);
  });

  testWidgets('initial selected teams enable the clear button', (tester) async {
    await tester.pumpWidget(buildPicker(initialSelected: {1}));
    await tester.pumpAndSettle();

    final clearButtonFinder = find.byKey(const ValueKey('session-clear-shown-teams'));
    final clearButton = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButton.enabled, isTrue);

    await tester.tap(clearButtonFinder);
    await tester.pumpAndSettle();

    final clearButtonAfterClear = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButtonAfterClear.enabled, isFalse);
  });
}

