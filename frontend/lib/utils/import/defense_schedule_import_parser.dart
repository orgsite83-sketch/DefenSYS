import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

class ParsedScheduleImport {
  const ParsedScheduleImport({
    required this.rows,
    this.stage,
    this.date,
    this.semester,
    this.room,
    this.isRedefense = false,
  });

  final List<ParsedScheduleImportRow> rows;
  final String? stage;
  final String? date;
  final String? semester;
  final String? room;
  final bool isRedefense;

  Map<String, dynamic> toJson() => {
    'rows': rows.map((r) => r.toJson()).toList(),
    'stage': stage,
    'date': date,
    'semester': semester,
    'room': room,
    'is_redefense': isRedefense,
  };

  factory ParsedScheduleImport.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List? ?? const [];
    return ParsedScheduleImport(
      rows: rawRows
          .map((r) => ParsedScheduleImportRow.fromJson(
                Map<String, dynamic>.from(r as Map),
              ))
          .toList(),
      stage: json['stage']?.toString(),
      date: json['date']?.toString(),
      semester: json['semester']?.toString(),
      room: json['room']?.toString(),
      isRedefense: json['is_redefense'] == true,
    );
  }

  ParsedScheduleImport copyWith({
    List<ParsedScheduleImportRow>? rows,
    String? stage,
    String? date,
    String? semester,
    String? room,
    bool? isRedefense,
  }) {
    return ParsedScheduleImport(
      rows: rows ?? this.rows,
      stage: stage ?? this.stage,
      date: date ?? this.date,
      semester: semester ?? this.semester,
      room: room ?? this.room,
      isRedefense: isRedefense ?? this.isRedefense,
    );
  }
}

class ParsedScheduleImportRow {
  const ParsedScheduleImportRow({
    required this.sheetRow,
    required this.time,
    required this.teamName,
    required this.projectTitle,
    required this.adviser,
    required this.members,
    required this.chair,
    required this.panelMembers,
    required this.documenter,
    required this.room,
    required this.date,
    required this.stage,
    required this.startTime,
    required this.endTime,
    required this.slotDuration,
  });

  final int sheetRow;
  final String time;
  final String teamName;
  final String projectTitle;
  final String adviser;
  final List<String> members;
  final String chair;
  final List<String> panelMembers;
  final String documenter;
  final String room;
  final String date;
  final String stage;
  final String startTime;
  final String endTime;
  final int? slotDuration;

  Map<String, dynamic> toJson() => {
    'sheet_row': sheetRow,
    'time': time,
    'team_name': teamName,
    'project_title': projectTitle,
    'adviser': adviser,
    'members': members,
    'chair': chair,
    'panel_members': panelMembers,
    'documenter': documenter,
    'room': room,
    'date': date,
    'stage': stage,
    'start_time': startTime,
    'end_time': endTime,
    'slot_duration': slotDuration,
  };

  factory ParsedScheduleImportRow.fromJson(Map<String, dynamic> json) {
    return ParsedScheduleImportRow(
      sheetRow: json['sheet_row'] is int
          ? json['sheet_row'] as int
          : int.tryParse(json['sheet_row']?.toString() ?? '') ?? 0,
      time: json['time']?.toString() ?? '',
      teamName: json['team_name']?.toString() ?? '',
      projectTitle: json['project_title']?.toString() ?? '',
      adviser: json['adviser']?.toString() ?? '',
      members: (json['members'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      chair: json['chair']?.toString() ?? '',
      panelMembers: (json['panel_members'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      documenter: json['documenter']?.toString() ?? '',
      room: json['room']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      stage: json['stage']?.toString() ?? '',
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      slotDuration: json['slot_duration'] is int
          ? json['slot_duration'] as int
          : int.tryParse(json['slot_duration']?.toString() ?? ''),
    );
  }

  ParsedScheduleImportRow copyWith({
    int? sheetRow,
    String? time,
    String? teamName,
    String? projectTitle,
    String? adviser,
    List<String>? members,
    String? chair,
    List<String>? panelMembers,
    String? documenter,
    String? room,
    String? date,
    String? stage,
    String? startTime,
    String? endTime,
    int? slotDuration,
  }) {
    return ParsedScheduleImportRow(
      sheetRow: sheetRow ?? this.sheetRow,
      time: time ?? this.time,
      teamName: teamName ?? this.teamName,
      projectTitle: projectTitle ?? this.projectTitle,
      adviser: adviser ?? this.adviser,
      members: members ?? this.members,
      chair: chair ?? this.chair,
      panelMembers: panelMembers ?? this.panelMembers,
      documenter: documenter ?? this.documenter,
      room: room ?? this.room,
      date: date ?? this.date,
      stage: stage ?? this.stage,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      slotDuration: slotDuration ?? this.slotDuration,
    );
  }
}

ParsedScheduleImport parseScheduleImportFile({
  required Uint8List bytes,
  required String filename,
}) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.csv')) {
    return parseScheduleImportMatrix(_csvToMatrix(utf8.decode(bytes)));
  }

  final workbook = Excel.decodeBytes(bytes);
  final allRows = <ParsedScheduleImportRow>[];
  String? detectedStage;
  String? detectedDate;
  String? detectedSemester;
  String? detectedRoom;
  var isRedefense = false;

  for (final tableName in workbook.tables.keys) {
    final sheet = workbook.tables[tableName];
    if (sheet == null || sheet.rows.isEmpty) {
      continue;
    }
    final matrix = sheet.rows
        .map((row) => row.map(_excelCellText).toList(growable: false))
        .toList(growable: false);
    final parsed = parseScheduleImportMatrix(matrix);
    if (parsed.rows.isNotEmpty) {
      allRows.addAll(parsed.rows);
      detectedStage ??= parsed.stage;
      detectedDate ??= parsed.date;
      detectedSemester ??= parsed.semester;
      detectedRoom ??= parsed.room;
      if (parsed.isRedefense) isRedefense = true;
    }
  }

  return ParsedScheduleImport(
    rows: allRows,
    stage: detectedStage,
    date: detectedDate,
    semester: detectedSemester,
    room: detectedRoom,
    isRedefense: isRedefense,
  );
}

ParsedScheduleImport parseScheduleImportMatrix(List<List<String>> matrix) {
  if (matrix.isEmpty) {
    return const ParsedScheduleImport(rows: []);
  }

  final metadata = <String, String>{};
  String currentStage = '';
  String currentDate = '';
  String currentRoom = '';
  String currentSemester = '';

  final grouped = <String, _ImportGroup>{};
  final fillDown = <int, String>{};

  var headerFound = false;
  var timeCol = -1;
  var teamCol = -1;
  var projectCol = -1;
  var adviserCol = -1;
  var memberCol = -1;
  var chairCol = -1;
  var panelCols = <int>[];
  var documenterCol = -1;
  var roomCol = -1;
  var dateCol = -1;
  var stageCol = -1;
  var semesterCol = -1;

  void applyHeader(List<String> row) {
    final headers = row.map(_normalizeHeader).toList();
    int column(List<String> aliases) {
      for (var i = 0; i < headers.length; i++) {
        if (aliases.contains(headers[i])) return i;
      }
      return -1;
    }

    timeCol = column(['time', 'timeslot', 'schedule', 'defensetime']);
    teamCol = column(['teamname', 'team']);
    projectCol = column(['capstoneproject', 'project', 'projecttitle']);
    adviserCol = column(['adviser', 'advisor']);
    memberCol = column(['teammembers', 'members', 'studentmembers']);
    chairCol = column(['chair', 'panelchair', 'chairperson']);
    panelCols = [
      column(['panelmember1', 'panel1', 'member1']),
      column(['panelmember2', 'panel2', 'member2']),
      column(['panelmember3', 'panel3', 'member3']),
    ].where((index) => index >= 0).toList();
    documenterCol = column(['documenter', 'secretary', 'recorder']);
    roomCol = column(['room', 'venue', 'roomvenue']);
    dateCol = column(['date', 'defensedate', 'scheduleddate']);
    stageCol = column(['stage', 'defensestage', 'event', 'pitevent']);
    semesterCol = column(['semester', 'term']);
    headerFound = true;
    fillDown.clear();
  }

  for (var rowIndex = 0; rowIndex < matrix.length; rowIndex++) {
    final rawRow = matrix[rowIndex];
    if (rawRow.every((cell) => cell.trim().isEmpty)) {
      fillDown.clear();
      continue;
    }

    // 1. Repeated or initial column header row
    if (_isHeaderRow(rawRow)) {
      applyHeader(rawRow);
      continue;
    }

    // 2. Preamble metadata before first table header
    if (!headerFound) {
      final rowMeta = _readMetadataRow(rawRow);
      if (rowMeta['stage'] != null && rowMeta['stage']!.isNotEmpty) {
        currentStage = rowMeta['stage']!;
        metadata['stage'] ??= currentStage;
      }
      if (rowMeta['date'] != null && rowMeta['date']!.isNotEmpty) {
        currentDate = rowMeta['date']!;
        metadata['date'] ??= currentDate;
      }
      if (rowMeta['room'] != null && rowMeta['room']!.isNotEmpty) {
        currentRoom = rowMeta['room']!;
        metadata['room'] ??= currentRoom;
      }
      if (rowMeta['semester'] != null && rowMeta['semester']!.isNotEmpty) {
        currentSemester = rowMeta['semester']!;
        metadata['semester'] ??= currentSemester;
      }
      continue;
    }

    // 3. Header already found; check if this row is a Section / Metadata divider row
    final rawTime = (timeCol >= 0 && timeCol < rawRow.length) ? rawRow[timeCol].trim() : '';
    final rawTeam = (teamCol >= 0 && teamCol < rawRow.length) ? rawRow[teamCol].trim() : '';
    final rawMember = (memberCol >= 0 && memberCol < rawRow.length) ? rawRow[memberCol].trim() : '';
    final parsedTime = _parseTimeRange(rawTime);
    final hasValidTime = parsedTime.start.isNotEmpty;

    // Check for repeated header text in cells (e.g. literal "Team Name" or "Time")
    final normTeam = _normalizeHeader(rawTeam);
    final normTime = _normalizeHeader(rawTime);
    if (normTeam == 'teamname' || normTeam == 'team' || normTime == 'time' || normTime == 'timeslot') {
      fillDown.clear();
      continue;
    }

    // If row has no valid defense time, no team name, and no student member,
    // it is a section metadata divider row (e.g. "6/19/2026" or "Room 301")
    if (!hasValidTime && rawTeam.isEmpty && rawMember.isEmpty) {
      final rowMeta = _readMetadataRow(rawRow);
      if (rowMeta['stage'] != null && rowMeta['stage']!.isNotEmpty) {
        currentStage = rowMeta['stage']!;
        metadata['stage'] ??= currentStage;
      }
      if (rowMeta['date'] != null && rowMeta['date']!.isNotEmpty) {
        currentDate = rowMeta['date']!;
        metadata['date'] ??= currentDate;
      }
      if (rowMeta['room'] != null && rowMeta['room']!.isNotEmpty) {
        currentRoom = rowMeta['room']!;
        metadata['room'] ??= currentRoom;
      }
      if (rowMeta['semester'] != null && rowMeta['semester']!.isNotEmpty) {
        currentSemester = rowMeta['semester']!;
        metadata['semester'] ??= currentSemester;
      }
      fillDown.clear();
      continue;
    }

    // 4. Read helper with fill-down support
    String read(int index, {bool fill = true}) {
      if (index < 0 || index >= rawRow.length) return '';
      final value = rawRow[index].trim();
      if (value.isNotEmpty) {
        if (fill) fillDown[index] = value;
        return value;
      }
      return fill ? (fillDown[index] ?? '') : '';
    }

    // Check if this is a member continuation row for the current team
    if (rawTeam.isEmpty && rawMember.isNotEmpty) {
      if (grouped.isNotEmpty) {
        final lastGroup = grouped.values.last;
        if (!lastGroup.members.contains(rawMember)) {
          lastGroup.members.add(rawMember);
        }
      }
      continue;
    }

    // If no team name and no valid time, skip
    if (rawTeam.isEmpty && !hasValidTime) {
      continue;
    }

    final time = read(timeCol);
    final teamName = read(teamCol);
    final project = read(projectCol);
    final adviser = read(adviserCol);
    final chair = read(chairCol);
    final documenter = read(documenterCol);
    final colRoom = read(roomCol, fill: false);
    final colDate = read(dateCol, fill: false);
    final colStage = read(stageCol, fill: false);
    final colSemester = read(semesterCol, fill: false);

    final effectiveRoom = colRoom.isNotEmpty ? colRoom : currentRoom;
    final effectiveDate = colDate.isNotEmpty ? colDate : currentDate;
    final effectiveStage = colStage.isNotEmpty ? colStage : currentStage;
    if (colSemester.isNotEmpty) currentSemester = colSemester;

    if (teamName.isEmpty && project.isEmpty) {
      continue;
    }

    final key = [
      _normalizeMatch(effectiveDate),
      _normalizeMatch(effectiveRoom),
      _normalizeMatch(time),
      _normalizeMatch(teamName),
    ].join('|');

    final group = grouped.putIfAbsent(
      key,
      () => _ImportGroup(
        sheetRow: rowIndex + 1,
        time: time,
        teamName: teamName,
        projectTitle: project,
        adviser: adviser,
        chair: chair,
        panelMembers: [
          for (final panelCol in panelCols) read(panelCol),
        ].where((name) => name.isNotEmpty).toList(),
        documenter: documenter,
        room: effectiveRoom,
        date: effectiveDate,
        stage: effectiveStage,
      ),
    );

    final member = read(memberCol, fill: false);
    if (member.isNotEmpty && !group.members.contains(member)) {
      group.members.add(member);
    }
  }

  final rows = grouped.values
      .where((group) => group.teamName.isNotEmpty)
      .map((group) {
        final parsedTime = _parseTimeRange(group.time);
        return ParsedScheduleImportRow(
          sheetRow: group.sheetRow,
          time: group.time,
          teamName: group.teamName,
          projectTitle: group.projectTitle,
          adviser: group.adviser,
          members: group.members,
          chair: group.chair,
          panelMembers: group.panelMembers,
          documenter: group.documenter,
          room: group.room,
          date: group.date,
          stage: group.stage,
          startTime: parsedTime.start,
          endTime: parsedTime.end,
          slotDuration: parsedTime.duration,
        );
      })
      .toList(growable: false);

  final rawStage = (metadata['stage'] ?? currentStage).toLowerCase();
  final isRedefense = rawStage.contains('redef') ||
      rawStage.contains('redefense') ||
      rawStage.contains('re-defense');

  return ParsedScheduleImport(
    rows: rows,
    stage: metadata['stage'] ?? currentStage,
    date: metadata['date'] ?? currentDate,
    semester: metadata['semester'] ?? currentSemester,
    room: metadata['room'] ?? currentRoom,
    isRedefense: isRedefense,
  );
}

String _excelCellText(Data? cell) {
  final value = cell?.value;
  return switch (value) {
    null => '',
    TextCellValue() => (value.value.text ?? '').trim(),
    FormulaCellValue() => value.formula.trim(),
    IntCellValue() => value.value.toString(),
    DoubleCellValue() => _trimNumber(value.value),
    BoolCellValue() => value.value ? 'true' : 'false',
    DateCellValue() => _formatDate(value.asDateTimeLocal()),
    DateTimeCellValue() => _formatDate(value.asDateTimeLocal()),
    TimeCellValue() => _durationToTime(value.asDuration()),
  };
}

String _trimNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toString();
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _durationToTime(Duration duration) {
  final minutes = duration.inMinutes;
  final hour = (minutes ~/ 60) % 24;
  final minute = minutes % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

bool _isHeaderRow(List<String> row) {
  final normalized = row.map(_normalizeHeader).toSet();
  final hasTeam = normalized.contains('teamname') || normalized.contains('team');
  final hasSchedule = normalized.contains('time') ||
      normalized.contains('chair') ||
      normalized.contains('panelmember1') ||
      normalized.contains('documenter') ||
      normalized.contains('timeslot');
  return hasTeam && hasSchedule;
}

bool _isDateString(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  if (RegExp(r'^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$').hasMatch(trimmed)) return true;
  final hasDigits = RegExp(r'\d').hasMatch(trimmed);
  final monthMatches = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
  ].any((m) => lower.contains(m));
  return hasDigits && monthMatches && !lower.contains('room');
}

bool _isRoomString(String text) {
  final lower = text.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower.contains('room') ||
      lower.contains('venue') ||
      lower.contains('hall') ||
      lower.contains('lab') ||
      lower.contains('avr') ||
      lower.contains('audi') ||
      lower.startsWith('rm') ||
      RegExp(r'^(?:smart\s+room|multimedia|conference)$').hasMatch(lower);
}

bool _isStageOrSessionString(String text) {
  final lower = text.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower.contains('proposal') ||
      lower.contains('defense') ||
      lower.contains('redefense') ||
      lower.contains('capstone') ||
      lower.contains('session') ||
      lower.contains('day 1') ||
      lower.contains('day 2') ||
      lower.contains('day 3') ||
      lower.contains('day 4') ||
      lower.contains('morning') ||
      lower.contains('afternoon');
}

Map<String, String> _readMetadataRow(List<String> row) {
  final result = <String, String>{};
  final semesterRegex =
      RegExp(r'\b(1st|2nd|Summer)\s*(?:Semester|sem)?\b', caseSensitive: false);

  for (var i = 0; i < row.length; i++) {
    final cell = row[i].trim();
    if (cell.isEmpty) continue;
    final normalized = _normalizeHeader(cell);
    final next = i + 1 < row.length ? row[i + 1].trim() : '';
    final inlineParts = cell.split(RegExp(r':\s*'));
    final inlineValue =
        inlineParts.length > 1 ? inlineParts.sublist(1).join(':').trim() : '';
    final value = inlineValue.isNotEmpty ? inlineValue : next;

    if (value.isNotEmpty) {
      if (['stage', 'defensestage'].contains(normalized)) {
        result['stage'] = value;
      }
      if (['date', 'defensedate', 'scheduleddate'].contains(normalized)) {
        result['date'] = value;
      }
      if (['semester', 'term'].contains(normalized)) {
        result['semester'] = value;
      }
      if (['room', 'venue', 'roomvenue'].contains(normalized)) {
        result['room'] = value;
      }
    }

    if (result['semester'] == null || result['semester']!.isEmpty) {
      final semMatch = semesterRegex.firstMatch(cell);
      if (semMatch != null) {
        final rawSem = semMatch.group(1)!.toLowerCase();
        if (rawSem.contains('1st')) {
          result['semester'] = '1st Semester';
        } else if (rawSem.contains('2nd')) {
          result['semester'] = '2nd Semester';
        } else if (rawSem.contains('summer')) {
          result['semester'] = 'Summer';
        }
      }
    }

    if (result['date'] == null && _isDateString(cell)) {
      result['date'] = cell;
    } else if (result['room'] == null && _isRoomString(cell)) {
      result['room'] = cell;
    } else if (result['stage'] == null && _isStageOrSessionString(cell)) {
      result['stage'] = cell;
    }
  }

  final nonEmpty =
      row.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  if (nonEmpty.length == 1) {
    final single = nonEmpty.first;
    if (result['date'] == null && _isDateString(single)) {
      result['date'] = single;
    } else if (result['room'] == null && _isRoomString(single)) {
      result['room'] = single;
    } else if (result['stage'] == null && _isStageOrSessionString(single)) {
      result['stage'] = single;
    }
  }

  return result;
}

String _normalizeHeader(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _normalizeMatch(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

_TimeRange _parseTimeRange(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const _TimeRange(start: '', end: '', duration: null);
  }
  final parts = text.split(RegExp(r'\s*(?:-|–|—|to)\s*', caseSensitive: false));
  if (parts.isEmpty) {
    return const _TimeRange(start: '', end: '', duration: null);
  }
  var startStr = parts.first.trim();
  var endStr = parts.length > 1 ? parts[1].trim() : '';

  // If end has AM/PM but start doesn't, inherit meridiem intelligently
  final upperStart = startStr.toUpperCase();
  final upperEnd = endStr.toUpperCase();
  final hasStartMeridiem = upperStart.contains('AM') || upperStart.contains('PM');
  final hasEndMeridiem = upperEnd.contains('AM') || upperEnd.contains('PM');

  if (!hasStartMeridiem && hasEndMeridiem) {
    if (upperEnd.contains('PM')) {
      final startHourMatch = RegExp(r'^(\d{1,2})').firstMatch(startStr);
      final startHour = int.tryParse(startHourMatch?.group(1) ?? '') ?? 0;
      final endHourMatch = RegExp(r'^(\d{1,2})').firstMatch(endStr);
      final endHour = int.tryParse(endHourMatch?.group(1) ?? '') ?? 0;
      if (startHour <= endHour || endHour == 12) {
        startStr += ' PM';
      } else {
        startStr += ' AM';
      }
    } else if (upperEnd.contains('AM')) {
      startStr += ' AM';
    }
  }

  final start = _parseTime(startStr);
  final end = endStr.isNotEmpty ? _parseTime(endStr) : '';
  return _TimeRange(
    start: start,
    end: end,
    duration: start.isNotEmpty && end.isNotEmpty
        ? _minutesBetween(start, end)
        : null,
  );
}

String _parseTime(String raw) {
  var text = raw.trim().toUpperCase().replaceAll(' ', '');
  if (text.isEmpty) {
    return '';
  }
  final meridiem = text.endsWith('AM')
      ? 'AM'
      : text.endsWith('PM')
          ? 'PM'
          : '';
  if (meridiem.isNotEmpty) {
    text = text.substring(0, text.length - 2);
  }
  final match = RegExp(r'^(\d{1,2})(?::?(\d{2}))?$').firstMatch(text);
  if (match == null) {
    return '';
  }
  var hour = int.tryParse(match.group(1) ?? '') ?? 0;
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;

  if (meridiem == 'PM' && hour < 12) {
    hour += 12;
  }
  if (meridiem == 'AM' && hour == 12) {
    hour = 0;
  }
  // In typical academic schedules, afternoon slots like "1:00" to "6:00" without meridiem are PM
  if (meridiem.isEmpty && hour >= 1 && hour <= 6) {
    hour += 12;
  }

  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return '';
  }
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

int _minutesBetween(String start, String end) {
  final startMinutes = _timeMinutes(start);
  var endMinutes = _timeMinutes(end);
  if (endMinutes <= startMinutes) {
    endMinutes += 24 * 60;
  }
  return endMinutes - startMinutes;
}

int _timeMinutes(String time) {
  final parts = time.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return hour * 60 + minute;
}

List<List<String>> _csvToMatrix(String csv) {
  final rows = <List<String>>[];
  final currentRow = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < csv.length; i++) {
    final char = csv[i];
    if (char == '"') {
      if (inQuotes && i + 1 < csv.length && csv[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      currentRow.add(cell.toString().trim());
      cell.clear();
    } else if ((char == '\n' || char == '\r') && !inQuotes) {
      if (char == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') {
        i++;
      }
      currentRow.add(cell.toString().trim());
      cell.clear();
      if (currentRow.any((item) => item.isNotEmpty)) {
        rows.add(List<String>.from(currentRow));
      }
      currentRow.clear();
    } else {
      cell.write(char);
    }
  }

  currentRow.add(cell.toString().trim());
  if (currentRow.any((item) => item.isNotEmpty)) {
    rows.add(currentRow);
  }
  return rows;
}

class _ImportGroup {
  _ImportGroup({
    required this.sheetRow,
    required this.time,
    required this.teamName,
    required this.projectTitle,
    required this.adviser,
    required this.chair,
    required this.panelMembers,
    required this.documenter,
    required this.room,
    required this.date,
    required this.stage,
  });

  final int sheetRow;
  final String time;
  final String teamName;
  final String projectTitle;
  final String adviser;
  final String chair;
  final List<String> panelMembers;
  final String documenter;
  final String room;
  final String date;
  final String stage;
  final List<String> members = [];
}

class _TimeRange {
  const _TimeRange({
    required this.start,
    required this.end,
    required this.duration,
  });

  final String start;
  final String end;
  final int? duration;
}
