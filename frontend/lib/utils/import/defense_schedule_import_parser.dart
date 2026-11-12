import 'tabular_text_decode.dart';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:defensys/utils/excel_safe_decode.dart';
import 'package:defensys/utils/string_matching_utils.dart';

// Use the same schema for header detection and column extraction. Only known
// aliases are mapped automatically; approximate matches are suggestions.
const _headerAliases = <String, List<String>>{
  'Time': ['time', 'timeslot', 'schedule', 'defensetime'],
  'Team Name': ['teamname', 'team'],
  'Capstone Project': ['capstoneproject', 'project', 'projecttitle'],
  'Adviser': ['adviser', 'advisor'],
  'Instructor': ['instructor', 'sectioninstructor', 'pitinstructor'],
  'Team Members': ['teammembers', 'members', 'studentmembers'],
  'Chair': [
    'chair',
    'panelchair',
    'chairpanel',
    'chairperson',
    'chairman',
    'panelchairperson',
    'chairpersonpanel',
    'panelchairman',
    'chairofpanel',
  ],
  'Panel Member 1': ['panelmember1', 'panel1', 'member1', 'panelist1'],
  'Panel Member 2': ['panelmember2', 'panel2', 'member2', 'panelist2'],
  'Panel Member 3': ['panelmember3', 'panel3', 'member3', 'panelist3'],
  'Documenter': ['documenter', 'secretary', 'recorder'],
  'Room': ['room', 'venue', 'roomvenue'],
  'Date': ['date', 'defensedate', 'scheduleddate'],
  'Stage': ['stage', 'defensestage', 'event', 'pitevent'],
  'Semester': ['semester', 'term'],
};

String? _headerRole(String header) {
  final normalized = _normalizeHeader(header);
  for (final entry in _headerAliases.entries) {
    if (entry.value.contains(normalized)) return entry.key;
  }
  return null;
}

bool _isSequenceHeader(String header) =>
    header.trim() == '#' ||
    [
      'no',
      'number',
      'sno',
      'seq',
      'sequence',
    ].contains(_normalizeHeader(header));

String _headerSuggestion(String header) {
  final normalized = _normalizeHeader(header);
  if (normalized.isEmpty) return '';
  final scores = <String, double>{};
  for (final entry in _headerAliases.entries) {
    scores[entry.key] = entry.value
        .map((alias) => stringSimilarity(normalized, alias))
        .reduce((a, b) => a > b ? a : b);
  }
  final ranked = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (ranked.first.value < 0.75 || ranked.first.value - ranked[1].value < 0.1) {
    return '';
  }
  return ' Did you mean "${ranked.first.key}"?';
}

class ParsedScheduleImport {
  const ParsedScheduleImport({
    required this.rows,
    this.stage,
    this.date,
    this.semester,
    this.room,
    this.isRedefense = false,
    this.parserVersion = 2,
    this.ignoredRows = const [],
  });

  final List<ParsedScheduleImportRow> rows;
  final String? stage;
  final String? date;
  final String? semester;
  final String? room;
  final bool isRedefense;
  final int parserVersion;
  final List<Map<String, dynamic>> ignoredRows;

  Map<String, dynamic> toJson() => {
    'rows': rows.map((r) => r.toJson()).toList(),
    'stage': stage,
    'date': date,
    'semester': semester,
    'room': room,
    'is_redefense': isRedefense,
    'parser_version': parserVersion,
    'ignored_rows': ignoredRows,
  };

  factory ParsedScheduleImport.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List? ?? const [];
    return ParsedScheduleImport(
      rows: rawRows
          .map(
            (r) => ParsedScheduleImportRow.fromJson(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList(),
      stage: json['stage']?.toString(),
      date: json['date']?.toString(),
      semester: json['semester']?.toString(),
      room: json['room']?.toString(),
      isRedefense: json['is_redefense'] == true,
      parserVersion: json['parser_version'] as int? ?? 1,
      ignoredRows: (json['ignored_rows'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  ParsedScheduleImport copyWith({
    List<ParsedScheduleImportRow>? rows,
    String? stage,
    String? date,
    String? semester,
    String? room,
    bool? isRedefense,
    List<Map<String, dynamic>>? ignoredRows,
  }) {
    return ParsedScheduleImport(
      rows: rows ?? this.rows,
      stage: stage ?? this.stage,
      date: date ?? this.date,
      semester: semester ?? this.semester,
      room: room ?? this.room,
      isRedefense: isRedefense ?? this.isRedefense,
      parserVersion: parserVersion,
      ignoredRows: ignoredRows ?? this.ignoredRows,
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
    this.instructor = '',
    this.hasAdviserColumn = false,
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
    this.parseIssues = const [],
    this.sourceFileId = '',
    this.sourceFileName = '',
    this.importRowId = '',
    this.sessionId = '',
    this.sourceSheetName = '',
    this.selectedAccountIds = const {},
  });

  final int sheetRow;
  final String time;
  final String teamName;
  final String projectTitle;
  final String adviser;
  final String instructor;
  final bool hasAdviserColumn;
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
  final List<String> parseIssues;
  // Review identities survive edits, duplicate sheet row numbers and retries.
  final String sourceFileId;
  final String sourceFileName;
  final String importRowId;
  final String sessionId;
  final String sourceSheetName;
  final Map<String, int> selectedAccountIds;

  Map<String, dynamic> toJson() => {
    'sheet_row': sheetRow,
    'time': time,
    'team_name': teamName,
    'project_title': projectTitle,
    'adviser': adviser,
    'instructor': instructor,
    'has_adviser_column': hasAdviserColumn,
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
    'parse_issues': parseIssues,
    'source_file_id': sourceFileId,
    'source_file_name': sourceFileName,
    'import_row_id': importRowId,
    'session_id': sessionId,
    'source_sheet_name': sourceSheetName,
    'selected_account_ids': selectedAccountIds,
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
      instructor: json['instructor']?.toString() ?? '',
      hasAdviserColumn: json['has_adviser_column'] == true,
      members:
          (json['members'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      chair: json['chair']?.toString() ?? '',
      panelMembers:
          (json['panel_members'] as List?)?.map((e) => e.toString()).toList() ??
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
      parseIssues:
          (json['parse_issues'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      sourceFileId: json['source_file_id']?.toString() ?? '',
      sourceFileName: json['source_file_name']?.toString() ?? '',
      importRowId: json['import_row_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      sourceSheetName: json['source_sheet_name']?.toString() ?? '',
      selectedAccountIds: {
        for (final entry
            in (json['selected_account_ids'] as Map? ?? const {}).entries)
          if ((int.tryParse('${entry.value}') ?? 0) > 0)
            '${entry.key}': int.parse('${entry.value}'),
      },
    );
  }

  ParsedScheduleImportRow copyWith({
    int? sheetRow,
    String? time,
    String? teamName,
    String? projectTitle,
    String? adviser,
    String? instructor,
    bool? hasAdviserColumn,
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
    List<String>? parseIssues,
    String? sourceFileId,
    String? sourceFileName,
    String? importRowId,
    String? sessionId,
    String? sourceSheetName,
    Map<String, int>? selectedAccountIds,
  }) {
    return ParsedScheduleImportRow(
      sheetRow: sheetRow ?? this.sheetRow,
      time: time ?? this.time,
      teamName: teamName ?? this.teamName,
      projectTitle: projectTitle ?? this.projectTitle,
      adviser: adviser ?? this.adviser,
      instructor: instructor ?? this.instructor,
      hasAdviserColumn: hasAdviserColumn ?? this.hasAdviserColumn,
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
      parseIssues: parseIssues ?? this.parseIssues,
      sourceFileId: sourceFileId ?? this.sourceFileId,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      importRowId: importRowId ?? this.importRowId,
      sessionId: sessionId ?? this.sessionId,
      sourceSheetName: sourceSheetName ?? this.sourceSheetName,
      selectedAccountIds: selectedAccountIds ?? this.selectedAccountIds,
    );
  }
}

bool _isLikelyTeamRosterWorkbook(Excel workbook) {
  for (final tableName in workbook.tables.keys) {
    final lowerName = tableName.toLowerCase();
    if (lowerName.contains('team_roster') ||
        lowerName.contains('team roster')) {
      return true;
    }
    final sheet = workbook.tables[tableName];
    if (sheet == null) continue;
    var hasTeamName = false;
    var hasMembers = false;
    var hasSection = false;
    var hasTimeSlot = false;
    for (final row in sheet.rows.take(20)) {
      for (final cell in row) {
        final text = _excelCellText(cell).toLowerCase().trim();
        if (text.contains('team name') || text.startsWith('team')) {
          hasTeamName = true;
        }
        if (text.contains('member') || text.contains('team members')) {
          hasMembers = true;
        }
        if (text == 'section') hasSection = true;
        if (text.contains('time slot') ||
            text.contains('start time') ||
            text == 'time') {
          hasTimeSlot = true;
        }
      }
    }
    if ((hasMembers || (hasTeamName && hasSection)) && !hasTimeSlot) {
      return true;
    }
  }
  return false;
}

bool _isLikelyTeamRosterCsv(String csvContent) {
  final lower = csvContent.toLowerCase();
  final hasMembers = lower.contains('team members') || lower.contains('member');
  final hasSection = lower.contains('section');
  final hasTimeSlot =
      lower.contains('time slot') || lower.contains('start time');
  return hasMembers && hasSection && !hasTimeSlot;
}

ParsedScheduleImport parseScheduleImportFile({
  required Uint8List bytes,
  required String filename,
  Iterable<String>? configuredStages,
  bool encodingConfirmed = false,
}) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.csv')) {
    final decoded = decodeTabularText(bytes);
    if (decoded.needsConfirmation && !encodingConfirmed) {
      throw FormatException(
        '$filename: confirm the displayed names before staging this CSV.',
      );
    }
    final csvText = decoded.text;
    final parsed = parseScheduleImportMatrix(
      _csvToMatrix(csvText),
      configuredStages: configuredStages,
    );
    if (parsed.rows.isEmpty && _isLikelyTeamRosterCsv(csvText)) {
      throw FormatException(
        '$filename is a Student Team Roster file, not a Defense Schedule timetable. Please import it under Student Teams > Import Teams.',
      );
    }
    return parsed;
  }

  final workbook = safeDecodeExcel(bytes);
  final allRows = <ParsedScheduleImportRow>[];
  final ignoredRows = <Map<String, dynamic>>[];
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
    final matrix = _sheetMatrix(sheet);
    final parsed = parseScheduleImportMatrix(
      matrix,
      configuredStages: configuredStages,
    );
    if (parsed.rows.isNotEmpty) {
      allRows.addAll(
        parsed.rows.map((row) => row.copyWith(sourceSheetName: tableName)),
      );
      ignoredRows.addAll(
        parsed.ignoredRows.map((row) => {...row, 'sheet': tableName}),
      );
      detectedStage ??= parsed.stage;
      detectedDate ??= parsed.date;
      detectedSemester ??= parsed.semester;
      detectedRoom ??= parsed.room;
      if (parsed.isRedefense) isRedefense = true;
    }
  }

  if (allRows.isEmpty && _isLikelyTeamRosterWorkbook(workbook)) {
    throw FormatException(
      '$filename is a Student Team Roster file, not a Defense Schedule timetable. Please import it under Student Teams > Import Teams.',
    );
  }

  return ParsedScheduleImport(
    rows: allRows,
    ignoredRows: ignoredRows,
    stage: detectedStage,
    date: detectedDate,
    semester: detectedSemester,
    room: detectedRoom,
    isRedefense: isRedefense,
  );
}

ParsedScheduleImport parseScheduleImportMatrix(
  List<List<String>> matrix, {
  Iterable<String>? configuredStages,
}) {
  if (matrix.isEmpty) {
    return const ParsedScheduleImport(rows: []);
  }

  final metadata = <String, String>{};
  final ignoredRows = <Map<String, dynamic>>[];
  final metadataIssues = <String>[];
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
  var instructorCol = -1;
  var memberCol = -1;
  var chairCol = -1;
  var panelCols = <int>[];
  var documenterCol = -1;
  var roomCol = -1;
  var dateCol = -1;
  var stageCol = -1;
  var semesterCol = -1;
  var activeHeaders = <String>[];
  var recognizedColumns = <int>{};
  var headerIssues = <String>[];
  var headerRow = 0;

  void applyHeader(List<String> row, int sheetRow) {
    activeHeaders = row;
    headerRow = sheetRow;
    recognizedColumns = <int>{};
    headerIssues = <String>[];
    final roles = row.map(_headerRole).toList();
    int column(String role) {
      final matches = <int>[];
      for (var i = 0; i < roles.length; i++) {
        if (roles[i] == role) {
          matches.add(i);
          recognizedColumns.add(i);
        }
      }
      if (matches.length > 1) {
        headerIssues.add(
          'Header row $sheetRow has multiple "$role" columns '
          '(${matches.map((i) => i + 1).join(', ')}). Keep one column for this role.',
        );
        return -1;
      }
      return matches.isEmpty ? -1 : matches.single;
    }

    timeCol = column('Time');
    // Keep rows visible for review even if the team mapping is ambiguous.
    teamCol = column('Team Name');
    if (teamCol < 0) teamCol = roles.indexOf('Team Name');
    projectCol = column('Capstone Project');
    adviserCol = column('Adviser');
    instructorCol = column('Instructor');
    memberCol = column('Team Members');
    chairCol = column('Chair');
    panelCols = [
      column('Panel Member 1'),
      column('Panel Member 2'),
      column('Panel Member 3'),
    ].where((index) => index >= 0).toList();
    documenterCol = column('Documenter');
    roomCol = column('Room');
    dateCol = column('Date');
    stageCol = column('Stage');
    semesterCol = column('Semester');
    for (var i = 0; i < row.length; i++) {
      final header = row[i].trim();
      if (header.isEmpty ||
          recognizedColumns.contains(i) ||
          _isSequenceHeader(header)) {
        continue;
      }
      // Block the whole table, including blank cells under merged staff
      // assignments, so an unknown role cannot disappear from later rows.
      headerIssues.add(
        'Column "$header" (header row $sheetRow) is not recognized.'
        '${_headerSuggestion(header)} Rename the header or remove this column, then upload again.',
      );
    }
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
      applyHeader(rawRow, rowIndex + 1);
      continue;
    }

    // 2. Preamble metadata before first table header
    if (!headerFound) {
      final rowMeta = _readMetadataRow(
        rawRow,
        configuredStages: configuredStages,
        isPreamble: true,
      );
      if (rowMeta['stage'] != null && rowMeta['stage']!.isNotEmpty) {
        currentStage = rowMeta['stage']!;
        if (metadata['stage'] != null &&
            scheduleStageKey(metadata['stage']!) !=
                scheduleStageKey(currentStage)) {
          metadataIssues.add(
            'Conflicting stage headings at row ${rowIndex + 1}. Correct the source stage.',
          );
        }
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
    final rawTime = (timeCol >= 0 && timeCol < rawRow.length)
        ? rawRow[timeCol].trim()
        : '';
    final rawTeam = (teamCol >= 0 && teamCol < rawRow.length)
        ? rawRow[teamCol].trim()
        : '';
    final rawMember = (memberCol >= 0 && memberCol < rawRow.length)
        ? rawRow[memberCol].trim()
        : '';
    final reservation = RegExp(
      r'^(?:re[ -]?defen[cs]e|unassigned|reserved|vacant|tba)$',
      caseSensitive: false,
    ).hasMatch(rawTeam);
    final isBreak = RegExp(
      r'^(?:(?:lunch|snack|coffee|health)\s+)?break$',
      caseSensitive: false,
    ).hasMatch(rawTeam);
    if (reservation || isBreak) {
      ignoredRows.add({
        'row': rowIndex + 1,
        'label': rawTeam,
        'kind': isBreak ? 'break' : 'reservation',
      });
      fillDown.clear();
      continue;
    }
    final isDayBanner = RegExp(
      r'^DAY\s*\d+\b',
      caseSensitive: false,
    ).hasMatch(rawTime);
    final parsedTime = _parseTimeRange(rawTime);
    final hasValidTime = parsedTime.start.isNotEmpty;

    // Check for repeated header text in cells (e.g. literal "Team Name" or "Time")
    final normTeam = _normalizeHeader(rawTeam);
    final normTime = _normalizeHeader(rawTime);
    if (normTeam == 'teamname' ||
        normTeam == 'team' ||
        normTime == 'time' ||
        normTime == 'timeslot') {
      fillDown.clear();
      continue;
    }

    // If row has no valid defense time, no team name, and no student member,
    // it is a section metadata divider row (e.g. "6/19/2026" or "Room 301")
    if (isDayBanner ||
        (!hasValidTime && rawTeam.isEmpty && rawMember.isEmpty)) {
      final rowMeta = _readMetadataRow(
        rawRow,
        configuredStages: configuredStages,
        isPreamble: false,
      );
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

    final parseIssues = <String>[...headerIssues, ...metadataIssues];
    for (var i = 0; i < rawRow.length; i++) {
      final header = i < activeHeaders.length ? activeHeaders[i].trim() : '';
      if (recognizedColumns.contains(i) ||
          header.isNotEmpty ||
          rawRow[i].trim().isEmpty) {
        continue;
      }
      parseIssues.add(
        'Unnamed column ${i + 1} (header row $headerRow) contains data but is not recognized. '
        'Add a header or remove this column, then upload again.',
      );
    }

    // Check if this is a member continuation row for the current team
    if (rawTeam.isEmpty && rawMember.isNotEmpty) {
      if (grouped.isNotEmpty) {
        final lastGroup = grouped.values.last;
        if (!lastGroup.members.contains(rawMember)) {
          lastGroup.members.add(rawMember);
        }
        for (final issue in parseIssues) {
          if (!lastGroup.parseIssues.contains(issue)) {
            lastGroup.parseIssues.add(issue);
          }
        }
      }
      continue;
    }

    // If no team name and no valid time, skip
    if (rawTeam.isEmpty) {
      continue;
    }

    final time = read(timeCol);
    final teamName = read(teamCol, fill: false);
    final project = read(projectCol);
    final adviser = read(adviserCol, fill: true);
    final instructor = read(instructorCol, fill: true);
    final chair = read(chairCol, fill: false);
    final documenter = read(documenterCol, fill: true);
    final colRoom = read(roomCol, fill: true);
    final colDate = read(dateCol, fill: true);
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
      rowIndex.toString(),
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
        instructor: instructor,
        hasAdviserColumn: adviserCol >= 0,
        chair: chair,
        panelMembers: [
          for (final panelCol in panelCols) read(panelCol, fill: false),
        ].where((name) => name.isNotEmpty).toList(),
        documenter: documenter,
        room: effectiveRoom,
        date: effectiveDate,
        stage: effectiveStage,
        parseIssues: parseIssues,
      ),
    );
    for (final issue in parseIssues) {
      if (!group.parseIssues.contains(issue)) group.parseIssues.add(issue);
    }

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
          instructor: group.instructor,
          hasAdviserColumn: group.hasAdviserColumn,
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
          parseIssues: [
            ...group.parseIssues,
            if (parsedTime.start.isEmpty ||
                (group.time.contains(RegExp(r'[-–—]|\bto\b')) &&
                    parsedTime.end.isEmpty))
              'Time range is invalid. Correct the source time.',
            if (parsedTime.duration != null &&
                (parsedTime.duration! < 15 || parsedTime.duration! > 240))
              'Time range must be 15–240 minutes within the same day.',
          ],
        );
      })
      .toList(growable: false);

  final rawStage = (metadata['stage'] ?? currentStage).toLowerCase();
  final isRedefense =
      rawStage.contains('redef') ||
      rawStage.contains('redefense') ||
      rawStage.contains('re-defense');

  return ParsedScheduleImport(
    rows: rows,
    ignoredRows: ignoredRows,
    stage: metadata['stage'] ?? currentStage,
    date: metadata['date'] ?? currentDate,
    semester: metadata['semester'] ?? currentSemester,
    room: metadata['room'] ?? currentRoom,
    isRedefense: isRedefense,
  );
}

List<List<String>> _sheetMatrix(Sheet sheet) {
  // Never write through merged cells: the Excel package can alter merge ranges
  // during iteration. Horizontal banners remain a single structural anchor.
  final matrix = sheet.rows
      .map((row) => row.map(_excelCellText).toList())
      .toList();
  for (final span in List<String>.of(sheet.spannedItems)) {
    final parts = span.split(':');
    if (parts.length != 2) throw FormatException('Invalid merged range $span.');
    final start = CellIndex.indexByString(parts[0]);
    final end = CellIndex.indexByString(parts[1]);
    final value = matrix[start.rowIndex][start.columnIndex];
    if (start.columnIndex != end.columnIndex) {
      if (RegExp(
        r'^(?:re[ -]?defense|unassigned|reserved|vacant|tba)$',
        caseSensitive: false,
      ).hasMatch(value.trim())) {
        for (var r = start.rowIndex + 1; r <= end.rowIndex; r++) {
          while (matrix.length <= r) {
            matrix.add([]);
          }
          while (matrix[r].length <= start.columnIndex) {
            matrix[r].add('');
          }
          matrix[r][start.columnIndex] = value;
        }
      }
      continue;
    }
    String? role;
    for (var r = start.rowIndex; r >= 0; r--) {
      if (_isHeaderRow(matrix[r])) {
        role = start.columnIndex < matrix[r].length
            ? _headerRole(matrix[r][start.columnIndex])
            : null;
        break;
      }
    }
    // Team/time merges describe member continuation rows. Only staff/metadata
    // assignments may be expanded into following physical rows.
    if (!const [
      'Adviser',
      'Instructor',
      'Chair',
      'Panel Member 1',
      'Panel Member 2',
      'Panel Member 3',
      'Documenter',
      'Room',
      'Date',
    ].contains(role))
      continue;
    for (var r = start.rowIndex + 1; r <= end.rowIndex; r++) {
      while (matrix.length <= r) {
        matrix.add([]);
      }
      while (matrix[r].length <= start.columnIndex) {
        matrix[r].add('');
      }
      matrix[r][start.columnIndex] = value;
    }
  }
  return matrix;
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
  final roles = row.map(_headerRole).toSet();
  final hasTeam = roles.contains('Team Name');
  final hasSchedule =
      roles.contains('Time') ||
      roles.contains('Chair') ||
      roles.contains('Panel Member 1') ||
      roles.contains('Documenter');
  return hasTeam && hasSchedule;
}

bool _isDateString(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  if (RegExp(r'^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$').hasMatch(trimmed)) return true;
  final hasDigits = RegExp(r'\d').hasMatch(trimmed);
  final monthMatches = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
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

/// Only complete labels with a presentation wrapper are equivalent.
String scheduleStageKey(String text) => text
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceFirst(RegExp(r'^schedule\s*[:\-–—]?\s*'), '')
    .replaceFirst(RegExp(r'\s+schedule$'), '')
    .trim();

bool _stageHeading(String text, Iterable<String>? configured) {
  final key = scheduleStageKey(text);
  if (RegExp(r'^re[ -]?defense\b', caseSensitive: false).hasMatch(text)) {
    return true;
  }
  if ((configured ?? const <String>[]).any(
    (stage) => scheduleStageKey(stage) == key,
  )) {
    return true;
  }
  if (RegExp(
    r'\b(?:bsit|bscs|capstone project and research|prepared by|approved by)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    return false;
  }
  return RegExp(
    r'\b(?:schedule|defense|redefense|proposal|examination|colloquium)\b',
    caseSensitive: false,
  ).hasMatch(text);
}

Map<String, String> _readMetadataRow(
  List<String> row, {
  Iterable<String>? configuredStages,
  bool isPreamble = false,
}) {
  final result = <String, String>{};
  for (var i = 0; i < row.length; i++) {
    final rawCell = row[i].trim();
    final cell =
        i + 1 < row.length &&
            RegExp(r'^\d{4}$').hasMatch(row[i + 1].trim()) &&
            _isDateString(rawCell)
        ? '$rawCell, ${row[i + 1].trim()}'
        : rawCell;
    if (cell.isEmpty) continue;
    final explicit = RegExp(
      r'^(stage|defense stage|event|pit event|date|defense date|semester|term|room|venue)\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(cell);
    final key = _normalizeHeader(explicit?.group(1) ?? cell);
    final value =
        explicit?.group(2) ?? (i + 1 < row.length ? row[i + 1].trim() : '');
    if (value.isNotEmpty) {
      if (['stage', 'defensestage', 'event', 'pitevent'].contains(key)) {
        result['stage'] = value;
      }
      if (['date', 'defensedate', 'scheduleddate'].contains(key)) {
        result['date'] = value;
      }
      if (['room', 'venue', 'roomvenue'].contains(key)) result['room'] = value;
      if (['semester', 'term'].contains(key)) result['semester'] = value;
    }
    for (final segment in cell.split('|')) {
      final text = segment.trim();
      if (text.isEmpty) continue;
      if (_isRoomString(text)) {
        result['room'] ??= text;
        continue;
      }
      final range = RegExp(
        r'\b[A-Za-z]+\s+\d{1,2}\s*[-–—]\s*\d{1,2}',
        caseSensitive: false,
      ).hasMatch(text);
      final human = RegExp(
        r'\b(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{4}\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (!range && human != null) {
        result['date'] ??= human.group(0)!;
        continue;
      }
      if (RegExp(r'^\d{1,4}[-/]\d{1,2}[-/]\d{1,4}$').hasMatch(text)) {
        result['date'] ??= text;
        continue;
      }
      final semester = RegExp(
        r'\b(1st|2nd|Summer)\s*(?:Semester|sem)\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (semester != null) {
        result['semester'] ??= '${semester.group(1)} Semester';
        continue;
      }
      if (_stageHeading(text, configuredStages)) result['stage'] ??= text;
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
  final parts = text.split(
    RegExp(r'\s*(?:-|â€“|â€”|to)\s*', caseSensitive: false),
  );
  if (parts.isEmpty) {
    return const _TimeRange(start: '', end: '', duration: null);
  }
  var startStr = parts.first.trim();
  var endStr = parts.length > 1 ? parts[1].trim() : '';

  // If end has AM/PM but start doesn't, inherit meridiem intelligently
  final upperStart = startStr.toUpperCase();
  final upperEnd = endStr.toUpperCase();
  final hasStartMeridiem =
      upperStart.contains('AM') || upperStart.contains('PM');
  final hasEndMeridiem = upperEnd.contains('AM') || upperEnd.contains('PM');

  if (!hasStartMeridiem && hasEndMeridiem) {
    if (upperEnd.contains('PM')) {
      final startHourMatch = RegExp(r'^(\d{1,2})').firstMatch(startStr);
      final startHour = int.tryParse(startHourMatch?.group(1) ?? '') ?? 0;
      final endHourMatch = RegExp(r'^(\d{1,2})').firstMatch(endStr);
      final endHour = int.tryParse(endHourMatch?.group(1) ?? '') ?? 0;
      if (startHour == 12 ||
          startHour <= endHour && endHour != 12 ||
          endHour == 12 && startHour < 7) {
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

  if (meridiem.isNotEmpty && (hour < 1 || hour > 12)) return '';
  if (meridiem == 'PM' && hour < 12) {
    hour += 12;
  }
  if (meridiem == 'AM' && hour == 12) {
    hour = 0;
  }
  // In typical academic schedules, afternoon slots like "1:00" to "6:00" without meridiem are PM
  if (meridiem.isEmpty && !text.startsWith('0') && hour >= 1 && hour <= 6) {
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
  // Negative/zero intervals stay invalid; never wrap into the next day.
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
      rows.add(List<String>.from(currentRow));
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
    required this.instructor,
    required this.hasAdviserColumn,
    required this.chair,
    required this.panelMembers,
    required this.documenter,
    required this.room,
    required this.date,
    required this.stage,
    required this.parseIssues,
  });

  final int sheetRow;
  final String time;
  final String teamName;
  final String projectTitle;
  final String adviser;
  final String instructor;
  final bool hasAdviserColumn;
  final String chair;
  final List<String> panelMembers;
  final String documenter;
  final String room;
  final String date;
  final String stage;
  final List<String> parseIssues;
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
