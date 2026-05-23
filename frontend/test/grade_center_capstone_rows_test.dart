import 'package:flutter_test/flutter_test.dart';

import 'package:user/screens/web/admin/grade_center_shared.dart';
import 'package:user/services/grade_center_provider.dart';

void main() {
  test('buildCapstoneStageRows merges defense stages with grade counts', () {
    const state = GradeCenterState(
      grades: [
        {
          'id': 1,
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'team_name': 'Team A',
        },
      ],
      groupSettings: {
        'capstone|Concept Proposal': {
          'scope': 'capstone',
          'stage_label': 'Concept Proposal',
          'is_officially_complete': true,
          'peer_grading_enabled': false,
        },
      },
    );

    final rows = buildCapstoneStageRows(
      state: state,
      defenseStages: [
        {
          'label': 'Concept Proposal',
          'display_order': 1,
          'description': 'Concept stage',
          'is_active': true,
        },
        {
          'label': 'Final Defense',
          'display_order': 3,
          'description': 'Final stage',
          'is_active': true,
        },
      ],
    );

    expect(rows.length, 2);
    expect(rows.first.label, 'Concept Proposal');
    expect(rows.first.teamCount, 1);
    expect(rows.first.workflowStatus, CapstoneStageWorkflowStatus.gradesLocked);
    expect(rows.last.label, 'Final Defense');
    expect(rows.last.teamCount, 0);
    expect(rows.last.workflowStatus, CapstoneStageWorkflowStatus.notStarted);
  });

  test('capstoneStageWorkflowStatus in progress when teams exist', () {
    expect(
      capstoneStageWorkflowStatus(isOfficiallyComplete: false, teamCount: 2),
      CapstoneStageWorkflowStatus.inProgress,
    );
  });
}
