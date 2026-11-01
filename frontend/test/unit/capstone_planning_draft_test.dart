import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/capstone_planning_draft.dart';

void main() {
  test('shared assignment equality ignores member display order', () {
    final first = CapstoneRosterDraft(
      chair: 1,
      members: [2, 3, 4],
      documenter: 5,
    );
    final reordered = CapstoneRosterDraft(
      chair: 1,
      members: [4, 2, 3],
      documenter: 5,
    );
    expect(first.signature, reordered.signature);
    expect(
      capstoneRosterDeltaHasChanges(first.changesFrom(reordered.toJson())),
      isFalse,
    );
  });

  test(
    'permanent replacement traces temporary cover without promoting unrelated cover',
    () {
      final baseline = CapstoneRosterDraft(
        chair: 1,
        members: [2, 3, 4],
        documenter: 5,
      );
      final first = baseline.copy()..members[2] = 6;
      final second = first.copy()..members[0] = 7;
      final proposed = second.copy()..members[2] = 8;
      final edit = capstoneContinuingDelta(
        proposed.changesFrom(second.toJson()),
        baseline.toJson(),
        [
          first.changesFrom(baseline.toJson()),
          second.changesFrom(first.toJson()),
        ],
      );
      final continuing = baseline.applying(edit);
      expect(continuing.toJson()['panelist_ids'], [1, 2, 3, 8]);
      expect(continuing.toJson()['panelist_ids'], isNot(contains(7)));
      final stage = continuing.applying(
        proposed.changesFrom(continuing.toJson()),
      );
      expect(stage.toJson()['panelist_ids'].toSet(), {1, 7, 3, 8});
    },
  );

  test(
    'readiness distinguishes waiting, partial, and already-scheduled teams',
    () {
      final ready = {
        'ready_stage_ids': [71],
      };
      final waiting = {'ready_stage_ids': <int>[]};
      final booked = {
        'stage_readiness': {
          '71': {
            'status': 'scheduled',
            'label': 'Scheduled',
            'endorsed': true,
            'can_schedule': false,
          },
        },
      };
      expect(
        CapstoneReadinessSummary([ready, waiting], 71).label,
        'Partly ready',
      );
      expect(
        CapstoneReadinessSummary([waiting], 71).label,
        'Awaiting endorsement',
      );
      expect(CapstoneReadinessSummary([booked], 71).label, 'Already scheduled');
      expect(CapstoneReadinessSummary([ready, booked], 71).ready, 1);
      expect(CapstoneReadinessSummary([ready, booked], 71).endorsed, 2);
    },
  );
  test(
    'new adviser starts with exactly one chair and three independent empty members',
    () {
      final a = CapstoneRosterDraft(), b = CapstoneRosterDraft();
      expect(a.members.length, 3);
      expect(a.chair, isNull);
      a.members.add(null);
      expect(b.members.length, 3);
      expect(a.complete, isFalse);
      expect(a.copy().members.length, 4);
    },
  );
  test(
    'temporary member replacement remains separate from permanent documenter change',
    () {
      final baseline = CapstoneRosterDraft(
        chair: 1,
        members: [2, 3, 4],
        documenter: 5,
      );
      final temporary = baseline.copy()..members[0] = 6;
      final delta = temporary.changesFrom(baseline.toJson());
      baseline.documenter = 7;
      final actual = baseline.applying(delta);
      expect(actual.members, [3, 4, 6]);
      expect(actual.documenter, 7);
      expect(baseline.members, [2, 3, 4]);
      expect(baseline.externals, isEmpty);
    },
  );
  test(
    'grouping separates different intakes with the same adviser and retains team order',
    () {
      final groups = capstoneGroups([
        {'id': 1, 'adviser_id': 10, 'intake_semester_id': 20},
        {'id': 2, 'adviser_id': 10, 'intake_semester_id': 20},
        {'id': 3, 'adviser_id': 10, 'intake_semester_id': 21},
      ]);
      expect(groups.length, 2);
      expect(groups.first.teams.map((t) => t['id']), [1, 2]);
    },
  );
}
