/// Keep all enrollment entry points on the selected, reviewed outcome.
Map<String, dynamic> buildStudentRolloverAction(
  Map<String, dynamic> row,
  String action,
) {
  final record = row['record'] as Map? ?? const {};
  final result =
      row[action == 'retain' ? 'retain_result' : 'promote_result'] as Map? ??
      const {};
  return {
    'record_id': record['id'],
    'username': record['student_username'],
    'first_name': record['first_name'],
    'last_name': record['last_name'],
    'email': record['student_email'],
    'action': action,
    'year_level': result['year_level'],
    'section': result['section'],
    'target_semester_id': result['target_semester_id'],
  };
}
