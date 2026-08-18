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
  });

  final List<ParsedScheduleImportRow> rows;
  final String? stage;
  final String? date;
  final String? semester;
  final String? room;
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
      return parsed;
    }
  }
  return const ParsedScheduleImport(rows: []);
}

ParsedScheduleImport parseScheduleImportMatrix(List<List<String>> matrix) {
  if (matrix.isEmpty) {
    return const ParsedScheduleImport(rows: []);
  }

  final headerIndex = _findHeaderIndex(matrix);
  if (headerIndex < 0) {
    return const ParsedScheduleImport(rows: []);
  }

  final metadata = _readMetadata(matrix.take(headerIndex).toList());

  // Fallback for official client template layout (preceding rows without explicit key labels)
  if (headerIndex >= 1) {
    final titleRows = matrix.take(headerIndex).toList();
    final firstCells = titleRows
        .map((row) => row.firstWhere((cell) => cell.trim().isNotEmpty, orElse: () => ''))
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();

    if (firstCells.length >= 3) {
      if (metadata['stage'] == null || metadata['stage']!.isEmpty) {
        metadata['stage'] = firstCells[0];
      }
      if (metadata['date'] == null || metadata['date']!.isEmpty) {
        metadata['date'] = firstCells[1];
      }
      if (metadata['room'] == null || metadata['room']!.isEmpty) {
        metadata['room'] = firstCells[2];
      }
    } else if (firstCells.isNotEmpty) {
      for (final cell in firstCells) {
        final lowerCell = cell.toLowerCase();
        final isDate = RegExp(r'\d').hasMatch(cell) && (
            lowerCell.contains('jan') ||
            lowerCell.contains('feb') ||
            lowerCell.contains('mar') ||
            lowerCell.contains('apr') ||
            lowerCell.contains('may') ||
            lowerCell.contains('jun') ||
            lowerCell.contains('jul') ||
            lowerCell.contains('aug') ||
            lowerCell.contains('sep') ||
            lowerCell.contains('oct') ||
            lowerCell.contains('nov') ||
            lowerCell.contains('dec') ||
            cell.contains('/') ||
            (cell.contains('-') && !lowerCell.contains('room'))
        );
        final isRoom = lowerCell.contains('room') || lowerCell.contains('venue') || lowerCell.contains('hall') || lowerCell.contains('lab');

        if (isDate) {
          metadata['date'] ??= cell;
        } else if (isRoom) {
          metadata['room'] ??= cell;
        } else {
          metadata['stage'] ??= cell;
        }
      }
    }
  }

  final headers = matrix[headerIndex].map(_normalizeHeader).toList();
  int column(List<String> aliases) {
    for (var i = 0; i < headers.length; i++) {
      if (aliases.contains(headers[i])) {
        return i;
      }
    }
    return -1;
  }

  final timeCol = column(['time', 'timeslot', 'schedule', 'defensetime']);
  final teamCol = column(['teamname', 'team']);
  final projectCol = column(['capstoneproject', 'project', 'projecttitle']);
  final adviserCol = column(['adviser', 'advisor']);
  final memberCol = column(['teammembers', 'members', 'studentmembers']);
  final chairCol = column(['chair', 'panelchair', 'chairperson']);
  final panelCols = [
    column(['panelmember1', 'panel1', 'member1']),
    column(['panelmember2', 'panel2', 'member2']),
    column(['panelmember3', 'panel3', 'member3']),
  ].where((index) => index >= 0).toList();
  final documenterCol = column(['documenter', 'secretary', 'recorder']);
  final roomCol = column(['room', 'venue', 'roomvenue']);
  final dateCol = column(['date', 'defensedate', 'scheduleddate']);
  final stageCol = column(['stage', 'defensestage', 'event', 'pitevent']);
  final semesterCol = column(['semester', 'term']);

  final grouped = <String, _ImportGroup>{};
  final fillDown = <int, String>{};

  for (var rowIndex = headerIndex + 1; rowIndex < matrix.length; rowIndex++) {
    final rawRow = matrix[rowIndex];
    if (rawRow.every((cell) => cell.trim().isEmpty)) {
      continue;
    }

    String read(int index, {bool fill = true}) {
      if (index < 0 || index >= rawRow.length) {
        return '';
      }
      final value = rawRow[index].trim();
      if (value.isNotEmpty) {
        if (fill) {
          fillDown[index] = value;
        }
        return value;
      }
      return fill ? (fillDown[index] ?? '') : '';
    }

    final time = read(timeCol);
    final teamName = read(teamCol);
    final project = read(projectCol);
    final adviser = read(adviserCol);
    final chair = read(chairCol);
    final documenter = read(documenterCol);
    final room = read(roomCol);
    final date = read(dateCol);
    final stage = read(stageCol);
    final semester = read(semesterCol);
    if (stage.isNotEmpty) {
      metadata['stage'] = stage;
    }
    if (date.isNotEmpty) {
      metadata['date'] = date;
    }
    if (semester.isNotEmpty) {
      metadata['semester'] = semester;
    }
    if (room.isNotEmpty) {
      metadata['room'] ??= room;
    }

    final member = read(memberCol, fill: false);
    if (teamName.isEmpty && project.isEmpty && member.isEmpty) {
      continue;
    }

    final key = [
      _normalizeMatch(time),
      _normalizeMatch(teamName),
      _normalizeMatch(project),
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
        room: room,
        date: date,
        stage: stage,
      ),
    );
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

  return ParsedScheduleImport(
    rows: rows,
    stage: metadata['stage'],
    date: metadata['date'],
    semester: metadata['semester'],
    room: metadata['room'],
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

int _findHeaderIndex(List<List<String>> matrix) {
  for (var i = 0; i < matrix.length; i++) {
    final headers = matrix[i].map(_normalizeHeader).toSet();
    final hasTeam = headers.contains('teamname') || headers.contains('team');
    final hasSchedule =
        headers.contains('time') ||
        headers.contains('chair') ||
        headers.contains('panelmember1') ||
        headers.contains('documenter');
    if (hasTeam && hasSchedule) {
      return i;
    }
  }
  return -1;
}

Map<String, String> _readMetadata(List<List<String>> rows) {
  final result = <String, String>{};
  final semesterRegex = RegExp(r'\b(1st|2nd|Summer)\s*(?:Semester|sem)?\b', caseSensitive: false);

  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      final cell = row[i].trim();
      if (cell.isEmpty) {
        continue;
      }
      final normalized = _normalizeHeader(cell);
      final next = i + 1 < row.length ? row[i + 1].trim() : '';
      final inlineParts = cell.split(RegExp(r':\s*'));
      final inlineValue = inlineParts.length > 1
          ? inlineParts.sublist(1).join(':').trim()
          : '';
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
  final start = _parseTime(parts.first);
  final end = parts.length > 1 ? _parseTime(parts[1]) : '';
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
