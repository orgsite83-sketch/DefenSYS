import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/schedule_run_container.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';

void main() {
  for (final assessed in [false, true]) {
    testWidgets(
      'ScheduleRunContainer shows current stage with assessed=$assessed',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final state = DefenseSchedulerState(
          defenseStages: const [
            {
              'id': 1,
              'label': 'Concept Proposal',
              'display_order': 1,
              'is_active': true,
              'is_officially_complete': false,
              'endorsed_teams_count': 0,
            },
            {
              'id': 2,
              'label': 'Project Proposal',
              'display_order': 2,
              'is_active': true,
              'is_officially_complete': false,
              'endorsed_teams_count': 0,
            },
          ],
          rubrics: const [
            {
              'id': 10,
              'name': 'Project Panel Rubric',
              'scope': 'capstone',
              'evaluation_type': 'panel',
              'defense_stage_id': 2,
            },
            {
              'id': 11,
              'name': 'Project Adviser Rubric',
              'scope': 'capstone',
              'evaluation_type': 'adviser',
              'defense_stage_id': 2,
            },
            {
              'id': 12,
              'name': 'Project Peer Rubric',
              'scope': 'capstone',
              'evaluation_type': 'peer',
              'defense_stage_id': 2,
            },
          ],
          teams: [
            {
              'id': 101,
              'name': 'Team BioPulse',
              'level': 'Capstone 1',
              'ready_for_stage': 'Project Proposal',
              'current_defense_stage': 'Project Proposal',
              if (assessed)
                'stage_progress': {'Project Proposal': 'awaiting_completion'},
              if (assessed) 'eligible_stages': <String>[],
            },
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: ShadApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ScheduleRunContainer(
                    state: state,
                    scope: 'capstone',
                    stageId: 2,
                    rubricId: 10,
                    adviserRubricId: 11,
                    capstonePeerRubricId: 12,
                    peerRubricId: null,
                    documenterId: null,
                    selectedPanelistIds: const {},
                    eventController: TextEditingController(),
                    panelWeightController: TextEditingController(text: '50'),
                    peerWeightController: TextEditingController(text: '20'),
                    dateController: TextEditingController(text: '2026-10-15'),
                    timeController: TextEditingController(text: '09:00'),
                    durationController: TextEditingController(text: '30'),
                    roomController: TextEditingController(text: 'Room 301'),
                    pitTemplateController: TextEditingController(),
                    planSlots: const [],
                    showFinalPreview: false,
                    canScheduleScope: (_, __) => true,
                    scheduleNoticeMessage: (_) => '',
                    onScopeChanged: (_) {},
                    onStageChanged: (_) {},
                    onRubricChanged: (_) {},
                    onAdviserRubricChanged: (_) {},
                    onCapstonePeerRubricChanged: (_) {},
                    onPeerRubricChanged: (_) {},
                    onDocumenterChanged: (_) {},
                    onPanelistsChanged: (_) {},
                    onPlanSlotsChanged: (_) {},
                    onShowFinalPreviewChanged: (_) {},
                    onPrefillCapstoneStageRubrics: () async {},
                    onPrefillPitEventConfig: () async {},
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // The selected button should show 'Project Proposal (current stage)'
        expect(find.text('Project Proposal (current stage)'), findsOneWidget);
        final eligibilityNotice = find.textContaining(
          'No teams are eligible to schedule',
        );
        expect(eligibilityNotice, assessed ? findsOneWidget : findsNothing);
        expect(
          find.textContaining(
            'Teams must have pre-defense deliverables approved',
          ),
          findsNothing,
        );

        // Tap to open dropdown
        await tester.tap(find.text('Project Proposal (current stage)'));
        await tester.pumpAndSettle();

        // Now options are visible
        expect(find.text('Concept Proposal'), findsOneWidget);
        // In dropdown, the option also has '(current stage)'
        expect(find.text('Project Proposal (current stage)'), findsWidgets);
      },
    );
  }
}
