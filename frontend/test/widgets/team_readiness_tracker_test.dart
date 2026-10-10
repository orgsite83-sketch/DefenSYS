import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/team_readiness_tracker.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';

void main() {
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
        MaterialApp(
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
