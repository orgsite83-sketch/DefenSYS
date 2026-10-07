import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';

void main() {
  group('DefenseSchedulerState Current Capstone Stage Resolution', () {
    final stageConcept = {
      'id': 1,
      'label': 'Concept Proposal',
      'display_order': 1,
      'is_active': true,
      'is_officially_complete': false,
      'endorsed_teams_count': 0,
    };

    final stageProject = {
      'id': 2,
      'label': 'Project Proposal',
      'display_order': 2,
      'is_active': true,
      'is_officially_complete': false,
      'endorsed_teams_count': 0,
    };

    final stageFinal = {
      'id': 3,
      'label': 'Final Defense',
      'display_order': 3,
      'is_active': true,
      'is_officially_complete': false,
      'endorsed_teams_count': 0,
    };

    test('dynamically identifies Project Proposal as current stage when teams are ready for it', () {
      final state = DefenseSchedulerState(
        defenseStages: [stageConcept, stageProject, stageFinal],
        teams: [
          {
            'id': 101,
            'name': 'Team BioPulse',
            'level': 'Capstone 1',
            'ready_for_stage': 'Project Proposal',
            'current_defense_stage': 'Project Proposal',
          },
          {
            'id': 102,
            'name': 'Team CodeLearners',
            'level': 'Capstone 1',
            'ready_for_stage': 'Project Proposal',
            'current_defense_stage': 'Project Proposal',
          },
        ],
      );

      expect(state.currentCapstoneStageId, equals(2));
      expect(state.isCurrentCapstoneStage(stageProject), isTrue);
      expect(state.isCurrentCapstoneStage(2), isTrue);
      expect(state.isCurrentCapstoneStage(stageConcept), isFalse);
      expect(state.isCurrentCapstoneStage(1), isFalse);

      expect(state.formatStageLabel(stageConcept), equals('Concept Proposal'));
      expect(state.formatStageLabel(stageProject), equals('Project Proposal (current stage)'));
      expect(state.formatStageLabel(stageFinal), equals('Final Defense'));
    });

    test('dynamically identifies next stage when prior stage is officially complete', () {
      final completedConcept = Map<String, dynamic>.from(stageConcept)
        ..['is_officially_complete'] = true;

      final state = DefenseSchedulerState(
        defenseStages: [completedConcept, stageProject, stageFinal],
        teams: const [],
      );

      expect(state.currentCapstoneStageId, equals(2));
      expect(state.isCurrentCapstoneStage(stageProject), isTrue);
      expect(state.formatStageLabel(completedConcept), equals('Concept Proposal'));
      expect(state.formatStageLabel(stageProject), equals('Project Proposal (current stage)'));
    });

    test('identifies first stage as current stage in a fresh semester with no active teams yet', () {
      final state = DefenseSchedulerState(
        defenseStages: [stageConcept, stageProject, stageFinal],
        teams: const [],
      );

      expect(state.currentCapstoneStageId, equals(1));
      expect(state.isCurrentCapstoneStage(stageConcept), isTrue);
      expect(state.isCurrentCapstoneStage(stageProject), isFalse);

      expect(state.formatStageLabel(stageConcept), equals('Concept Proposal (current stage)'));
      expect(state.formatStageLabel(stageProject), equals('Project Proposal'));
    });

    test('respects explicit is_current flag when provided in payload', () {
      final explicitStage = Map<String, dynamic>.from(stageFinal)
        ..['is_current'] = true;

      final state = DefenseSchedulerState(
        defenseStages: [stageConcept, stageProject, explicitStage],
        teams: [
          {
            'id': 101,
            'level': 'Capstone 1',
            'ready_for_stage': 'Concept Proposal',
          },
        ],
      );

      expect(state.currentCapstoneStageId, equals(3));
      expect(state.formatStageLabel(explicitStage), equals('Final Defense (current stage)'));
    });

    test('ignores inactive stages from current stage determination', () {
      final inactiveConcept = Map<String, dynamic>.from(stageConcept)
        ..['is_active'] = false;

      final state = DefenseSchedulerState(
        defenseStages: [inactiveConcept, stageProject, stageFinal],
        teams: const [],
      );

      expect(state.currentCapstoneStageId, equals(2));
      expect(state.formatStageLabel(stageProject), equals('Project Proposal (current stage)'));
    });

    test('handles scheduled appointments in schedules', () {
      final state = DefenseSchedulerState(
        defenseStages: [stageConcept, stageProject],
        schedules: [
          {
            'defense_stage_id': 2,
            'status': 'scheduled',
          },
        ],
        teams: const [],
      );

      expect(state.currentCapstoneStageId, equals(2));
      expect(state.formatStageLabel(stageProject), equals('Project Proposal (current stage)'));
    });
  });
}
