import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/team_readiness_tracker.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import '../helpers/auth_test_overrides.dart';

void main() {
  testWidgets('PIT concept filters retain only matching teams in the event year', (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: authTestOverrides(),
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TeamReadinessTracker(
        state: DefenseSchedulerState(
          teams: [
            for (final entry in [
              (1, 'Replacement team', '1st Year', 'replacement_concepts_needed'),
              (2, 'Review team', '1st Year', 'concept_review_pending'),
              (3, 'Other year team', '2nd Year', 'replacement_concepts_needed'),
            ]) {
              'id': entry.$1, 'name': entry.$2,
              'level': '${entry.$3} PIT', 'year_level': entry.$3, 'section': 'Concept Section',
              'concept_workflows': {'PIT Concepts': {'enabled': true, 'status': entry.$4}},
            },
          ],
          pitEvents: const [{
            'event_name': 'PIT Concepts', 'year_level': '1st Year',
            'concept_config': {'enabled': true}, 'deliverables': [],
          }],
        ),
        scope: 'pit', activeStageOrEventName: 'PIT Concepts',
        onReviewTeamDeliverables: (_, _) {}, onSendReminder: (_, _) {}, isSendingReminder: false,
      )))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All defense workflows'));
    await tester.pumpAndSettle();
    expect(find.text('Instructor review pending'), findsOneWidget);
    await tester.tap(find.text('Replacement concepts needed').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concept Section'));
    await tester.pumpAndSettle();
    expect(find.text('Replacement team'), findsOneWidget);
    expect(find.text('Review team'), findsNothing);
    expect(find.text('Other year team'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT event without scheduling files is ready without endorsement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: authTestOverrides(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TeamReadinessTracker(
                state: DefenseSchedulerState(
                  teams: const [{
                    'id': 1,
                    'name': 'Team Alpha',
                    'level': '1st Year PIT',
                    'year_level': '1st Year',
                    'section': 'BSIT-1A',
                  }],
                  pitEvents: const [{
                    'event_name': 'System Concept Pitching',
                    'year_level': '1st Year',
                    'deliverables': [
                      {'deliverable_type': 'pre', 'required': true, 'requirement_timing': 'defense'},
                    ],
                  }],
                ),
                scope: 'pit',
                activeStageOrEventName: 'System Concept Pitching',
                onReviewTeamDeliverables: (_, _) {},
                onSendReminder: (_, _) {},
                isSendingReminder: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSIT-1A'));
    await tester.pumpAndSettle();
    final statusCell = find.byKey(
      const ValueKey('team-defense-status-1-System Concept Pitching'),
    );
    expect(
      find.descendant(of: statusCell, matching: find.text('Ready to Schedule')),
      findsOneWidget,
    );
    expect(find.text('Awaiting Endorsement'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (
      'awaiting_completion',
      false,
      'Awaiting completion',
      'approved',
      'Approved',
    ),
    ('grading_incomplete', false, 'Grading incomplete', 'approved', 'Approved'),
    (
      'revisions_pending',
      false,
      'Revisions pending',
      'approved_with_revisions',
      'Approved with Revisions',
    ),
    (
      'redefense_required',
      false,
      'Awaiting re-defense eligibility',
      'for_redefense',
      'For Re-defense',
    ),
    (
      'redefense_required',
      true,
      'Ready for Re-defense',
      'for_redefense',
      'For Re-defense',
    ),
    ('completed', false, 'Completed', 'approved', 'Approved'),
    ('failed', false, 'Failed', 'failed', 'Failed'),
    (
      'project_rejected',
      false,
      'Project Rejected',
      'project_rejected',
      'Project Rejected',
    ),
    ('failed', true, 'Ready for Retake', 'failed', 'Failed'),
  ]) {
    testWidgets('queue displays ${scenario.$3} after assessment', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: authTestOverrides(),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TeamReadinessTracker(
                  state: DefenseSchedulerState(
                    teams: [
                      {
                        'id': 1,
                        'name': 'Team CodeLearners',
                        'level': '4th Year Capstone',
                        'section': 'BSIT-4A',
                        'ready_for_stage': 'Project Proposal',
                        'stage_progress': {'Project Proposal': scenario.$1},
                        'stage_verdicts': {'Project Proposal': scenario.$4},
                        'eligible_stages': scenario.$2
                            ? ['Project Proposal']
                            : <String>[],
                      },
                    ],
                  ),
                  scope: 'capstone',
                  activeStageOrEventName: 'Project Proposal',
                  onReviewTeamDeliverables: (_, _) {},
                  onSendReminder: (_, _) {},
                  isSendingReminder: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('BSIT-4A'));
      await tester.pumpAndSettle();
      final statusCell = find.byKey(
        const ValueKey('team-defense-status-1-Project Proposal'),
      );
      expect(
        find.descendant(of: statusCell, matching: find.text(scenario.$3)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: statusCell, matching: find.text(scenario.$5)),
        findsOneWidget,
      );
      expect(find.text('Ready for Defense'), findsNothing);
      expect(find.text('Awaiting Endorsement'), findsNothing);
      expect(find.text('Remind'), findsNothing);
      expect(find.text('Needs Endorsement'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
