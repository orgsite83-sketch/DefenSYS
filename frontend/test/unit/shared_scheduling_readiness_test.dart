import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const event = 'IT Concept Defense';
  Map<String, dynamic> team({
    String status = 'awaiting_upload',
    bool complete = false,
  }) => {
    'level': '1st Year PIT',
    'year_level': '1st Year',
    'ready_for_stage': event,
    'stage_progress': {event: 'ready'},
    'shared_readiness': {
      event: {
        'section': 'BSIT-1B',
        'project_manager_name': 'Lance San Pedro',
        'complete': complete,
        'requirements': complete
            ? []
            : [
                {'label': 'Concept Paper', 'status': status},
              ],
      },
    },
  };

  test('team endorsement cannot override pending section work', () {
    final blocked = team();
    expect(getTeamStageStatus(blocked, event), 'pending');
    expect(isTeamStageReady(blocked, event), isFalse);
    for (final deliverables in [
      [],
      [
        {'deliverable_type': 'pre', 'required': true},
      ],
    ]) {
      expect(
        isPitTeamReadyToSchedule(blocked, event, {
          'year_level': '1st Year',
          'deliverables': deliverables,
        }),
        isFalse,
      );
    }
    expect(
      isTeamStageReady({
        ...blocked,
        'level': 'Capstone',
        'eligible_stages': [event],
      }, event),
      isFalse,
    );
  });

  test('section status states the requirement and its action', () {
    for (final scenario in [
      ('awaiting_upload', 'Shared files missing', 'upload required'),
      ('awaiting_review', 'Shared files awaiting review', 'awaiting review'),
      ('changes_requested', 'Shared changes requested', 'changes requested'),
    ]) {
      final readiness = sharedSchedulingReadiness(
        team(status: scenario.$1),
        event,
      );
      expect(sharedRequirementsStatus(readiness), scenario.$2);
      expect(
        sharedRequirementsDetail(readiness),
        contains('Concept Paper — ${scenario.$3}'),
      );
      expect(
        sharedRequirementsDetail(readiness),
        contains('Project manager: Lance San Pedro'),
      );
    }
  });

  test(
    'accepted section files restore readiness without hiding recorded progress',
    () {
      expect(isTeamStageReady(team(complete: true), event), isTrue);
      expect(isTeamStageReady(team(), 'Another event'), isFalse);
      for (final status in [
        'scheduled',
        'completed',
        'evaluating',
        'revisions_pending',
      ]) {
        expect(
          getTeamStageStatus({
            ...team(),
            'stage_progress': {event: status},
          }, event),
          status,
        );
      }
    },
  );
}
