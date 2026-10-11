/// Local previews only. The backend validates rubric scores and records the result.
class RubricScore {
  const RubricScore(this.score, this.maximum, this.weight);

  final double score;
  final double maximum;
  final double? weight;
}

double? rubricPercentage(Iterable<RubricScore> values) {
  final rows = values.toList();
  if (rows.isEmpty) return null;
  if (rows.any((row) => !row.maximum.isFinite || row.maximum <= 0)) {
    return null;
  }
  double value;
  if (rows.any((row) => row.weight == null)) {
    // Compatibility for recorded evaluations predating weight snapshots.
    final maximum = rows.fold<double>(0, (sum, row) => sum + row.maximum);
    value = rows.fold<double>(0, (sum, row) => sum + row.score) / maximum * 100;
  } else {
    if (rows.any((row) => !row.weight!.isFinite || row.weight! <= 0)) {
      return null;
    }
    final weight = rows.fold<double>(0, (sum, row) => sum + row.weight!);
    value = rows.fold<double>(
          0, (sum, row) => sum + row.score / row.maximum * row.weight!,
        ) / weight * 100;
  }
  if (!value.isFinite) return null;
  // Match the backend's two-decimal, half-even rounding for previews.
  final scaled = value.clamp(0.0, 100.0) * 100;
  final lower = scaled.floor();
  final rounded = ((scaled - lower) - 0.5).abs() < 0.00000001
      ? (lower.isEven ? lower : lower + 1)
      : scaled.round();
  return rounded / 100;
}

double? rubricWeight(dynamic value) => double.tryParse(value?.toString() ?? '');

double? recordedPanelPercentage(
  Map<String, dynamic> grade, String panelistKey, int? studentId,
) {
  final values = grade['panel_evaluation_scores'];
  if (values is! List) return null;
  for (final value in values.whereType<Map>()) {
    if (value['panelist_key'] == panelistKey && value['student_id'] == studentId) {
      return rubricWeight(value['percentage']);
    }
  }
  for (final value in values.whereType<Map>()) {
    if (value['panelist_key'] == panelistKey && value['student_id'] == null) {
      return rubricWeight(value['percentage']);
    }
  }
  return null;
}
