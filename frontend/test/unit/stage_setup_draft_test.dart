import 'package:defensys/utils/stage_setup_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'incomplete configuration survives storage and controller disposal',
    () async {
      final controller = TextEditingController(text: 'Final manuscript');
      final deliverables = <Map<String, dynamic>>[
        {
          'label': controller.text,
          'file_format': 'pdf',
          'required': true,
          'deliverable_type': 'post',
          'archive_file_template': '{project}_{deliverable}',
          '_labelController': controller,
        },
      ];
      final draft = StageSetupDraft(
        tab: 2,
        fields: {
          'label': 'Concept draft',
          'code': 'concept',
          'description': 'Work in progress',
          'display_order': 3,
          'is_active': false,
          'minutes_required': null,
          'minutes_deliverable_id': 'DOC-7',
          'minutes_deliverable_label': 'Signed minutes',
          'is_presentation_only': false,
          'deliverables': deliverables,
          'grading_config': {
            'panel_weight': '',
            'adviser_weight': '25',
            'peer_weight': '15',
            'panel_rubric_id': 9,
            'adviser_rubric_id': null,
            'peer_rubric_id': 11,
          },
        },
      );
      deliverables.first['label'] = 'Later change';
      controller.dispose();
      final store = StageSetupDraftStore(userId: '1', semesterId: 3);
      await store.save(draft);
      final restored = (await store.load())!;
      expect(restored.tab, 2);
      expect(restored.fields, draft.fields);
      expect(restored.fields['minutes_required'], isNull);
      expect(
        (restored.fields['deliverables'] as List).single['label'],
        'Final manuscript',
      );
      expect(
        (restored.fields['deliverables'] as List).single.containsKey(
          '_labelController',
        ),
        isFalse,
      );
    },
  );

  test('drafts are isolated by account, semester and stage', () async {
    final store = StageSetupDraftStore(userId: '1', semesterId: 3);
    await store.save(
      StageSetupDraft(fields: {'label': 'My new stage'}, tab: 1),
    );
    for (final other in [
      StageSetupDraftStore(userId: '2', semesterId: 3),
      StageSetupDraftStore(userId: '1', semesterId: 4),
      StageSetupDraftStore(userId: '1', semesterId: null),
      store.forStage(7),
    ]) {
      expect(await other.load(), isNull);
    }
    await store
        .forStage(7)
        .save(StageSetupDraft(fields: {'label': 'Editor draft'}, tab: 0));
    await store.clear();
    expect(await store.load(), isNull);
    expect((await store.forStage(7).load())!.label, 'Editor draft');
  });

  test('corrupt and unsupported stored drafts are ignored', () async {
    final store = StageSetupDraftStore(userId: '1', semesterId: 3);
    final prefs = await SharedPreferences.getInstance();
    for (final raw in [
      '{broken',
      '[]',
      '{"version":2,"fields":{}}',
      '{"version":1,"fields":[]}',
    ]) {
      await prefs.setString(store.key, raw);
      expect(await store.load(), isNull);
    }
  });
}
