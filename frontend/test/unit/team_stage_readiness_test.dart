import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';

void main() {
  group('Team Stage Readiness & Completion Lifecycle Tests', () {
    test('completed_stages correctly returns completed and overrides ready_for_stage', () {
      final team = {
        'id': 1,
        'name': 'Team SkyLedger',
        'ready_for_stage': 'Project Proposal',
        'completed_stages': ['Concept Proposal', 'Project Proposal'],
        'scheduled_stages': <String>[],
        'stage_progress': {
          'Concept Proposal': 'completed',
          'Project Proposal': 'completed',
        },
      };

      expect(getTeamStageStatus(team, 'Concept Proposal'), 'completed');
      expect(isTeamStageCompleted(team, 'Concept Proposal'), isTrue);
      expect(isTeamStageReady(team, 'Concept Proposal'), isFalse);

      expect(getTeamStageStatus(team, 'Project Proposal'), 'completed');
      expect(isTeamStageCompleted(team, 'Project Proposal'), isTrue);
      expect(isTeamStageReady(team, 'Project Proposal'), isFalse);
    });

    test('ready_for_stage returns ready when not completed or scheduled', () {
      final team = {
        'id': 2,
        'name': 'Team Alpha',
        'ready_for_stage': 'Project Proposal',
        'completed_stages': ['Concept Proposal'],
        'scheduled_stages': <String>[],
        'stage_progress': {
          'Concept Proposal': 'completed',
          'Project Proposal': 'ready',
        },
      };

      expect(getTeamStageStatus(team, 'Concept Proposal'), 'completed');
      expect(isTeamStageCompleted(team, 'Concept Proposal'), isTrue);

      expect(getTeamStageStatus(team, 'Project Proposal'), 'ready');
      expect(isTeamStageReady(team, 'Project Proposal'), isTrue);
      expect(isTeamStageCompleted(team, 'Project Proposal'), isFalse);
    });

    test('scheduled_stages returns scheduled status', () {
      final team = {
        'id': 3,
        'name': 'Team Beta',
        'ready_for_stage': '',
        'completed_stages': ['Concept Proposal'],
        'scheduled_stages': ['Project Proposal'],
        'stage_progress': {
          'Concept Proposal': 'completed',
          'Project Proposal': 'scheduled',
        },
      };

      expect(getTeamStageStatus(team, 'Project Proposal'), 'scheduled');
      expect(isTeamStageScheduled(team, 'Project Proposal'), isTrue);
      expect(isTeamStageReady(team, 'Project Proposal'), isFalse);
      expect(isTeamStageCompleted(team, 'Project Proposal'), isFalse);
    });

    test('pending status when milestone is not yet ready or completed', () {
      final team = {
        'id': 4,
        'name': 'Team Gamma',
        'ready_for_stage': null,
        'completed_stages': <String>[],
        'scheduled_stages': <String>[],
        'stage_progress': <String, dynamic>{},
      };

      expect(getTeamStageStatus(team, 'Concept Proposal'), 'pending');
      expect(isTeamStageReady(team, 'Concept Proposal'), isFalse);
      expect(isTeamStageCompleted(team, 'Concept Proposal'), isFalse);
      expect(isTeamStageScheduled(team, 'Concept Proposal'), isFalse);
    });
  });
}
