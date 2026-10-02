import 'defense_schedule_import_parser.dart';
import 'schedule_import_timing.dart';

bool scheduleImportDateIsValid(String value) {
  final parsed = DateTime.tryParse(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      parsed != null &&
      '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' ==
          value;
}

bool scheduleImportSemesterMatches(String? source, String target) {
  if (source == null || source.trim().isEmpty) return true;
  String normalized(String value) => value
      .toLowerCase()
      .replaceAll('semester', 'sem')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (normalized(source) == normalized(target)) return true;
  final years = RegExp(
    r'20\d{2}',
  ).allMatches(source).map((match) => match.group(0)).toList();
  final targetYears = RegExp(
    r'20\d{2}',
  ).allMatches(target).map((match) => match.group(0)).toList();
  final term = RegExp(
    r'(1st|2nd|first|second|summer)',
    caseSensitive: false,
  ).firstMatch(source)?.group(0)?.toLowerCase();
  final targetTerm = RegExp(
    r'(1st|2nd|first|second|summer)',
    caseSensitive: false,
  ).firstMatch(target)?.group(0)?.toLowerCase();
  String? ordinal(String? value) => value == 'first'
      ? '1st'
      : value == 'second'
      ? '2nd'
      : value;
  return (years.isEmpty || years.join('-') == targetYears.join('-')) &&
      (term == null || ordinal(term) == ordinal(targetTerm));
}

class ScheduleImportSourceFile {
  const ScheduleImportSourceFile({
    required this.id,
    required this.name,
    required this.parsed,
  });
  final String id;
  final String name;
  final ParsedScheduleImport parsed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parsed': parsed.toJson(),
  };
  factory ScheduleImportSourceFile.fromJson(Map<String, dynamic> json) =>
      ScheduleImportSourceFile(
        id: json['id'].toString(),
        name: json['name'].toString(),
        parsed: ParsedScheduleImport.fromJson(
          Map<String, dynamic>.from(json['parsed'] as Map),
        ),
      );

  ScheduleImportSourceFile withRows(List<ParsedScheduleImportRow> rows) =>
      ScheduleImportSourceFile(
        id: id,
        name: name,
        parsed: parsed.copyWith(rows: rows),
      );
}

ScheduleImportSourceFile attachScheduleImportSource(
  ParsedScheduleImport parsed,
  String id,
  String name,
) => ScheduleImportSourceFile(
  id: id,
  name: name,
  parsed: parsed.copyWith(
    rows: [
      for (var i = 0; i < parsed.rows.length; i++)
        parsed.rows[i].copyWith(
          sourceFileId: id,
          sourceFileName: name,
          importRowId: '$id:$i',
          date: parsed.rows[i].date.trim().isEmpty ? parsed.date : null,
          room: parsed.rows[i].room.trim().isEmpty ? parsed.room : null,
          stage: parsed.rows[i].stage.trim().isEmpty ? parsed.stage : null,
        ),
    ],
  ),
);

ParsedScheduleImport combineScheduleImportSources(
  List<ScheduleImportSourceFile> files,
) => ParsedScheduleImport(
  rows: files.expand((file) => file.parsed.rows).toList(),
  isRedefense: files.any((file) => file.parsed.isRedefense),
);

/// Natural spreadsheet sessions follow committee lanes and explicit breaks.
/// Planned sessions use their own identity even when faculty assignments vary.
List<List<ParsedScheduleImportRow>> scheduleImportSessionGroups(
  List<ParsedScheduleImportRow> rows, {
  String date = '',
  String room = '',
  int duration = 60,
}) {
  final lanes = <String, List<ParsedScheduleImportRow>>{};
  for (final row in rows) {
    final rowDate = row.date.trim().isEmpty ? date : row.date.trim();
    final rowRoom = row.room.trim().isEmpty ? room : row.room.trim();
    final key = row.sessionId.isNotEmpty
        ? 'planned|${row.sessionId}|$rowDate|$rowRoom'
        : '${row.sourceFileId}|$rowDate|$rowRoom|${row.chair}|${row.panelMembers.join(',')}|${row.documenter}';
    (lanes[key.toLowerCase()] ??= []).add(row);
  }
  final groups = <List<ParsedScheduleImportRow>>[];
  for (final lane in lanes.values) {
    lane.sort(
      (a, b) => (scheduleTimeMinutes(a.startTime) ?? 0).compareTo(
        scheduleTimeMinutes(b.startTime) ?? 0,
      ),
    );
    List<ParsedScheduleImportRow>? group;
    int? previousEnd;
    for (final row in lane) {
      final start = scheduleTimeMinutes(row.startTime);
      if (group == null ||
          (row.sessionId.isEmpty &&
              previousEnd != null &&
              start != null &&
              start > previousEnd)) {
        group = <ParsedScheduleImportRow>[];
        groups.add(group);
      }
      group.add(row);
      previousEnd = start == null
          ? null
          : start + (row.slotDuration ?? duration);
    }
  }
  return groups;
}

class ScheduleImportSessionPlan {
  const ScheduleImportSessionPlan({
    required this.count,
    required this.start,
    required this.duration,
    required this.date,
    required this.room,
  });
  final int count;
  final String start;
  final int duration;
  final String date;
  final String room;
}

/// Allocates existing rows exactly once; names, source rows and faculty remain.
List<ParsedScheduleImportRow> applyScheduleImportSessionPlans(
  List<ParsedScheduleImportRow> rows,
  List<String> selectedIds,
  List<ScheduleImportSessionPlan> plans, {
  required String sessionPrefix,
}) {
  final byId = {for (final row in rows) row.importRowId: row};
  if (selectedIds.toSet().length != selectedIds.length ||
      selectedIds.any((id) => !byId.containsKey(id))) {
    throw const FormatException(
      'The selected source rows changed. Reopen Settings.',
    );
  }
  if (plans.isEmpty ||
      plans.any((plan) => plan.count < 1) ||
      plans.fold<int>(0, (total, plan) => total + plan.count) !=
          selectedIds.length) {
    throw const FormatException(
      'Assign every imported team to exactly one session.',
    );
  }
  final changed = <String, ParsedScheduleImportRow>{};
  var offset = 0;
  for (var i = 0; i < plans.length; i++) {
    final plan = plans[i], start = scheduleTimeMinutes(plan.start);
    if (start == null ||
        plan.duration < 15 ||
        plan.duration > 240 ||
        !scheduleImportDateIsValid(plan.date) ||
        plan.room.trim().isEmpty) {
      throw const FormatException(
        'Set a valid date, room, start time and duration for every session.',
      );
    }
    if (start + plan.count * plan.duration > 1440) {
      throw const FormatException(
        'A session extends past midnight. Adjust its timing or date.',
      );
    }
    for (var j = 0; j < plan.count; j++) {
      final id = selectedIds[offset++], row = byId[id]!;
      final rowStart = scheduleTimeFromMinutes(start + j * plan.duration);
      final rowEnd = scheduleTimeFromMinutes(start + (j + 1) * plan.duration);
      changed[id] = row.copyWith(
        sessionId: '$sessionPrefix:$i',
        date: plan.date,
        room: plan.room.trim(),
        startTime: rowStart,
        endTime: rowEnd,
        time: '$rowStart - $rowEnd',
        slotDuration: plan.duration,
      );
    }
  }
  return [for (final row in rows) changed[row.importRowId] ?? row];
}

/// Selected fields change within their own sessions; later session anchors stay.
List<ParsedScheduleImportRow> updateScheduleImportValues(
  List<ParsedScheduleImportRow> rows,
  Set<String> selectedIds, {
  String? date,
  String? room,
  int? duration,
  String fallbackDate = '',
  String fallbackRoom = '',
  int fallbackDuration = 60,
}) {
  final changed = <String, ParsedScheduleImportRow>{};
  final groups = scheduleImportSessionGroups(
    rows,
    date: fallbackDate,
    room: fallbackRoom,
    duration: fallbackDuration,
  );
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final hasDurationChange =
        duration != null &&
        group.any((row) => selectedIds.contains(row.importRowId));
    var nextStart = scheduleTimeMinutes(group.first.startTime);
    ParsedScheduleImportRow? previous;
    for (final row in group) {
      final selected = selectedIds.contains(row.importRowId);
      var updated = selected
          ? row.copyWith(date: date, room: room, slotDuration: duration)
          : row;
      if (hasDurationChange && nextStart != null && selected) {
        final originalStart = scheduleTimeMinutes(row.startTime);
        final previousStart = previous == null
            ? null
            : scheduleTimeMinutes(previous.startTime);
        if (previousStart != null && originalStart != null) {
          final gap =
              originalStart -
              (previousStart + (previous!.slotDuration ?? fallbackDuration));
          if (gap > 0) nextStart += gap;
        }
        final end = nextStart + (updated.slotDuration ?? fallbackDuration);
        updated = updated.copyWith(
          startTime: scheduleTimeFromMinutes(nextStart),
          endTime: scheduleTimeFromMinutes(end),
          time:
              '${scheduleTimeFromMinutes(nextStart)} - ${scheduleTimeFromMinutes(end)}',
          sessionId: row.sessionId.isEmpty
              ? 'timing:${group.first.importRowId}'
              : row.sessionId,
        );
        nextStart = end;
      } else if (hasDurationChange) {
        final start = scheduleTimeMinutes(row.startTime);
        nextStart = start == null
            ? null
            : start + (row.slotDuration ?? fallbackDuration);
      }
      changed[row.importRowId] = updated;
      previous = row;
    }
  }
  return [for (final row in rows) changed[row.importRowId] ?? row];
}
