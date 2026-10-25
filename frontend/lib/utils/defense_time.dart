/// Defense times belong to Asia/Manila even when the viewing device does not.
DateTime? defenseScheduledAt(Map<String, dynamic>? schedule) {
  if (schedule == null) return null;
  final absolute = DateTime.tryParse(
    schedule['scheduled_at']?.toString() ?? '',
  );
  if (absolute != null) return absolute.toUtc();
  // Compatibility with older responses during an incremental deployment.
  final date = DateTime.tryParse(
    (schedule['date'] ?? schedule['scheduled_date'])?.toString() ?? '',
  );
  if (date == null) return null;
  final rawTime =
      (schedule['startTime'] ?? schedule['start_time'] ?? '00:00:00')
          .toString()
          .trim();
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$',
    caseSensitive: false,
  ).firstMatch(rawTime);
  if (match == null) return null;
  var hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  final second = int.parse(match[3] ?? '0');
  final period = match[4]?.toUpperCase();
  if (period != null) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (period == 'PM' ? 12 : 0);
  }
  if (hour > 23 || minute > 59 || second > 59) return null;
  return DateTime.utc(
    date.year,
    date.month,
    date.day,
    hour,
    minute,
    second,
  ).subtract(const Duration(hours: 8));
}

/// The server anchors real time once per response; a monotonic timer advances
/// between refreshes so local timezone and wall-clock changes cannot skew it.
class DefenseCountdownClock {
  final Stopwatch _elapsed = Stopwatch();
  String? _key;
  DateTime? _reference;

  DateTime now(Map<String, dynamic> schedule) {
    final key = '${schedule['id']}:${schedule['server_now']}';
    if (_key != key || _reference == null) {
      _key = key;
      _reference =
          DateTime.tryParse(
            schedule['server_now']?.toString() ?? '',
          )?.toUtc() ??
          DateTime.now().toUtc();
      _elapsed
        ..reset()
        ..start();
    }
    return _reference!.add(_elapsed.elapsed);
  }
}
