int? defenseRecordId(dynamic value) => int.tryParse(value?.toString() ?? '');

String _stage(dynamic value) => value?.toString().trim().toLowerCase() ?? '';

/// Resolve by schedule identity so a new attempt cannot inherit older grades.
Map<String, dynamic>? gradeForDefense(
  Map<String, dynamic> schedule,
  List<Map<String, dynamic>> grades,
) {
  final id = defenseRecordId(schedule['id']);
  if (id == null) return null;
  for (final grade in grades) {
    if (defenseRecordId(grade['team_id']) != null &&
        defenseRecordId(grade['team_id']) !=
            defenseRecordId(schedule['team_id'])) {
      continue;
    }
    if (defenseRecordId(grade['schedule_id']) == id) return grade;
    for (final attempt
        in (grade['attempt_history'] as List? ?? []).whereType<Map>()) {
      if (defenseRecordId(attempt['schedule_id']) == id) {
        // Snapshots have no publication state. Do not present retained
        // provisional scores as a published grade.
        return Map<String, dynamic>.from(attempt);
      }
    }
  }
  return null;
}

class TeamDefenseRecords {
  final Map<String, dynamic>? current;
  final List<Map<String, dynamic>> history;

  const TeamDefenseRecords({required this.current, required this.history});

  factory TeamDefenseRecords.fromSchedules(
    List<Map<String, dynamic>> schedules, {
    required int teamId,
    required String selectedStage,
    int? projectVersion,
    int? semesterId,
  }) {
    final records =
        schedules
            .where(
              (s) =>
                  defenseRecordId(s['team_id']) == teamId &&
                  s['scope'] == 'capstone' &&
                  _stage(s['stage_label']) == _stage(selectedStage),
            )
            .toList()
          ..sort(_newestFirst);
    final eligible = records
        .where(
          (s) =>
              !{'cancelled', 'archived'}.contains(s['status']) &&
              (projectVersion == null ||
                  defenseRecordId(s['project_version']) == projectVersion) &&
              (semesterId == null ||
                  defenseRecordId(s['semester_id']) == semesterId),
        )
        .toList();
    final open = eligible.where((s) => s['status'] == 'scheduled').toList()
      ..sort((a, b) => _newestFirst(b, a));
    final current = open.firstOrNull ?? eligible.firstOrNull;
    return TeamDefenseRecords(
      current: current,
      history: records.where((s) => !identical(s, current)).toList(),
    );
  }

  static int _newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
    final date = '${b['scheduled_date']} ${b['start_time']}'.compareTo(
      '${a['scheduled_date']} ${a['start_time']}',
    );
    return date != 0
        ? date
        : (defenseRecordId(b['id']) ?? 0).compareTo(
            defenseRecordId(a['id']) ?? 0,
          );
  }
}
