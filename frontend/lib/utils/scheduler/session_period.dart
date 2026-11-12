import 'package:intl/intl.dart';

/// Nominal scheduler context, independent of a user's visible team subset.
class DefenseSessionWindow {
  const DefenseSessionWindow({this.label = '', this.start = '', this.end = ''});

  factory DefenseSessionWindow.fromJson(Map<String, dynamic> json) =>
      DefenseSessionWindow(
        label: json['session_label']?.toString() ?? '',
        start: json['session_start_time']?.toString() ?? '',
        end: json['session_end_time']?.toString() ?? '',
      );

  final String label, start, end;

  static DateTime? _time(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.firstOrNull ?? '');
    final minute = int.tryParse(parts.elementAtOrNull(1) ?? '');
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return DateTime(2000, 1, 1, hour, minute);
  }

  bool get isConfigured =>
      label.isNotEmpty && _time(start) != null && _time(end) != null;

  String get timeRange => isConfigured
      ? '${DateFormat('h:mm a').format(_time(start)!)}–${DateFormat('h:mm a').format(_time(end)!)}'
      : '';
}
