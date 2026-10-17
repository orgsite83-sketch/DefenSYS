import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'post-defense uploads precede finalization, with reviews taking priority',
    () {
      for (final scope in ['pit', 'capstone']) {
        final post = <String, dynamic>{
          'id': 'FINAL',
          'type': 'post',
          'required': true,
          'uploaded': false,
        };
        final value = <String, dynamic>{
          'deliverables_configured': true,
          'assessment_progress': {'display_status': 'awaiting_completion'},
          'post': [post],
        };
        var status = TeamWorkflowStatus.fromStage(value, scope: scope);
        expect(status.label, 'Awaiting post-defense');
        expect(status.nextStep, contains('submit or correct'));
        post['uploaded'] = true;
        post['submission'] = {'status': 'pending'};
        expect(
          TeamWorkflowStatus.fromStage(value, scope: scope).label,
          '1 needs review',
        );
        post['submission'] = {'status': 'accepted'};
        expect(
          TeamWorkflowStatus.fromStage(value, scope: scope).label,
          'Awaiting completion',
        );
        post['uploaded'] = false;
        post['submission'] = null;
        value['assessment_progress'] = {'display_status': 'scheduled'};
        expect(
          TeamWorkflowStatus.fromStage(value, scope: scope).label,
          'Scheduled',
        );
        value['has_done_schedule'] = true;
        value['assessment_progress'] = {
          'display_status': 'awaiting_evaluation',
        };
        expect(
          TeamWorkflowStatus.fromStage(value, scope: scope).label,
          'Awaiting post-defense',
        );
        post['is_waived'] = true;
        expect(
          TeamWorkflowStatus.fromStage(value, scope: scope).label,
          'Awaiting evaluation',
        );
      }
    },
  );

  test(
    'pre and post reviews take priority, then restore completion status',
    () {
      for (final scope in ['pit', 'capstone']) {
        for (final combined in [false, true]) {
          final pre = {
            'type': 'pre',
            'uploaded': true,
            'locked': true,
            'submission': {'status': 'pending_review'},
          };
          final post = {
            'type': 'post',
            'uploaded': true,
            'locked': true,
            'submission': {'status': 'pending'},
          };
          final value = <String, dynamic>{
            'deliverables_configured': true,
            'assessment_progress': {'display_status': 'awaiting_completion'},
            if (combined)
              'deliverables': [pre, post]
            else ...{
              'pre': [pre],
              'post': [post],
            },
          };
          final team = <String, dynamic>{'selected_stage': value};
          final status = TeamWorkflowStatus.fromStage(value, scope: scope);
          expect(status.label, '2 needs review');
          expect(status.code, 'needs_review');
          expect(status.nextStep, contains('pre- and post-defense'));
          expect(DeliverablesTriageHelper.pendingReviewCount(team), 2);
          expect(
            DeliverablesTriageHelper.matchesFilter(
              team,
              TeamTriageFilter.needsReview,
            ),
            isTrue,
          );
          (pre['submission'] as Map)['status'] = 'accepted';
          expect(
            TeamWorkflowStatus.fromStage(value, scope: scope).label,
            '1 needs review',
          );
          (post['submission'] as Map)['status'] = 'accepted';
          expect(
            TeamWorkflowStatus.fromStage(value, scope: scope).label,
            'Awaiting completion',
          );
          expect(DeliverablesTriageHelper.pendingReviewCount(team), 0);
        }
      }
    },
  );

  test('review count uses current files within a grouped submission', () {
    final value = {
      'assessment_progress': {
        'display_status': 'completed',
        'is_completed': true,
      },
      'deliverables': [
        {
          'type': 'post',
          'submission': {
            'status': 'rejected',
            'files': [
              {'status': 'accepted'},
              {'status': 'pending'},
              {'status': 'submitted'},
              {'status': 'rejected'},
              {'status': 'pending', 'is_current': false},
            ],
          },
        },
        {
          'type': 'pre',
          'requirement_timing': 'defense',
          'submission': {'status': 'pending'},
        },
        {
          'type': 'post',
          'is_waived': true,
          'submission': {'status': 'pending'},
        },
        {'type': 'post', 'source': 'defense_minutes', 'uploaded': true},
      ],
    };
    expect(TeamWorkflowStatus.fromStage(value).label, '2 needs review');
    expect(TeamWorkflowStatus.pendingReviewCount(value), 2);
  });

  Map<String, dynamic> stage({String? fileStatus, bool endorsed = false}) => {
    'deliverables_configured': true,
    'endorsed': endorsed,
    'required_complete': fileStatus == 'accepted',
    'endorsement_review': {
      'can_review_and_endorse': fileStatus != null && fileStatus != 'rejected',
    },
    'pre': [
      {
        'type': 'pre',
        'required': true,
        'requirement_timing': 'scheduling',
        'uploaded': fileStatus != null,
        if (fileStatus != null) 'submission': {'status': fileStatus},
      },
    ],
  };

  test(
    'file review, endorsement and scheduling readiness retain different labels',
    () {
      final missing = TeamWorkflowStatus.fromStage(stage());
      expect(missing.code, 'awaiting_files');
      expect(missing.tone, WorkflowStatusTone.neutral);
      final pending = TeamWorkflowStatus.fromStage(
        stage(fileStatus: 'pending'),
      );
      expect(pending.code, 'needs_review');
      expect(pending.tone, WorkflowStatusTone.active);
      final accepted = TeamWorkflowStatus.fromStage(
        stage(fileStatus: 'accepted'),
      );
      expect(accepted.code, 'awaiting_endorsement');
      expect(accepted.tone, WorkflowStatusTone.active);
      final endorsed = TeamWorkflowStatus.fromStage(
        stage(fileStatus: 'accepted', endorsed: true),
      );
      expect(endorsed.code, 'ready_to_schedule');
      expect(endorsed.tone, WorkflowStatusTone.success);
    },
  );

  test('correctable requirements are amber; failed outcomes are red', () {
    expect(
      TeamWorkflowStatus.fromStage(stage(fileStatus: 'rejected')).tone,
      WorkflowStatusTone.attention,
    );
    for (final code in ['revisions_pending', 'for_redefense']) {
      expect(
        TeamWorkflowStatus.describe(code).tone,
        WorkflowStatusTone.attention,
      );
    }
    for (final code in ['failed', 'project_rejected']) {
      expect(
        TeamWorkflowStatus.describe(code).tone,
        WorkflowStatusTone.destructive,
      );
    }
  });

  test(
    'PIT without an endorsement requirement can proceed directly to scheduling',
    () {
      final value = stage()..['endorsement_required'] = false;
      expect(
        TeamWorkflowStatus.fromStage(value, scope: 'pit').code,
        'ready_to_schedule',
      );
    },
  );

  test('missing defense materials remain secondary to the schedule status', () {
    final value = stage(fileStatus: 'accepted')
      ..['assessment_progress'] = {
        'display_status': 'scheduled',
        'is_completed': false,
      }
      ..['materials_readiness'] = {'required_total': 1, 'submitted_total': 0};
    expect(TeamWorkflowStatus.fromStage(value).code, 'scheduled');
    expect(TeamWorkflowStatus.fromStage(value).tone, WorkflowStatusTone.active);
    expect(
      DeliverablesTriageHelper.isOverdueOrMissing({'selected_stage': value}),
      isTrue,
    );
  });

  test(
    'recorded assessment progress overrides legacy premature passed or ongoing labels',
    () {
      final value = stage(fileStatus: 'accepted', endorsed: true)
        ..['stage_status_detail'] = 'passed'
        ..['assessment_progress'] = {
          'display_status': 'awaiting_verdict',
          'is_completed': false,
        };
      expect(TeamWorkflowStatus.fromStage(value).code, 'awaiting_verdict');
      expect(
        DeliverablesTriageHelper.isReadyForDefense({'selected_stage': value}),
        isFalse,
      );
      value['stage_status_detail'] = 'defense_ongoing';
      value['assessment_progress'] = {
        'display_status': 'awaiting_evaluation',
        'is_completed': false,
      };
      expect(TeamWorkflowStatus.fromStage(value).code, 'awaiting_evaluation');
    },
  );

  test(
    'published assessment waits for required archive files and documentation',
    () {
      final value = stage(fileStatus: 'accepted', endorsed: true)
        ..['assessment_progress'] = {
          'display_status': 'completed',
          'is_completed': true,
        }
        ..['archive_complete'] = false;
      expect(TeamWorkflowStatus.fromStage(value).code, 'pending_post_defense');
      value['archive_complete'] = true;
      value['documentation_complete'] = false;
      expect(TeamWorkflowStatus.fromStage(value).code, 'pending_post_defense');
      value['documentation_complete'] = true;
      expect(TeamWorkflowStatus.fromStage(value).code, 'completed');
      expect(
        TeamWorkflowStatus.fromStage(value).tone,
        WorkflowStatusTone.success,
      );
    },
  );

  test(
    'PIT completion retains a low published result as a separate outcome',
    () {
      final value = stage(fileStatus: 'accepted', endorsed: true)
        ..['assessment_progress'] = {
          'display_status': 'completed',
          'is_completed': true,
          'published_result': 'failed',
        };
      expect(
        TeamWorkflowStatus.fromStage(value, scope: 'pit').code,
        'completed',
      );
    },
  );

  test(
    'awaiting endorsement has a separate filter and does not count as ready to schedule',
    () {
      final team = <String, dynamic>{
        'selected_stage': stage(fileStatus: 'accepted'),
      };
      expect(
        DeliverablesTriageHelper.matchesFilter(
          team,
          TeamTriageFilter.awaitingEndorsement,
        ),
        isTrue,
      );
      expect(
        DeliverablesTriageHelper.matchesFilter(
          team,
          TeamTriageFilter.needsReview,
        ),
        isFalse,
      );
      expect(DeliverablesTriageHelper.isReadyForDefense(team), isFalse);
      expect(
        DeliverablesTriageHelper.computeCounts([
          team,
        ])[TeamTriageFilter.awaitingEndorsement],
        1,
      );
    },
  );
}
