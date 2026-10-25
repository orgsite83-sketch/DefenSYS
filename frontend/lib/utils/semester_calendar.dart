class SemesterCalendarWindow {
  const SemesterCalendarWindow(this.start, this.end);
  final DateTime start, end;

  static SemesterCalendarWindow? fromMap(Map<dynamic, dynamic>? period) {
    final start = DateTime.tryParse(
      (period?['starts_on'] ?? period?['semester_starts_on'])?.toString() ?? '',
    );
    final end = DateTime.tryParse(
      (period?['ends_on'] ?? period?['semester_ends_on'])?.toString() ?? '',
    );
    if (start == null || end == null || !end.isAfter(start)) return null;
    return SemesterCalendarWindow(start, end);
  }

  bool contains(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  DateTime clamp(DateTime value) => value.isBefore(start)
      ? start
      : value.isAfter(end)
      ? end
      : value;
}
