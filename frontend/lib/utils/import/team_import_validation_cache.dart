import 'dart:convert';

/// Retain display results only where an edit cannot change batch readiness.
/// Roster/name/scope changes require the complete batch. Titles and faculty
/// references can also affect a joining shared manager, so invalidate their
/// entire section, including its metadata summary. Adviser changes can consume
/// capacity across sections and therefore invalidate the complete batch.
Map<String, dynamic>? retainTeamImportValidation({
  required List<Map<String, dynamic>> checkedRows,
  required List<Map<String, dynamic>> rows,
  required Map<String, dynamic>? preview,
}) {
  if (preview == null || checkedRows.length != rows.length) return null;
  const sectionFields = {'project_title', 'adviser_id', 'adviser_name'};
  final affectedSections = <String>{};
  for (var index = 0; index < rows.length; index++) {
    final before = checkedRows[index];
    final after = rows[index];
    final changed = {
      ...before.keys,
      ...after.keys,
    }.where((key) => jsonEncode(before[key]) != jsonEncode(after[key])).toSet();
    if (changed.isEmpty) continue;
    if (changed.contains('adviser_id') || changed.contains('adviser_name')) {
      return null;
    }
    if (!sectionFields.containsAll(changed)) return null;
    affectedSections.add('${after['section'] ?? ''}'.trim());
  }
  final results = (preview['rows'] as List? ?? []).whereType<Map>().where((p) {
    final index = (p['row'] as int? ?? 0) - 1;
    return index >= 0 &&
        index < rows.length &&
        !affectedSections.contains('${rows[index]['section'] ?? ''}'.trim());
  }).toList();
  return {
    ...preview,
    'rows': results,
    'summary': {
      'total': rows.length,
      'ready': results.where((row) => row['ready'] == true).length,
    },
    'section_summaries': (preview['section_summaries'] as List? ?? [])
        .whereType<Map>()
        .where(
          (s) => !affectedSections.contains('${s['section'] ?? ''}'.trim()),
        )
        .toList(),
    // The legacy single-section result must not survive a section edit.
    if (affectedSections.isNotEmpty) 'section_assignment': null,
  };
}
