import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/screens/app/student/team_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class _StaleStageNotifier extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    stageOptions: ['Concept Proposal'],
    selectedStage: 'Concept Proposal',
  );

  @override
  Future<void> fetchDeliverables({
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

final _studentWithoutStages = <String, dynamic>{
  'student': {'id': 1, 'name': 'Alex Student'},
  'team': {
    'id': 7,
    'name': 'Team SafeCity',
    'projectTitle': 'Smart City IoT Infrastructure',
    'isCapstone': true,
    'currentStage': 'Concept Proposal',
    'readyForStage': 'Concept Proposal',
    'adviserName': 'Ricardo Fontanilla',
  },
  'members': <Map<String, dynamic>>[],
  'stage_options': <String>[],
  'stages': <Map<String, dynamic>>[],
  'current_stage': 'Concept Proposal',
};

void main() {
  testWidgets('Team tab shows no stage when configured stages are empty', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 500,
        height: 900,
        child: TeamTab(studentData: _studentWithoutStages),
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_StaleStageNotifier.new),
      ],
    );

    expect(find.text('No defense stages configured yet'), findsOneWidget);
    expect(find.text('Concept Proposal'), findsNothing);
    expect(find.text('View Details'), findsNothing);
    expect(find.textContaining('Awaiting schedule assignment'), findsNothing);
  });

  testWidgets('Stages tab hides status and endorsement when no stage exists', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 400,
        height: 900,
        child: StudentEventsTab(
          isCapstone: true,
          studentData: _studentWithoutStages,
        ),
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(_StaleStageNotifier.new),
      ],
    );

    expect(find.text('No defense stages configured yet'), findsOneWidget);
    expect(find.textContaining('Defense Status for'), findsNothing);
    expect(find.text('Active Stage Deliberation'), findsNothing);
    expect(find.text('Awaiting Adviser Endorsement'), findsNothing);
    expect(find.text('Concept Proposal'), findsNothing);
    expect(find.text('Schedule'), findsNothing);
  });
}
