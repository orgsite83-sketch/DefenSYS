import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/screens/web/faculty/dashboard_widgets.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scope in ['pit', 'capstone']) {
      testWidgets(
        '$scope dashboard and team badges agree in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          for (final code in [
            'awaiting_files',
            'awaiting_endorsement',
            'ready_to_schedule',
            'scheduled',
            'awaiting_evaluation',
            'evaluating',
            'awaiting_verdict',
            'awaiting_concept_selection',
            'ready_to_schedule_redefense',
            'grading_incomplete',
            'awaiting_completion',
            'pending_post_defense',
            'changes_requested',
            'revisions_pending',
            'redefense_required',
            'completed',
            'failed',
            'project_rejected',
            'paused',
            'postponed',
            'no_show',
            'cancelled',
            'archived',
            'needs_review',
          ]) {
            final stage = <String, dynamic>{
              'stage_label': 'Current event',
              'deliverables_configured': true,
              'assessment_progress': {'display_status': code},
              if (code == 'needs_review')
                'post': [
                  {
                    'uploaded': true,
                    'type': 'post',
                    'submission': {'status': 'pending'},
                  },
                ],
            };
            final status = TeamWorkflowStatus.fromStage(stage, scope: scope);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
                home: Scaffold(
                  body: Column(
                    children: [
                      TeamRequirementBadge(
                        scope: scope,
                        team: {
                          'current_stage': 'Current event',
                          'stages': [stage],
                          // A historical workspace selection must not change the dashboard.
                          'selected_stage': {
                            'stage_label': 'Past event',
                            'assessment_progress': {
                              'display_status': 'completed',
                            },
                          },
                        },
                      ),
                      TeamWorkflowBadge(status: status),
                    ],
                  ),
                ),
              ),
            );
            expect(find.text(status.label), findsNWidgets(2), reason: code);
            final badges = tester
                .widgetList<TeamWorkflowBadge>(find.byType(TeamWorkflowBadge))
                .toList();
            expect(
              badges.first.status.code,
              badges.last.status.code,
              reason: code,
            );
            expect(
              badges.first.status.tone,
              badges.last.status.tone,
              reason: code,
            );
            final texts = tester
                .widgetList<Text>(find.text(status.label))
                .toList();
            expect(
              texts.first.style?.color,
              texts.last.style?.color,
              reason: code,
            );
            expect(tester.takeException(), isNull, reason: code);
          }
        },
      );
    }
  }

  test('palette distinguishes waiting, actions, corrections and outcomes', () {
    for (final code in [
      'awaiting_files',
      'awaiting_evaluation',
      'awaiting_verdict',
      'awaiting_results',
      'awaiting_completion',
      'pending_post_defense',
    ]) {
      expect(
        TeamWorkflowStatus.describe(code).tone,
        WorkflowStatusTone.neutral,
        reason: code,
      );
    }
    for (final code in [
      'needs_review',
      'awaiting_endorsement',
      'scheduled',
      'evaluating',
    ]) {
      expect(
        TeamWorkflowStatus.describe(code).tone,
        WorkflowStatusTone.active,
        reason: code,
      );
    }
    for (final code in [
      'changes_requested',
      'grading_incomplete',
      'revisions_pending',
      'redefense_required',
    ]) {
      expect(
        TeamWorkflowStatus.describe(code).tone,
        WorkflowStatusTone.attention,
        reason: code,
      );
    }
    expect(
      TeamWorkflowStatus.describe('completed').tone,
      WorkflowStatusTone.success,
    );
    expect(
      TeamWorkflowStatus.describe('failed').tone,
      WorkflowStatusTone.destructive,
    );
  });
}
