import 'package:defensys/models/team_defense_record.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> schedule(
  int id, {
  String status = 'scheduled',
  int version = 2,
  int semester = 3,
}) => {
  'id': id,
  'team_id': 7,
  'scope': 'capstone',
  'stage_label': 'Project Proposal',
  'project_version': version,
  'semester_id': semester,
  'scheduled_date': '2099-10-${id.toString().padLeft(2, '0')}',
  'start_time': '08:00',
  'status': status,
};

void main() {
  test(
    'current defense excludes cancelled schedules, old projects and old terms',
    () {
      final records = TeamDefenseRecords.fromSchedules(
        [
          schedule(20, status: 'done'),
          schedule(21),
          schedule(22, status: 'cancelled'),
          schedule(23, version: 1),
          schedule(24, semester: 2),
          {...schedule(25), 'team_id': 8},
          {...schedule(26), 'scope': 'pit'},
          {...schedule(27), 'stage_label': 'Concept Proposal'},
        ],
        teamId: 7,
        selectedStage: ' project proposal ',
        projectVersion: 2,
        semesterId: 3,
      );
      expect(records.current?['id'], 21);
      expect(records.history.map((s) => s['id']), [24, 23, 22, 20]);
    },
  );

  test(
    'viewing a stage filters both its current defense and entire history',
    () {
      final records = TeamDefenseRecords.fromSchedules(
        [
          schedule(20),
          {...schedule(21, status: 'done'), 'stage_label': 'Concept Proposal'},
          {
            ...schedule(22, status: 'cancelled'),
            'stage_label': ' concept proposal ',
          },
          {
            ...schedule(23, status: 'archived'),
            'stage_label': 'Concept Proposal',
          },
        ],
        teamId: 7,
        selectedStage: 'CONCEPT PROPOSAL',
      );
      expect(records.current?['id'], 21);
      expect(records.history.map((s) => s['id']), [23, 22]);
    },
  );

  test('a stage without defenses does not show another stage in history', () {
    final records = TeamDefenseRecords.fromSchedules(
      [schedule(20)],
      teamId: 7,
      selectedStage: 'Concept Proposal',
    );
    expect(records.current, isNull);
    expect(records.history, isEmpty);
  });

  test(
    'a cancelled-only stage stays in history instead of appearing upcoming',
    () {
      final records = TeamDefenseRecords.fromSchedules(
        [schedule(21, status: 'cancelled')],
        teamId: 7,
        selectedStage: 'Project Proposal',
      );
      expect(records.current, isNull);
      expect(records.history, hasLength(1));
    },
  );

  test('a new attempt never receives a different or unscheduled grade', () {
    final grades = <Map<String, dynamic>>[
      {
        'team_id': 7,
        'stage_label': 'Project Proposal',
        'status': 'published',
        'schedule_id': 20,
      },
      {'team_id': 7, 'stage_label': 'Project Proposal', 'status': 'published'},
      {'team_id': 8, 'schedule_id': 21, 'verdict': 'approved'},
    ];
    expect(gradeForDefense(schedule(21), grades), isNull);
  });

  test(
    'earlier attempts use their own snapshots and retain publication uncertainty',
    () {
      final current = {
        'team_id': 7,
        'schedule_id': 21,
        'status': 'published',
        'verdict': 'approved',
        'attempt_history': [
          {'schedule_id': 20, 'verdict': 'for_redefense', 'final_grade': 68},
        ],
      };
      expect(gradeForDefense(schedule(21), [current])?['verdict'], 'approved');
      final earlier = gradeForDefense(schedule(20), [current]);
      expect(earlier?['verdict'], 'for_redefense');
      expect(earlier?['status'], isNull);
    },
  );
}
