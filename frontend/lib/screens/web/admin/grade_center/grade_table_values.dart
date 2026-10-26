typedef GradeRow = Map<String, dynamic>;

List<GradeRow> gradeMaps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
    : [];

GradeRow gradeMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

double? gradeNumber(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

String gradePercent(dynamic value) {
  final score = gradeNumber(value);
  return score == null ? '—' : '${score.toStringAsFixed(2)}%';
}
