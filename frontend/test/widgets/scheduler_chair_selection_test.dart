import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/schedule_run_container.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';

void main() {
  testWidgets('ScheduleRunContainer shows Presiding Chair chips defaulting to first panelist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final eventController = TextEditingController();
    final panelWeightController = TextEditingController(text: '80');
    final peerWeightController = TextEditingController(text: '20');
    final dateController = TextEditingController(text: '2026-06-18');
    final timeController = TextEditingController(text: '08:00');
    final durationController = TextEditingController(text: '60');
    final roomController = TextEditingController(text: 'Room 301');
    final pitTemplateController = TextEditingController();

    final selectedPanelistIds = <int>{};
    final planSlots = <Map<String, dynamic>>[];

    final testState = DefenseSchedulerState(
      defenseStages: const [
        {'id': 1, 'label': 'Project Proposal'},
      ],
      panelists: const [
        {'id': 101, 'name': 'Dr. Alice Guo', 'username': 'aguo'},
        {'id': 102, 'name': 'Prof. Bob Smith', 'username': 'bsmith'},
        {'id': 103, 'name': 'Engr. Charlie Day', 'username': 'cday'},
      ],
      teams: const [
        {
          'id': 1,
          'name': 'Team Alpha',
          'project_title': 'Project Alpha',
          'ready_for_stage': 'Project Proposal',
          'is_endorsed': true,
        },
      ],
      rubrics: const [
        {'id': 10, 'scope': 'capstone', 'defense_stage_id': 1, 'title': 'Rubric 1'},
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: ScheduleRunContainer(
                    state: testState,
                    scope: 'capstone',
                    stageId: 1,
                    rubricId: 10,
                    adviserRubricId: null,
                    capstonePeerRubricId: null,
                    peerRubricId: null,
                    documenterId: null,
                    selectedPanelistIds: selectedPanelistIds,
                    eventController: eventController,
                    panelWeightController: panelWeightController,
                    peerWeightController: peerWeightController,
                    dateController: dateController,
                    timeController: timeController,
                    durationController: durationController,
                    roomController: roomController,
                    pitTemplateController: pitTemplateController,
                    planSlots: planSlots,
                    showFinalPreview: false,
                    canScheduleScope: (_, __) => true,
                    scheduleNoticeMessage: (_) => '',
                    onScopeChanged: (_) {},
                    onStageChanged: (_) {},
                    onRubricChanged: (_) {},
                    onAdviserRubricChanged: (_) {},
                    onCapstonePeerRubricChanged: (_) {},
                    onPeerRubricChanged: (_) {},
                    onPanelistsChanged: (ids) {
                      setState(() {
                        selectedPanelistIds.clear();
                        selectedPanelistIds.addAll(ids);
                      });
                    },
                    onPlanSlotsChanged: (_) {},
                    onShowFinalPreviewChanged: (_) {},
                    onPrefillCapstoneStageRubrics: () async {},
                    onPrefillPitEventConfig: () async {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    // Initial state: no chair section shown when no panelists selected
    expect(find.text('👑 Presiding Panel Chair'), findsNothing);

    // Tap Dr. Alice Guo to select her
    await tester.tap(find.text('Dr. Alice Guo'));
    await tester.pumpAndSettle();

    // Now Presiding Chair selector appears with Dr. Alice Guo as default Chair
    expect(find.text('👑 Presiding Panel Chair'), findsOneWidget);
    expect(find.text('👑 Dr. Alice Guo (Chair)'), findsOneWidget);

    // Tap Prof. Bob Smith to add him to panelists
    await tester.tap(find.text('Prof. Bob Smith'));
    await tester.pumpAndSettle();

    expect(find.text('Prof. Bob Smith'), findsWidgets);

    // Switch presiding chair to Prof. Bob Smith
    await tester.tap(find.text('Prof. Bob Smith').last);
    await tester.pumpAndSettle();

    expect(find.text('👑 Prof. Bob Smith (Chair)'), findsOneWidget);
  });
}
