/// Board sections follow assessment progress, not an elapsed defense slot.
enum SessionActivity {
  active('Active sessions'),
  upcoming('Upcoming sessions'),
  past('Past sessions');

  const SessionActivity(this.label);
  final String label;
}

const _finishedStatuses = {
  'done',
  'assessed',
  'completed',
  'failed',
  'project_rejected',
  'redefense_required',
  'for_redefense',
  'cancelled',
  'archived',
};

SessionActivity _scheduleActivity(Map<String, dynamic> schedule, DateTime now) {
  // Cancellation/archive remain final even if an older display status is cached.
  if (const {'cancelled', 'archived'}.contains(schedule['status'])) {
    return SessionActivity.past;
  }
  final status = schedule['display_status'] ?? schedule['status'];
  if (_finishedStatuses.contains(status)) return SessionActivity.past;
  if (status == 'scheduled' &&
      (schedule['operation_state'] == null ||
          schedule['operation_state'] == 'normal')) {
    final date = DateTime.tryParse('${schedule['scheduled_date']}');
    final today = DateTime(now.year, now.month, now.day);
    if (date != null && date.isAfter(today)) return SessionActivity.upcoming;
  }
  return SessionActivity.active;
}

/// A partially assessed session stays visible until all its defenses are final.
SessionActivity sessionActivity(
  List<Map<String, dynamic>> schedules, {
  required DateTime now,
}) => schedules.fold(SessionActivity.past, (current, schedule) {
  final activity = _scheduleActivity(schedule, now);
  return activity.index < current.index ? activity : current;
});

DateTime? _sessionDate(
  List<Map<String, dynamic>> schedules,
  SessionActivity activity,
  DateTime now,
) {
  final dates =
      schedules
          .where((schedule) => _scheduleActivity(schedule, now) == activity)
          .map(
            (schedule) => DateTime.tryParse(
              '${schedule['scheduled_date']} ${schedule['start_time'] ?? '00:00:00'}',
            ),
          )
          .whereType<DateTime>()
          .toList()
        ..sort();
  if (dates.isEmpty) return null;
  return activity == SessionActivity.past ? dates.last : dates.first;
}

int compareSessionActivity(
  List<Map<String, dynamic>> a,
  List<Map<String, dynamic>> b, {
  required DateTime now,
}) {
  final activityA = sessionActivity(a, now: now);
  final activityB = sessionActivity(b, now: now);
  final priority = activityA.index.compareTo(activityB.index);
  if (priority != 0) return priority;
  if (activityA == SessionActivity.active) {
    bool evaluating(List<Map<String, dynamic>> schedules) => schedules.any(
      (s) =>
          _scheduleActivity(s, now) == SessionActivity.active &&
          const {
            'evaluating',
            'ongoing',
          }.contains(s['display_status'] ?? s['status']),
    );
    final livePriority = (evaluating(a) ? 0 : 1).compareTo(
      evaluating(b) ? 0 : 1,
    );
    if (livePriority != 0) return livePriority;
  }
  final dateA = _sessionDate(a, activityA, now);
  final dateB = _sessionDate(b, activityB, now);
  if (dateA == null) return dateB == null ? 0 : 1;
  if (dateB == null) return -1;
  return activityA == SessionActivity.past
      ? dateB.compareTo(dateA)
      : dateA.compareTo(dateB);
}
