/// Minute arithmetic deliberately keeps hours beyond 23 visible. A preview that
/// runs into the next day must be rejected, never silently wrapped to morning.
int? scheduleTimeMinutes(String value, {bool allowOverflow = false}) {
  final match = RegExp(
    r'^(\d{1,3}):(\d{2})(?::\d{2})?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (minute > 59 || (!allowOverflow && hour > 23)) return null;
  return hour * 60 + minute;
}

String scheduleTimeFromMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class ScheduleTimingInput {
  const ScheduleTimingInput({
    required this.index,
    required this.date,
    required this.room,
    required this.start,
    required this.originalDuration,
  });

  final int index;
  final String date;
  final String room;
  final int start;
  final int originalDuration;
}

/// Rebuild each room/day from its original first start. Original gaps survive
/// both longer and shorter durations; later committee sessions share the lane.
/// Inputs are never changed, so repeated edits do not accumulate timing drift.
Map<int, String> reflowScheduleStarts(
  List<ScheduleTimingInput> inputs,
  int duration,
) {
  final lanes = <(String, String), List<ScheduleTimingInput>>{};
  for (final input in inputs) {
    final key = (
      input.date,
      input.room.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
    );
    (lanes[key] ??= []).add(input);
  }
  final result = <int, String>{};
  for (final lane in lanes.values) {
    lane.sort((a, b) {
      final order = a.start.compareTo(b.start);
      return order == 0 ? a.index.compareTo(b.index) : order;
    });
    var nextStart = lane.first.start;
    ScheduleTimingInput? previous;
    for (final input in lane) {
      if (previous != null) {
        final gap = input.start - (previous.start + previous.originalDuration);
        if (gap > 0) nextStart += gap;
      }
      result[input.index] = scheduleTimeFromMinutes(nextStart);
      nextStart += duration;
      previous = input;
    }
  }
  return result;
}

bool scheduleIntervalsOverlap(int aStart, int aEnd, int bStart, int bEnd) =>
    aStart < bEnd && bStart < aEnd;
