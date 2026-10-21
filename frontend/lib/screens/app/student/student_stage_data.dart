/// Resolves a schedule or grade for one event without borrowing another event's
/// top-level dashboard data. Nested records already belong to their stage.
Map<String, dynamic>? studentStageRecord({
  required String stage,
  required List<Map<String, dynamic>> stages,
  required String field,
  Map<String, dynamic>? fallback,
}) {
  final label = stage.trim().toLowerCase();
  if (label.isEmpty) return null;
  for (final entry in stages) {
    if (entry['stage_label']?.toString().trim().toLowerCase() == label) {
      final record = entry[field];
      if (record is Map) return Map<String, dynamic>.from(record);
      break;
    }
  }
  return fallback?['stage']?.toString().trim().toLowerCase() == label
      ? fallback
      : null;
}
