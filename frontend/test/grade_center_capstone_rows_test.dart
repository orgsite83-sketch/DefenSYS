import 'package:flutter_test/flutter_test.dart';

import 'package:defensys/screens/web/admin/grade_center_shared.dart';
import 'package:defensys/services/grade_center_provider.dart';

void main() {
  test('concept selection policy survives PIT and all-scope row building', () {
    const events = [
      {
        'event_name': 'Research Options',
        'concept_config': {'enabled': true},
      },
      {'event_name': 'Project Expo'},
    ];
    final pitRows = buildPitStageRows(
      state: const GradeCenterState(),
      pitEvents: events,
    );
    expect(
      pitRows
          .singleWhere((row) => row.label == 'Research Options')
          .conceptSelectionEnabled,
      isTrue,
    );
    expect(
      pitRows
          .singleWhere((row) => row.label == 'Project Expo')
          .conceptSelectionEnabled,
      isFalse,
    );
    final allRows = buildAllStageRows(
      state: const GradeCenterState(),
      defenseStages: const [
        {
          'label': 'Concept Proposal',
          'concept_config': {'enabled': true},
        },
      ],
      pitEvents: events,
    );
    expect(
      allRows
          .where((row) => row.conceptSelectionEnabled)
          .map((row) => row.label),
      ['Concept Proposal', 'Research Options'],
    );
  });

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

  test('capstoneStagesTableBodyHeight is positive and capped', () {
    expect(capstoneStagesTableBodyHeight(1), greaterThan(0));
    expect(capstoneStagesTableBodyHeight(4), lessThanOrEqualTo(520));
    expect(capstoneStagesTableBodyHeight(20), 520);
  });

  test('buildCapstoneStageRows appends unscheduled row when needed', () {
    const state = GradeCenterState(
      grades: [
        {
          'id': 1,
          'scope': 'capstone',
          'stage_label': 'Unscheduled',
          'team_name': 'Team B',
        },
        {
          'id': 2,
          'scope': 'capstone',
          'stage_label': '',
          'team_name': 'Team C',
        },
      ],
    );

    final rows = buildCapstoneStageRows(
      state: state,
      defenseStages: [
        {'label': 'Concept Proposal', 'display_order': 1, 'is_active': true},
      ],
    );

    expect(rows.length, 2);
    expect(rows.last.label, kUnscheduledStageLabel);
    expect(rows.last.teamCount, 2);
  });
}
