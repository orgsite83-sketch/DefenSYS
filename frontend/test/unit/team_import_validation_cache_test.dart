import 'dart:convert';
import 'package:defensys/utils/import/team_import_validation_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, dynamic>> checked;
  late List<Map<String, dynamic>> rows;
  late Map<String, dynamic> preview;
  setUp(() {
    checked = [
      for (var index = 0; index < 3; index++)
        {
          'group_key': 'team/$index',
          'team_name': 'Team $index',
          'project_title': 'Project $index',
          'section': index == 2 ? 'BSIT-3B' : 'BSIT-3A',
          'member_ids': ['student/$index'],
        },
    ];
    rows = (jsonDecode(jsonEncode(checked)) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    preview = {
      'rows': [
        for (var index = 0; index < 3; index++)
          {'row': index + 1, 'group_key': 'team/$index', 'ready': true},
      ],
      'section_summaries': [
        {'section': 'BSIT-3A', 'ready': true},
        {'section': 'BSIT-3B', 'ready': true},
      ],
      'summary': {'total': 3, 'ready': 3},
      'section_assignment': {'section': 'BSIT-3A', 'ready': true},
    };
  });
  Map<String, dynamic>? retain() => retainTeamImportValidation(
    checkedRows: checked,
    rows: rows,
    preview: preview,
  );

  test('title edits invalidate the section and its shared summary', () {
    rows[0]['project_title'] = 'Edited';
    final result = retain()!;
    expect(result['rows'], [preview['rows'][2]]);
    expect(result['summary'], {'total': 3, 'ready': 1});
    expect(result['section_summaries'], [preview['section_summaries'][1]]);
    expect(result['section_assignment'], isNull);
    expect(preview['rows'], hasLength(3));
  });
  test('adviser edits invalidate capacity reservations across sections', () {
    rows[0]['adviser_name'] = 'New adviser';
    expect(retain(), isNull);
  });
  test('multiple section edits accumulate', () {
    rows[0]['project_title'] = 'Edited';
    rows[2]['project_title'] = 'Edited';
    expect(retain()!['rows'], isEmpty);
  });
  for (final field in [
    'member_ids',
    'leader_id',
    'team_name',
    'section',
    'system_name',
    'project_manager',
    'level',
  ]) {
    test('$field edits require a full batch check', () {
      rows[0][field] = field == 'member_ids' ? ['other/student'] : 'Changed';
      expect(retain(), isNull);
    });
  }
  test('structural changes cannot shift cached row results', () {
    rows.removeAt(0);
    expect(retain(), isNull);
  });
  test('unchanged input retains results', () {
    expect(retain()!['rows'], preview['rows']);
  });
}
