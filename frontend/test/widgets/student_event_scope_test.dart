import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/screens/app/student/team_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class _PastEventSelection extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    stageOptions: ['Poster Showcase', 'System Pitching'],
    selectedStage: 'Poster Showcase',
  );

  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

final _data = <String, dynamic>{
  'student': {'id': 1, 'name': 'Student'},
  'team': {
    'id': 1,
    'name': 'PIT Team',
    'isCapstone': false,
    'currentStage': 'System Pitching',
  },
  'current_stage': 'System Pitching',
  'year_level': '3rd Year',
  'members': <Map<String, dynamic>>[],
  'stage_options': ['Poster Showcase', 'System Pitching'],
  'schedule': {
    'stage': 'Poster Showcase',
    'date': '2026-10-14',
    'room': 'Old Room',
  },
  'grades': {
    'stage': 'Poster Showcase',
    'result': 'PASSED',
    'is_published': true,
  },
  'stages': [
    {
      'stage_label': 'Poster Showcase',
      'is_officially_complete': true,
      'grade': {'result': 'PASSED', 'final_grade': 90},
      'schedule': {'date': '2026-10-14', 'room': 'Old Room'},
    },
    {'stage_label': 'System Pitching', 'is_officially_complete': false},
  ],
};

void main() {
  testWidgets('An earlier PIT event needs its own completion evidence', (
    tester,
  ) async {
    final data = {..._data, 'stages': <Map<String, dynamic>>[]};
    await pumpDefensysWidget(
      tester,
      StudentEventsTab(
        isCapstone: false,
        studentData: data,
        initialStage: 'Poster Showcase',
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_PastEventSelection.new),
      ],
    );
    expect(find.text('Milestone Cleared & Evaluated'), findsNothing);
    expect(find.textContaining('Official Grade:'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Team shows the current event published result', (tester) async {
    final data = {
      ..._data,
      'stages': [
        {
          'stage_label': 'System Pitching',
          'grade': {'status': 'published', 'result': 'PASSED', 'final_grade': 92},
        },
      ],
    };
    await pumpDefensysWidget(tester, TeamTab(studentData: data), overrides: [
      capstoneDeliverablesProvider.overrideWith(_PastEventSelection.new),
    ]);
    expect(find.textContaining('Score: 92'), findsOneWidget);
    expect(find.text('OCT'), findsNothing);
  });

  testWidgets('Events opens current event despite shared past selection', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      StudentEventsTab(isCapstone: false, studentData: _data),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_PastEventSelection.new),
      ],
    );

    expect(find.text('Defense Status for System Pitching'), findsOneWidget);
    expect(
      find.text('Defense schedule will be posted once assigned.'),
      findsOneWidget,
    );
    expect(find.textContaining('Old Room'), findsNothing);

    await tester.tap(find.text('Poster Showcase'));
    await tester.pump();
    expect(find.text('Defense Status for Poster Showcase'), findsOneWidget);
    expect(find.textContaining('Old Room'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Explicit event links still open the requested archive', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      StudentEventsTab(
        isCapstone: false,
        studentData: _data,
        initialStage: 'Poster Showcase',
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_PastEventSelection.new),
      ],
    );
    expect(find.text('Defense Status for Poster Showcase'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Team current event never displays a previous event pass or date',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        TeamTab(studentData: _data),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(_PastEventSelection.new),
        ],
      );
      expect(find.text('System Pitching'), findsOneWidget);
      expect(find.textContaining('Cleared'), findsNothing);
      expect(
        find.textContaining('Awaiting schedule assignment'),
        findsOneWidget,
      );
      expect(find.text('OCT'), findsNothing);
    },
  );
}
