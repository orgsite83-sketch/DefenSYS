import 'package:flutter/material.dart';

class ScheduleSessionBlock {
  ScheduleSessionBlock({required this.start, required this.end});
  final TextEditingController start, end;
  Map<String, dynamic> toPayload() => {
    'start_time': start.text.trim(),
    'end_time': end.text.trim(),
  };
  void dispose() {
    start.dispose();
    end.dispose();
  }
}

class ScheduleSessionDraft {
  ScheduleSessionDraft({
    required this.key,
    required this.date,
    required this.start,
    required this.duration,
    required this.room,
    String end = '12:00',
    this.ownsFields = true,
  }) : end = TextEditingController(text: end) {
    blocks = [
      ScheduleSessionBlock(start: start, end: this.end),
      ScheduleSessionBlock(
        start: TextEditingController(text: '13:00'),
        end: TextEditingController(text: '17:00'),
      ),
    ];
  }

  final String key;
  final TextEditingController date, start, end, duration, room;
  final bool ownsFields;
  late final List<ScheduleSessionBlock> blocks;
  Set<int> teamIds = {};
  bool customStaff = false;
  Set<int> panelists = {}, externals = {};
  int? chair, documenter;

  int get capacity {
    final minutes = int.tryParse(duration.text) ?? 0;
    if (minutes <= 0) return 0;
    int total = 0;
    for (final block in blocks) {
      final startMinutes = scheduleTimeMinutes(block.start.text);
      final endMinutes = scheduleTimeMinutes(block.end.text);
      if (startMinutes < 0 || endMinutes <= startMinutes) return 0;
      total += (endMinutes - startMinutes) ~/ minutes;
    }
    return total;
  }

  String get timeWindowLabel => blocks
      .map((block) => '${block.start.text}–${block.end.text}')
      .join(' / ');

  Map<String, dynamic> toPayload() => {
    'key': key,
    'scheduled_date': date.text.trim(),
    'start_time': start.text.trim(),
    'end_time': blocks.last.end.text.trim(),
    'time_blocks': blocks.map((block) => block.toPayload()).toList(),
    'team_ids': teamIds.toList(),
    'slot_duration': int.tryParse(duration.text.trim()) ?? 0,
    'room': room.text.trim(),
    if (customStaff) ...{
      'panelist_ids': panelists.toList(),
      'external_evaluator_ids': externals.toList(),
      'chair_panelist_id': chair,
      'documenter_id': documenter,
    },
  };

  void dispose() {
    for (final block in blocks.skip(1)) {
      block.dispose();
    }
    end.dispose();
    if (ownsFields) {
      date.dispose();
      start.dispose();
      duration.dispose();
      room.dispose();
    }
  }
}

int scheduleTimeMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return -1;
  final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return -1;
  }
  return hour * 60 + minute;
}

String scheduleTimeLabel(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

List<(int, int)> sessionSlotIntervals(Map<String, dynamic> session) {
  final duration = session['slot_duration'] as int;
  if (duration <= 0) return [];
  final blocks =
      (session['time_blocks'] as List?)?.cast<Map<String, dynamic>>() ??
      [
        {'start_time': session['start_time'], 'end_time': session['end_time']},
      ];
  final intervals = <(int, int)>[];
  for (final block in blocks) {
    final start = scheduleTimeMinutes(block['start_time'] as String);
    final end = scheduleTimeMinutes(block['end_time'] as String);
    if (start < 0 || end <= start) continue;
    for (int offset = start; offset + duration <= end; offset += duration) {
      intervals.add((offset, offset + duration));
    }
  }
  return intervals;
}

/// Team slots stay inside their selected session's blocks and skip every break.
List<Map<String, dynamic>> arrangeSessionSlots(
  List<Map<String, dynamic>> slots,
  List<Map<String, dynamic>> sessions,
) {
  final counts = <String, int>{};
  final byKey = {for (final session in sessions) session['key']: session};
  return slots.map((original) {
    final slot = Map<String, dynamic>.from(original);
    final key = slot['session_key'];
    final session = byKey[key];
    if (session != null) {
      final duration = session['slot_duration'] as int;
      final intervals = sessionSlotIntervals(session);
      final index = counts[key] ?? 0;
      if (index < intervals.length) {
        final (start, end) = intervals[index];
        counts[key] = index + 1;
        slot.addAll({
          'scheduled_date': session['scheduled_date'],
          'start_time': scheduleTimeLabel(start),
          'end_time': scheduleTimeLabel(end),
          'slot_duration': duration,
          'room': session['room'],
        });
        return slot;
      }
    }
    slot.addAll({
      'session_key': null,
      'requested_session_key': slot['requested_session_key'] ?? key,
      'scheduled_date': null,
      'start_time': null,
      'end_time': null,
      'slot_duration': null,
      'room': '',
    });
    return slot;
  }).toList();
}
