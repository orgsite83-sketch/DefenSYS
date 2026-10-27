import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_deliverable_presets.dart';
import 'package:defensys/widgets/repository/deliverable_submission_settings.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> requirement(String id, String label) => {
  'deliverable_id': id,
  'label': label,
  'deliverable_type': 'pre',
  'required': true,
  'file_format': 'pdf',
  'file_policy': {
    'mode': 'concepts',
    'slots': [
      {'key': 'paper', 'label': label, 'required': true, 'file_format': 'pdf'},
    ],
  },
};

void main() {
  test('protected server requirements survive stale draft edits and removals', () {
    final restored = restoreProtectedDeliverables([
      {'id': 1, 'deliverable_id': 'RENAMED', 'label': 'Stale edit'},
      {'deliverable_id': 'NEW', 'label': 'Unsaved new requirement'},
    ], [
      {'id': 1, 'deliverable_id': 'D1', 'label': 'Submitted file', 'has_data': true},
      {'id': 2, 'deliverable_id': 'D2', 'label': 'Reviewed file', 'is_locked': true},
    ]);
    expect(restored.map((row) => row['label']),
        ['Submitted file', 'Unsaved new requirement', 'Reviewed file']);
    expect(restored.first['deliverable_id'], 'D1');
    expect(restored.first['has_data'], true);
  });

  test('shared evidence protects a linked team entry while presets start unlocked', () {
    final teams = [requirement('D1', 'Shared manuscript')];
    final shared = [requirement('SHARED_D1', 'Shared manuscript')
      ..['team_deliverable_id'] = 'D1'
      ..['has_data'] = true
      ..['is_locked'] = true];
    expect(deliverableSetupItems(teams, shared).single['is_locked'], true);
    final preset = deliverablePresetItems(teams, shared).single;
    expect(preset.containsKey('has_data'), false);
    expect(preset.containsKey('is_locked'), false);
  });

  test(
    'both uses one configured row and separate synchronized submission definitions',
    () {
      final item = requirement('D1', 'Concept Paper')..['id'] = 18;
      final teams = [item];
      final shared = <Map<String, dynamic>>[];
      setDeliverableSubmissionAudience(item, 'both', teams, shared);
      expect(deliverableSetupItems(teams, shared), [same(item)]);
      expect(shared.single['team_deliverable_id'], 'D1');
      final pmNumber = shared.single['deliverable_id'];
      item['label'] = 'Concept Manuscript';
      item['archive_file_template'] = '{project}_{deliverable}';
      item['is_defense_material'] = true;
      final payload = configuredSharedDeliverables(teams, shared).single;
      expect(payload['label'], 'Concept Manuscript');
      expect(payload['is_defense_material'], true);
      expect(payload['archive_file_template'], '{project}_{deliverable}');
      expect(payload['deliverable_id'], pmNumber);
      expect(payload.containsKey('id'), false);
      expect(identical(payload['file_policy'], item['file_policy']), false);
      expect(item['id'], 18);
    },
  );

  test(
    'scope changes preserve the edited row and retain the correct recipients',
    () {
      final item = requirement('D1', 'Paper')..['id'] = 18;
      final teams = [item];
      final shared = <Map<String, dynamic>>[];
      setDeliverableSubmissionAudience(item, 'both', teams, shared);
      final pmNumber = shared.single['deliverable_id'];
      setDeliverableSubmissionAudience(item, 'pm', teams, shared);
      expect(teams, isEmpty);
      expect(shared.single, same(item));
      expect(item.containsKey('id'), false);
      setDeliverableSubmissionAudience(item, 'both', teams, shared);
      expect(teams.single, same(item));
      expect(item['id'], 18);
      expect(shared.single['deliverable_id'], pmNumber);
      expect(deliverableSetupItems(teams, shared).length, 1);
      setDeliverableSubmissionAudience(item, 'teams', teams, shared);
      expect(shared, isEmpty);
      expect(teams.single, same(item));
    },
  );

  test(
    'identical legacy names stay separate and deleting a linked row preserves other records',
    () {
      final item = requirement('D1', 'Concept Paper');
      final legacy = requirement('SHARED_CONCEPTS', 'Concept Paper');
      final teams = [item];
      final shared = [legacy];
      expect(deliverableSetupItems(teams, shared).length, 2);
      expect(deliverableSubmissionAudience(item), 'teams');
      expect(deliverableSubmissionAudience(legacy), 'pm');
      setDeliverableSubmissionAudience(item, 'both', teams, shared);
      removeConfiguredDeliverable(item, teams, shared);
      expect(teams, isEmpty);
      expect(shared, [same(legacy)]);
    },
  );

  test(
    'legacy missing IDs and repeated scope changes cannot collide with new team records',
    () {
      final item = requirement('', 'Paper');
      final teams = [item];
      final shared = <Map<String, dynamic>>[];
      deliverableSetupItems(teams, shared);
      expect(item['deliverable_id'], 'D1');
      setDeliverableSubmissionAudience(item, 'pm', teams, shared);
      teams.add(requirement('D1', 'Deck'));
      setDeliverableSubmissionAudience(item, 'both', teams, shared);
      expect(teams.map((row) => row['deliverable_id']).toSet().length, 2);
      expect(shared.single['team_deliverable_id'], item['deliverable_id']);
    },
  );

  test(
    'saved presets round-trip all three audiences without controller or database identities',
    () {
      final team = requirement('D1', 'Team paper')..['id'] = 13;
      final both = requirement('D2', 'Both paper')..['id'] = 14;
      final pm = requirement('SHARED_ADMIN', 'Section form');
      final teams = [team, both];
      final shared = [pm];
      setDeliverableSubmissionAudience(both, 'both', teams, shared);
      final controller = TextEditingController(text: 'Team paper');
      addTearDown(controller.dispose);
      team['_labelController'] = controller;
      final preset = StageDeliverablePresetManager.cloneDeliverables(
        deliverablePresetItems(teams, shared),
      );
      expect(preset.map((row) => row['submission_audience']), [
        'teams',
        'both',
        'pm',
      ]);
      expect(
        preset.every(
          (row) =>
              !row.containsKey('id') &&
              !row.keys.any((key) => key.startsWith('_')),
        ),
        true,
      );
      final restoredTeams = <Map<String, dynamic>>[];
      final restoredShared = <Map<String, dynamic>>[];
      applyDeliverablePresetItems(preset, restoredTeams, restoredShared);
      expect(deliverableSetupItems(restoredTeams, restoredShared).length, 3);
      expect(restoredTeams.length, 2);
      expect(restoredShared.length, 2);
      expect(
        restoredShared.singleWhere(
          (row) => row['team_deliverable_id'] != null,
        )['label'],
        'Both paper',
      );
    },
  );

  test(
    'moving automatic concept papers to PM does not recreate team requirements',
    () {
      final teams = <Map<String, dynamic>>[];
      final shared = <Map<String, dynamic>>[];
      ensureConceptPapers(teams, {'enabled': true});
      for (final item in List<Map<String, dynamic>>.of(teams)) {
        setDeliverableSubmissionAudience(item, 'pm', teams, shared);
      }
      ensureConceptPapers(teams, {'enabled': true}, sharedItems: shared);
      expect(teams, isEmpty);
      expect(shared.length, 2);
    },
  );

  test(
    'fresh shared concept defaults configure each automatic paper once and disable cleanly',
    () {
      final teams = <Map<String, dynamic>>[];
      final shared = [
        requirement('SHARED_CONCEPTS', 'Concept papers'),
        {
          'deliverable_id': 'SHARED_FINAL',
          'label': 'Approved concept paper',
          'deliverable_type': 'post',
          'required': true,
          'file_format': 'pdf',
          'file_policy': {'mode': 'single', 'purpose': 'approved_concept'},
        },
      ];
      ensureConceptPapers(teams, {'enabled': true}, sharedItems: shared);
      linkNewSharedConceptDefaults(teams, shared);
      expect(deliverableSetupItems(teams, shared).length, 2);
      expect(
        teams.every((row) => deliverableSubmissionAudience(row) == 'both'),
        true,
      );
      ensureConceptPapers(teams, {'enabled': false}, sharedItems: shared);
      expect(teams, isEmpty);
      expect(shared, isEmpty);
    },
  );

  test(
    'explicitly choosing both reuses an equivalent automatic legacy PM paper identity',
    () {
      final teams = <Map<String, dynamic>>[];
      ensureConceptPapers(teams, {'enabled': true});
      final paper = teams.singleWhere(
        (row) => row['deliverable_type'] == 'pre',
      );
      final pm = requirement('SHARED_CONCEPTS', 'Concept papers')
        ..['is_defense_material'] = true
        ..['file_policy'] = {
          'mode': 'concepts',
          'slots': [
            {
              'key': 'paper',
              'label': 'Concept paper',
              'required': true,
              'file_format': 'pdf',
            },
          ],
        };
      final shared = [pm];
      setDeliverableSubmissionAudience(paper, 'both', teams, shared);
      expect(shared.single, same(pm));
      expect(shared.single['deliverable_id'], 'SHARED_CONCEPTS');
      expect(shared.single['team_deliverable_id'], paper['deliverable_id']);
    },
  );
}
