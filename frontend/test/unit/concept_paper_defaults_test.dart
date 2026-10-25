import 'dart:convert';

import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('on/off removes automatic papers and keeps manual requirements', () {
    final manual = <String, dynamic>{
      'deliverable_id': 'D1',
      'label': 'Pitch Deck',
      'file_policy': {'mode': 'multiple', 'min_files': 1, 'max_files': 3},
    };
    final items = [manual];
    for (var cycle = 0; cycle < 3; cycle++) {
      ensureConceptPapers(items, {'enabled': true});
      ensureConceptPapers(items, {'enabled': true, 'required_count': 2});
      expect(items, hasLength(3));
      ensureConceptPapers(items, {'enabled': false});
      expect(items, [manual]);
      expect(manual['file_policy']['mode'], 'multiple');
    }
  });

  test('automatic origin survives save/reload and custom settings', () {
    final items = <Map<String, dynamic>>[];
    ensureConceptPapers(items, {'enabled': true});
    for (final item in items) {
      item['label'] = 'Department ${item['label']}';
    }
    items.first['file_policy']['mode'] = 'multiple';
    final restored = (jsonDecode(jsonEncode(items)) as List)
        .cast<Map<String, dynamic>>();
    ensureConceptPapers(restored, {'enabled': false});
    expect(restored, isEmpty);
  });

  test(
    'manually authored concept papers keep their identities and settings',
    () {
      final items = <Map<String, dynamic>>[
        {
          'deliverable_id': 'D1',
          'label': 'Concept Papers',
          'file_policy': {'mode': 'concepts'},
        },
        {
          'deliverable_id': 'D2',
          'label': 'Approved Concept Paper',
          'deliverable_type': 'post',
          'file_policy': {
            'mode': 'multiple',
            'purpose': 'approved_concept',
            'min_files': 2,
            'max_files': 5,
          },
        },
      ];
      ensureConceptPapers(items, {'enabled': true});
      ensureConceptPapers(items, {'enabled': false});
      expect(items.map((item) => item['deliverable_id']), ['D1', 'D2']);
      expect(items.last['file_policy']['min_files'], 2);
    },
  );

  test(
    'legacy automatic defaults are removed without matching by label alone',
    () {
      final items = <Map<String, dynamic>>[];
      ensureConceptPapers(items, {'enabled': true});
      for (final item in items) {
        (item['file_policy'] as Map).remove('auto_added_for');
        item['id'] = items.indexOf(item) + 1;
        item['deliverable_id'] = '${item['deliverable_id']}_2';
      }
      items.add({
        'deliverable_id': 'D3',
        'label': 'Concept Papers',
        'file_policy': {'mode': 'single'},
      });
      ensureConceptPapers(items, {'enabled': false});
      expect(items.single['deliverable_id'], 'D3');
    },
  );
}
