const teamBulkImportHeader =
    'Team Name,Capstone Project,Section,Adviser,Team Members';

const teamBulkImportHeaderPit =
    'Team Name,PIT Project,Section,Instructor,Team Members';

const teamBulkImportLegacyHeader =
    'team_name,project_title,level,year_level,member_ids,leader_id,adviser_name';

String bulkImportHeaderFor({required bool isCapstoneAdmin}) =>
    isCapstoneAdmin ? teamBulkImportHeader : teamBulkImportHeaderPit;

String rowsToTeamCsv(
  List<Map<String, dynamic>> rows, {
  required bool isCapstoneAdmin,
}) {
  // Row-based CSV keeps unnamed teams explicit without empty separator rows.
  if (rows.any((row) => (row['team_name'] ?? '').toString().trim().isEmpty)) {
    const fields = [
      'team_name',
      'project_title',
      'level',
      'year_level',
      'section',
      'member_ids',
      'leader_id',
      'adviser_name',
      'instructor_name',
      'system_name',
      'project_manager',
      'group_key',
    ];
    return [
      fields.join(','),
      for (final row in rows)
        fields
            .map((field) {
              var value = row[field];
              if (field == 'leader_id' && (value ?? '').toString().isEmpty) {
                final members = row['member_ids'];
                value = members is List && members.isNotEmpty
                    ? members.first
                    : members?.toString().split('|').first;
              }
              if (field == 'adviser_name') value ??= row['adviser_id'];
              return _csvCell(value is List ? value.join('|') : value);
            })
            .join(','),
    ].join('\n');
  }
  final header = bulkImportHeaderFor(isCapstoneAdmin: isCapstoneAdmin);
  final buffer = StringBuffer('$header\n');
  for (final row in rows) {
    final teamName = row['team_name']?.toString() ?? '';
    final project = row['project_title']?.toString() ?? '';
    final section = row['section']?.toString() ?? '';
    final adviser =
        row['adviser_name']?.toString() ?? row['adviser_id']?.toString() ?? '';
    final instructor = row['instructor_name']?.toString() ?? '';
    final members = row['member_ids'];
    final membersList = members is List
        ? members
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : (members
                  ?.toString()
                  .split('|')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList() ??
              []);

    if (membersList.isEmpty) {
      if (isCapstoneAdmin) {
        buffer.writeln(
          [
            _csvCell(teamName),
            _csvCell(project),
            _csvCell(section),
            _csvCell(adviser),
            '',
          ].join(','),
        );
      } else {
        buffer.writeln(
          [
            _csvCell(teamName),
            _csvCell(project),
            _csvCell(section),
            _csvCell(instructor),
            '',
          ].join(','),
        );
      }
      continue;
    }

    for (var i = 0; i < membersList.length; i++) {
      final member = membersList[i];
      if (isCapstoneAdmin) {
        if (i == 0) {
          buffer.writeln(
            [
              _csvCell(teamName),
              _csvCell(project),
              _csvCell(section),
              _csvCell(adviser),
              _csvCell(member),
            ].join(','),
          );
        } else {
          buffer.writeln(['', '', '', '', _csvCell(member)].join(','));
        }
      } else {
        if (i == 0) {
          buffer.writeln(
            [
              _csvCell(teamName),
              _csvCell(project),
              _csvCell(section),
              _csvCell(instructor),
              _csvCell(member),
            ].join(','),
          );
        } else {
          buffer.writeln(['', '', '', '', _csvCell(member)].join(','));
        }
      }
    }
  }
  return buffer.toString().trim();
}

String _csvCell(dynamic value) {
  final text = value?.toString() ?? '';
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

class ParsedBulkCsvResult {
  final List<Map<String, dynamic>> rows;
  final List<String> csvColumns;
  final String? section;
  final String? systemName;
  final String? projectManager;

  const ParsedBulkCsvResult({
    required this.rows,
    required this.csvColumns,
    this.section,
    this.systemName,
    this.projectManager,
  });
}

List<String> _parseCsvLine(String line) {
  final delimiter = line.contains('\t') ? '\t' : ',';
  final result = <String>[];
  var currentCell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        currentCell.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == delimiter && !inQuotes) {
      result.add(currentCell.toString().trim());
      currentCell.clear();
    } else {
      currentCell.write(char);
    }
  }
  result.add(currentCell.toString().trim());
  return result;
}

String csvToTsv(String csv) {
  final lines = _csvRecords(csv);
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      buffer.writeln();
      continue;
    }
    final cells = _parseCsvLine(line);
    buffer.writeln(
      cells
          .map(
            (cell) => cell.contains(RegExp(r'[\t\n\r"]'))
                ? '"${cell.replaceAll('"', '""')}"'
                : cell,
          )
          .join('\t'),
    );
  }
  return buffer.toString().trimRight();
}

ParsedBulkCsvResult _parseMultiColumnTeamMatrix(
  List<List<String>> matrix,
  int headerRowIndex,
  List<int> teamNameIndices,
) {
  final headerRow = matrix[headerRowIndex];
  final parsedRows = <Map<String, dynamic>>[];
  final allSections = <String>{};
  String? firstSection;
  String? firstPm;

  for (var b = 0; b < teamNameIndices.length; b++) {
    final colStart = teamNameIndices[b];
    final colEnd = (b + 1 < teamNameIndices.length)
        ? teamNameIndices[b + 1]
        : headerRow.length;

    var blockSection = '';
    var blockPm = '';
    var blockAdviser = '';
    var blockInstructor = '';

    final pmRegex = RegExp(
      r'(?:PROJECT\s*MANAGER|PM)\s*:\s*(.+)',
      caseSensitive: false,
    );
    final adviserRegex = RegExp(r'ADVISER\s*:\s*(.+)', caseSensitive: false);

    for (var r = 0; r < headerRowIndex; r++) {
      final row = matrix[r];
      for (var c = colStart; c < colEnd && c < row.length; c++) {
        final text = row[c].trim();
        if (text.isEmpty) continue;

        if (blockPm.isEmpty) {
          final pmMatch = pmRegex.firstMatch(text);
          if (pmMatch != null) {
            blockPm = pmMatch.group(1)?.trim() ?? '';
          }
        }

        if (blockAdviser.isEmpty) {
          final advMatch = adviserRegex.firstMatch(text);
          if (advMatch != null) {
            blockAdviser = advMatch.group(1)?.trim() ?? '';
          }
        }
        if (blockInstructor.isEmpty) {
          final match = RegExp(
            r'INSTRUCTOR\s*:\s*(.+)',
            caseSensitive: false,
          ).firstMatch(text);
          if (match != null) blockInstructor = match.group(1)!.trim();
        }

        if (blockSection.isEmpty) {
          final bsitMatch = RegExp(
            r'\b(BSIT-[1-4][A-Za-z])\b',
            caseSensitive: false,
          ).firstMatch(text);
          if (bsitMatch != null) {
            blockSection = bsitMatch.group(1)!.toUpperCase();
          } else {
            final simpleMatch = RegExp(
              r'\b([1-4][A-Za-z])\b',
              caseSensitive: false,
            ).firstMatch(text);
            if (simpleMatch != null) {
              blockSection = simpleMatch.group(1)!.toUpperCase();
            }
          }
        }
      }
    }

    if (blockSection.isNotEmpty) {
      allSections.add(blockSection);
      firstSection ??= blockSection;
    }
    if (blockPm.isNotEmpty) {
      firstPm ??= blockPm;
    }

    final blockHeaders = <String>[];
    for (var c = colStart; c < colEnd && c < headerRow.length; c++) {
      blockHeaders.add(
        headerRow[c]
            .trim()
            .toLowerCase()
            .replaceAll('*', '')
            .replaceAll(':', '')
            .trim()
            .replaceFirst('\ufeff', ''),
      );
    }

    int findInBlock(bool Function(String) test) {
      for (var i = 0; i < blockHeaders.length; i++) {
        if (test(blockHeaders[i])) return i;
      }
      return -1;
    }

    final teamNameRelIdx = findInBlock(
      (h) => h == 'team name' || h == 'team_name',
    );
    final membersRelIdx = findInBlock(
      (h) =>
          h.contains('team members') ||
          h.contains('team_members') ||
          h.contains('members') ||
          h.contains('names') ||
          h.contains('member_ids'),
    );
    final projectRelIdx = findInBlock(
      (h) =>
          h.contains('capstone project') ||
          h.contains('pit project') ||
          h.contains('project') ||
          h.contains('module') ||
          h.contains('modules') ||
          h.contains('system'),
    );
    final adviserRelIdx = findInBlock((h) => h.contains('adviser'));
    final instructorRelIdx = findInBlock((h) => h.contains('instructor'));

    if (teamNameRelIdx == -1 || membersRelIdx == -1) continue;

    final teamNameCol = colStart + teamNameRelIdx;
    final membersCol = colStart + membersRelIdx;
    final projectCol = projectRelIdx != -1 ? colStart + projectRelIdx : -1;
    final adviserCol = adviserRelIdx != -1 ? colStart + adviserRelIdx : -1;
    final instructorCol = instructorRelIdx != -1
        ? colStart + instructorRelIdx
        : -1;

    String yearLevel = '';
    if (blockSection.isNotEmpty) {
      final firstChar = blockSection.replaceAll(RegExp(r'[^0-9]'), '');
      if (firstChar.startsWith('1')) {
        yearLevel = '1st Year';
      } else if (firstChar.startsWith('2')) {
        yearLevel = '2nd Year';
      } else if (firstChar.startsWith('3')) {
        yearLevel = '3rd Year';
      } else if (firstChar.startsWith('4')) {
        yearLevel = '4th Year';
      }
    }

    Map<String, dynamic>? currentTeam;

    for (var r = headerRowIndex + 1; r < matrix.length; r++) {
      final row = matrix[r];
      String cell(int col) =>
          (col >= 0 && col < row.length) ? row[col].trim() : '';

      final teamName = cell(teamNameCol);
      final member = cell(membersCol);
      final project = projectCol != -1 ? cell(projectCol) : '';
      if (teamName.isEmpty && project.isEmpty && member.isEmpty) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
        }
        currentTeam = null;
        continue;
      }
      final adviser = adviserCol != -1 ? cell(adviserCol) : '';
      final instructor = instructorCol != -1 ? cell(instructorCol) : '';

      final isSameTeam =
          currentTeam != null &&
          currentTeam['team_name']?.toString().toLowerCase().trim() ==
              teamName.toLowerCase().trim();

      if (currentTeam == null || (teamName.isNotEmpty && !isSameTeam)) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
        }
        currentTeam = {
          'group_key': 'matrix/col$colStart/row$r',
          'team_name': teamName,
          'project_title': project,
          'year_level': yearLevel,
          if (yearLevel.isNotEmpty)
            'level': yearLevel == '4th Year'
                ? '4th Year Capstone'
                : '$yearLevel PIT',
          'member_ids': <String>[if (member.isNotEmpty) member],
          'leader_id': member,
          if (blockSection.isNotEmpty) 'section': blockSection,
          if (blockPm.isNotEmpty) 'project_manager': blockPm,
          if (adviser.isNotEmpty)
            'adviser_name': adviser
          else if (blockAdviser.isNotEmpty)
            'adviser_name': blockAdviser,
          if (instructor.isNotEmpty)
            'instructor_name': instructor
          else if (blockInstructor.isNotEmpty)
            'instructor_name': blockInstructor,
        };
      } else if (member.isNotEmpty) {
        if (member.contains('|')) {
          final items = member
              .split('|')
              .map((m) => m.trim())
              .where((m) => m.isNotEmpty);
          for (final item in items) {
            if (!(currentTeam['member_ids'] as List<String>).contains(item)) {
              (currentTeam['member_ids'] as List<String>).add(item);
            }
          }
        } else {
          if (!(currentTeam['member_ids'] as List<String>).contains(member)) {
            (currentTeam['member_ids'] as List<String>).add(member);
          }
        }
      }
    }

    if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
      parsedRows.add(currentTeam);
    }
  }

  return ParsedBulkCsvResult(
    rows: parsedRows,
    csvColumns: const ['team_name', 'project_title', 'team_members', 'section'],
    section: allSections.isNotEmpty ? allSections.join(', ') : firstSection,
    projectManager: firstPm,
  );
}

ParsedBulkCsvResult parseTeamBulkCsv(
  String csv, {
  bool isSubBlock = false,
  String sourceKey = 'file',
}) {
  final rawLines = _csvRecords(csv);
  if (rawLines.isEmpty) {
    return const ParsedBulkCsvResult(rows: [], csvColumns: []);
  }

  var section = '';
  var systemName = '';
  var projectManager = '';

  final matrix = rawLines.map(_parseCsvLine).toList();

  // Check for multi-column / side-by-side section matrices (e.g. 2A/2B/2C or unified blueprint A-E and G-K)
  if (!isSubBlock) {
    final multiColIndices = <int>[];
    for (var r = 0; r < matrix.length && r < 10; r++) {
      for (var c = 0; c < matrix[r].length; c++) {
        final h = matrix[r][c]
            .trim()
            .toLowerCase()
            .replaceAll('*', '')
            .replaceAll(':', '')
            .trim()
            .replaceFirst('\ufeff', '');
        if (h == 'team name' || h == 'team_name') {
          if (!multiColIndices.contains(c)) {
            multiColIndices.add(c);
          }
        }
      }
    }
    multiColIndices.sort();

    if (multiColIndices.length > 1) {
      final blockResults = <ParsedBulkCsvResult>[];
      final maxCols = matrix
          .map((row) => row.length)
          .fold(0, (a, b) => a > b ? a : b);

      for (var b = 0; b < multiColIndices.length; b++) {
        final colStart = multiColIndices[b];
        final colEnd = (b + 1 < multiColIndices.length)
            ? multiColIndices[b + 1]
            : maxCols;

        final subMatrix = <List<String>>[];
        for (final row in matrix) {
          if (colStart >= row.length) {
            subMatrix.add([]);
            continue;
          }
          final end = colEnd < row.length ? colEnd : row.length;
          final slice = row.sublist(colStart, end).toList();
          while (slice.isNotEmpty && slice.last.trim().isEmpty) {
            slice.removeLast();
          }
          subMatrix.add(slice);
        }

        if (subMatrix.isNotEmpty) {
          final blockCsv = subMatrix
              .map((r) => r.map(_csvCell).join(','))
              .join('\n');
          final res = parseTeamBulkCsv(
            blockCsv,
            isSubBlock: true,
            sourceKey: '$sourceKey/table$b',
          );
          if (res.rows.isNotEmpty) {
            blockResults.add(res);
          }
        }
      }

      if (blockResults.isNotEmpty) {
        final allRows = <Map<String, dynamic>>[];
        final allSections = <String>{};
        String? combinedSystemName;
        String? combinedProjectManager;
        final allColumns = <String>[];

        for (final res in blockResults) {
          allRows.addAll(res.rows);
          if (res.section != null && res.section!.isNotEmpty) {
            for (final s in res.section!.split(',')) {
              final st = s.trim();
              if (st.isNotEmpty) allSections.add(st);
            }
          }
          if (res.systemName != null && res.systemName!.isNotEmpty) {
            combinedSystemName ??= res.systemName;
          }
          if (res.projectManager != null && res.projectManager!.isNotEmpty) {
            combinedProjectManager ??= res.projectManager;
          }
          if (allColumns.isEmpty && res.csvColumns.isNotEmpty) {
            allColumns.addAll(res.csvColumns);
          }
        }

        return ParsedBulkCsvResult(
          rows: allRows,
          csvColumns: allColumns.isNotEmpty
              ? allColumns
              : const ['team_name', 'project_title', 'team_members', 'section'],
          section: allSections.isNotEmpty ? allSections.join(', ') : null,
          systemName: combinedSystemName,
          projectManager: combinedProjectManager,
        );
      }
    }
  }

  var lineIndex = -1;

  for (var i = 0; i < matrix.length; i++) {
    final row = matrix[i];
    final headers = row
        .map(
          (cell) => cell
              .trim()
              .toLowerCase()
              .replaceAll('*', '')
              .replaceAll(':', '')
              .trim()
              .replaceFirst('\ufeff', ''),
        )
        .toSet();
    final hasTeamName =
        headers.contains('team name') || headers.contains('team_name');
    final hasMembers =
        headers.contains('team members') ||
        headers.contains('team_members') ||
        headers.contains('members') ||
        headers.contains('names') ||
        headers.contains('student name') ||
        headers.contains('student_name') ||
        headers.contains('student names') ||
        headers.contains('student') ||
        headers.contains('students') ||
        headers.contains('member_ids');
    if (hasTeamName && hasMembers) {
      lineIndex = i;
      break;
    }
  }

  if (lineIndex == -1) {
    return const ParsedBulkCsvResult(rows: [], csvColumns: []);
  }

  // Check for multi-column section matrix (e.g. 2A, 2B, 2C side-by-side)
  final teamNameIndices = <int>[];
  for (var c = 0; c < matrix[lineIndex].length; c++) {
    final h = matrix[lineIndex][c]
        .trim()
        .toLowerCase()
        .replaceAll('*', '')
        .replaceAll(':', '')
        .trim()
        .replaceFirst('\ufeff', '');
    if (h == 'team name' || h == 'team_name') {
      teamNameIndices.add(c);
    }
  }
  if (teamNameIndices.length > 1) {
    return _parseMultiColumnTeamMatrix(matrix, lineIndex, teamNameIndices);
  }

  String nextCell(List<String> row, int index) {
    for (var i = index + 1; i < row.length; i++) {
      final val = row[i].trim();
      if (val.isNotEmpty) return val;
    }
    return '';
  }

  var currentAdviser = '';
  var currentInstructor = '';

  for (var i = 0; i < lineIndex; i++) {
    final row = matrix[i];
    final rowText = row.join(' ').trim();
    final normalized = row
        .map(
          (cell) => cell
              .trim()
              .toLowerCase()
              .replaceAll('*', '')
              .replaceAll(':', '')
              .trim()
              .replaceFirst('\ufeff', ''),
        )
        .toList();

    void readMeta(List<String> labels, void Function(String val) setVal) {
      for (final label in labels) {
        final idx = normalized.indexOf(label);
        if (idx == -1) continue;
        final val = nextCell(row, idx);
        if (val.isNotEmpty) {
          setVal(val);
          break;
        }
      }
    }

    if (section.isEmpty) {
      readMeta(const [
        'section',
        'class section',
        'class_section',
      ], (val) => section = val);
      if (section.isEmpty) {
        final m = RegExp(
          r'(?:SECTION|CLASS\s*SECTION)\s*:\s*(.+)',
          caseSensitive: false,
        ).firstMatch(rowText);
        if (m != null) {
          section = m.group(1)!.trim();
        } else {
          final bsitMatch = RegExp(
            r'\b(BSIT-[1-4][A-Za-z])\b',
            caseSensitive: false,
          ).firstMatch(rowText);
          if (bsitMatch != null) {
            section = bsitMatch.group(1)!.toUpperCase();
          } else {
            final simpleMatch = RegExp(
              r'\b([1-4][A-Za-z])\b',
              caseSensitive: false,
            ).firstMatch(rowText);
            if (simpleMatch != null) {
              section = simpleMatch.group(1)!.toUpperCase();
            }
          }
        }
      }
    }
    if (systemName.isEmpty) {
      readMeta(const [
        'system name',
        'system_name',
        'system',
        'subject',
      ], (val) => systemName = val);
      if (systemName.isEmpty) {
        final m = RegExp(
          r'(?:SYSTEM\s*NAME|SYSTEM)\s*:\s*(.+)',
          caseSensitive: false,
        ).firstMatch(rowText);
        if (m != null) systemName = m.group(1)!.trim();
      }
    }
    if (projectManager.isEmpty) {
      readMeta(const [
        'project manager',
        'project_manager',
        'pm',
      ], (val) => projectManager = val);
      if (projectManager.isEmpty) {
        final m = RegExp(
          r'(?:PROJECT\s*MANAGER|PM)\s*:\s*(.+)',
          caseSensitive: false,
        ).firstMatch(rowText);
        if (m != null) projectManager = m.group(1)!.trim();
      }
    }
    if (currentAdviser.isEmpty) {
      readMeta(const ['adviser'], (val) => currentAdviser = val);
      if (currentAdviser.isEmpty) {
        final m = RegExp(
          r'ADVISER\s*:\s*(.+)',
          caseSensitive: false,
        ).firstMatch(rowText);
        if (m != null) currentAdviser = m.group(1)!.trim();
      }
    }
    if (currentInstructor.isEmpty) {
      readMeta(const [
        'instructor',
        'instructor_name',
      ], (val) => currentInstructor = val);
      if (currentInstructor.isEmpty) {
        final m = RegExp(
          r'INSTRUCTOR\s*:\s*(.+)',
          caseSensitive: false,
        ).firstMatch(rowText);
        if (m != null) currentInstructor = m.group(1)!.trim();
      }
    }
  }

  final lines = rawLines.skip(lineIndex).toList();

  if (lines.isEmpty) {
    return ParsedBulkCsvResult(
      rows: const [],
      csvColumns: const [],
      section: section.isNotEmpty ? section : null,
      systemName: systemName.isNotEmpty ? systemName : null,
      projectManager: projectManager.isNotEmpty ? projectManager : null,
    );
  }

  final headers = _parseCsvLine(lines.first)
      .map(
        (header) => header
            .trim()
            .toLowerCase()
            .replaceAll('*', '')
            .replaceAll(':', '')
            .trim()
            .replaceFirst('\ufeff', ''),
      )
      .toList();

  final isClientFormat =
      (headers.contains('team name') || headers.contains('team_name')) &&
      (headers.contains('team members') ||
          headers.contains('team_members') ||
          headers.contains('members') ||
          headers.contains('names') ||
          headers.contains('student name') ||
          headers.contains('student_name') ||
          headers.contains('student names') ||
          headers.contains('student') ||
          headers.contains('students'));

  if (isClientFormat) {
    final groupKeyIdx = headers.indexOf('group_key');
    final teamNameIdx = headers.contains('team name')
        ? headers.indexOf('team name')
        : headers.indexOf('team_name');

    var projectIdx = headers.indexWhere(
      (h) =>
          h == 'capstone project' ||
          h == 'pit project' ||
          h == 'project' ||
          h == 'project title' ||
          h == 'project_title' ||
          h == 'module' ||
          h == 'modules' ||
          h == 'module assigned' ||
          h == 'assigned module' ||
          h == 'project / module' ||
          h == 'project/module' ||
          h == 'project / system' ||
          h == 'system / module' ||
          h == 'system/module' ||
          h == 'system' ||
          (!h.contains('manager') &&
              (h.contains('project') || h.contains('module'))),
    );

    var adviserIdx = headers.indexOf('adviser');
    if (adviserIdx == -1) adviserIdx = headers.indexOf('adviser 1');
    if (adviserIdx == -1) adviserIdx = headers.indexOf('adviser_1');
    if (adviserIdx == -1) adviserIdx = headers.indexOf('adviser 2');
    if (adviserIdx == -1) {
      adviserIdx = headers.indexWhere((h) => h.contains('adviser'));
    }
    final instructorIdx = headers.indexWhere((h) => h.contains('instructor'));

    var sectionIdx = headers.indexOf('section');
    if (sectionIdx == -1) sectionIdx = headers.indexOf('class section');
    if (sectionIdx == -1) sectionIdx = headers.indexOf('class_section');

    var pmIdx = headers.indexOf('project manager');
    if (pmIdx == -1) pmIdx = headers.indexOf('project_manager');
    if (pmIdx == -1) pmIdx = headers.indexOf('pm');

    var systemColIdx = headers.indexOf('system name');
    if (systemColIdx == -1) systemColIdx = headers.indexOf('system_name');
    if (systemColIdx == -1) systemColIdx = headers.indexOf('system');

    var membersIdx = headers.indexOf('team members');
    if (membersIdx == -1) membersIdx = headers.indexOf('team_members');
    if (membersIdx == -1) membersIdx = headers.indexOf('members');
    if (membersIdx == -1) membersIdx = headers.indexOf('names');
    if (membersIdx == -1) membersIdx = headers.indexOf('student name');
    if (membersIdx == -1) membersIdx = headers.indexOf('student_name');
    if (membersIdx == -1) membersIdx = headers.indexOf('student names');
    if (membersIdx == -1) membersIdx = headers.indexOf('student');
    if (membersIdx == -1) membersIdx = headers.indexOf('students');

    if (teamNameIdx == -1 || membersIdx == -1) {
      return ParsedBulkCsvResult(
        rows: const [],
        csvColumns: headers,
        section: section.isNotEmpty ? section : null,
        systemName: systemName.isNotEmpty ? systemName : null,
        projectManager: projectManager.isNotEmpty ? projectManager : null,
      );
    }

    final parsedRows = <Map<String, dynamic>>[];
    final allSections = <String>{};
    if (section.isNotEmpty) allSections.add(section);
    Map<String, dynamic>? currentTeam;

    var sourceRow = lineIndex;
    for (final line in lines.skip(1)) {
      sourceRow++;

      final columns = _parseCsvLine(line);
      final firstCol = columns.isNotEmpty ? columns[0].trim() : '';
      final fullRowText = columns.join(' ').trim();

      // Check for intermediate SECTION: divider header or Section, <Name>
      final sectionHeaderMatch = RegExp(
        r'^(?:SECTION|CLASS\s*SECTION)\s*:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(firstCol.isNotEmpty ? firstCol : fullRowText);
      if (sectionHeaderMatch != null) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        section = sectionHeaderMatch.group(1)!.trim();
        currentInstructor = '';
        allSections.add(section);
        continue;
      }

      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'section' ||
              firstCol.toLowerCase() == 'class section')) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        section = columns[1].trim();
        currentInstructor = '';
        allSections.add(section);
        continue;
      }

      // Check for intermediate System Name or Project Manager
      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'system name' ||
              firstCol.toLowerCase() == 'system_name' ||
              firstCol.toLowerCase() == 'system')) {
        systemName = columns[1].trim();
        continue;
      }
      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'project manager' ||
              firstCol.toLowerCase() == 'project_manager' ||
              firstCol.toLowerCase() == 'pm')) {
        projectManager = columns[1].trim();
        continue;
      }

      // Keep the faculty role from the source label, including divider rows.
      final adviserHeaderMatch = RegExp(
        r'^(ADVISER|INSTRUCTOR)\s*:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(firstCol.isNotEmpty ? firstCol : fullRowText);
      if (adviserHeaderMatch != null) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        if (adviserHeaderMatch.group(1)!.toLowerCase() == 'instructor') {
          currentInstructor = adviserHeaderMatch.group(2)!.trim();
        } else {
          currentAdviser = adviserHeaderMatch.group(2)!.trim();
        }
        continue;
      }

      // Check for ADVISER, <Name> format
      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'adviser' ||
              firstCol.toLowerCase() == 'instructor')) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        if (firstCol.toLowerCase() == 'instructor') {
          currentInstructor = columns[1].trim();
        } else {
          currentAdviser = columns[1].trim();
        }
        continue;
      }

      // Check if this line is a repeated table header (e.g. "Team Name,Names,Modules")
      final lineNormalized = columns
          .map((c) => c.trim().toLowerCase())
          .toList();
      if (lineNormalized.contains('team name') ||
          lineNormalized.contains('team_name')) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
        }
        currentTeam = null;
        continue;
      }

      String read(int idx) =>
          (idx >= 0 && idx < columns.length) ? columns[idx] : '';

      final teamName = read(teamNameIdx);
      final project = read(projectIdx);
      final member = read(membersIdx);
      // Evaluate before faculty/section carry-forward. Merged class columns
      // do not turn an otherwise empty group separator into a member row.
      if (teamName.isEmpty && project.isEmpty && member.isEmpty) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
        }
        currentTeam = null;
        continue;
      }
      final rowAdviser = adviserIdx >= 0 ? read(adviserIdx) : '';
      if (rowAdviser.isNotEmpty) {
        currentAdviser = rowAdviser;
      }
      final effectiveAdviser = rowAdviser.isNotEmpty
          ? rowAdviser
          : currentAdviser;
      final rowInstructor = read(instructorIdx);
      if (rowInstructor.isNotEmpty) currentInstructor = rowInstructor;
      final rowSection = read(sectionIdx);
      if (rowSection.isNotEmpty) {
        if (section.isNotEmpty &&
            rowSection.toLowerCase() != section.toLowerCase()) {
          currentInstructor = rowInstructor;
        }
        section = rowSection;
        allSections.add(section);
      }
      final effectiveSection = rowSection.isNotEmpty ? rowSection : section;
      final effectiveInstructor = rowInstructor.isNotEmpty
          ? rowInstructor
          : currentInstructor;

      final rowPm = pmIdx >= 0 ? read(pmIdx) : '';
      if (rowPm.isNotEmpty) {
        projectManager = rowPm;
      }
      final effectivePm = rowPm.isNotEmpty ? rowPm : projectManager;

      final rowSys = systemColIdx >= 0 ? read(systemColIdx) : '';
      if (rowSys.isNotEmpty) {
        systemName = rowSys;
      }
      final effectiveSys = rowSys.isNotEmpty ? rowSys : systemName;

      final isSameTeam =
          currentTeam != null &&
          currentTeam['team_name']?.toString().toLowerCase().trim() ==
              teamName.toLowerCase().trim();

      final sourceGroup = read(groupKeyIdx);
      final groupKey = sourceGroup.isEmpty ? '' : '$sourceKey/$sourceGroup';
      final startsGroup =
          groupKey.isNotEmpty && currentTeam?['group_key'] != groupKey;
      if (currentTeam == null ||
          startsGroup ||
          (teamName.isNotEmpty && !isSameTeam)) {
        if (currentTeam != null &&
            (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
        }
        String inferredYear = '';
        if (effectiveSection.isNotEmpty) {
          final digits = effectiveSection.replaceAll(RegExp(r'[^0-9]'), '');
          if (digits.startsWith('1')) {
            inferredYear = '1st Year';
          } else if (digits.startsWith('2')) {
            inferredYear = '2nd Year';
          } else if (digits.startsWith('3')) {
            inferredYear = '3rd Year';
          } else if (digits.startsWith('4')) {
            inferredYear = '4th Year';
          }
        }
        currentTeam = {
          'group_key': groupKey.isEmpty ? '$sourceKey/row$sourceRow' : groupKey,
          'team_name': teamName,
          'project_title': project,
          'year_level': inferredYear,
          if (inferredYear.isNotEmpty)
            'level': inferredYear == '4th Year'
                ? '4th Year Capstone'
                : '$inferredYear PIT',
          'member_ids': <String>[if (member.isNotEmpty) member],
          'leader_id': member,
          if (effectiveAdviser.isNotEmpty) 'adviser_name': effectiveAdviser,
          if (effectiveInstructor.isNotEmpty)
            'instructor_name': effectiveInstructor,
          if (effectiveSection.isNotEmpty) 'section': effectiveSection,
          if (effectiveSys.isNotEmpty) 'system_name': effectiveSys,
          if (effectivePm.isNotEmpty) 'project_manager': effectivePm,
        };
      } else {
        if (member.isNotEmpty) {
          if (!(currentTeam['member_ids'] as List<String>).contains(member)) {
            (currentTeam['member_ids'] as List<String>).add(member);
          }
        }
      }
    }
    if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
      parsedRows.add(currentTeam);
    }
    return ParsedBulkCsvResult(
      rows: parsedRows,
      csvColumns: headers,
      section: allSections.isNotEmpty
          ? allSections.join(', ')
          : (section.isNotEmpty ? section : null),
      systemName: systemName.isNotEmpty ? systemName : null,
      projectManager: projectManager.isNotEmpty ? projectManager : null,
    );
  }

  if (lines.length < 2) {
    return ParsedBulkCsvResult(
      rows: const [],
      csvColumns: headers,
      section: section.isNotEmpty ? section : null,
      systemName: systemName.isNotEmpty ? systemName : null,
      projectManager: projectManager.isNotEmpty ? projectManager : null,
    );
  }

  int index(String name) => headers.indexOf(name);
  final teamNameIndex = index('team_name');
  final projectTitleIndex = index('project_title');
  final levelIndex = index('level');
  final yearLevelIndex = index('year_level');
  final memberIdsIndex = index('member_ids');
  final leaderIdIndex = index('leader_id');
  var adviserNameIndex = index('adviser_name');
  if (adviserNameIndex == -1) {
    adviserNameIndex = index('adviser_id');
  }
  final instructorNameIndex = headers.indexWhere(
    (h) => h == 'instructor_name' || h == 'instructor',
  );
  var sectionIndex = index('section');
  if (sectionIndex == -1) sectionIndex = index('class_section');
  if (sectionIndex == -1) sectionIndex = index('class section');

  if ([teamNameIndex, memberIdsIndex, leaderIdIndex].contains(-1)) {
    return ParsedBulkCsvResult(
      rows: const [],
      csvColumns: headers,
      section: section.isNotEmpty ? section : null,
      systemName: systemName.isNotEmpty ? systemName : null,
      projectManager: projectManager.isNotEmpty ? projectManager : null,
    );
  }

  final rows = lines
      .skip(1)
      .map((line) {
        final columns = _parseCsvLine(line);
        String read(int columnIndex) =>
            columnIndex >= 0 && columnIndex < columns.length
            ? columns[columnIndex]
            : '';

        final level = read(levelIndex);
        final yearLevel = read(yearLevelIndex);
        final rowSec = read(sectionIndex);
        final effectiveSec = rowSec.isNotEmpty ? rowSec : section;

        return {
          if (index('group_key') >= 0) 'group_key': read(index('group_key')),
          'team_name': read(teamNameIndex),
          'project_title': read(projectTitleIndex),
          if (level.isNotEmpty) 'level': level,
          'year_level': yearLevel.isNotEmpty
              ? yearLevel
              : _yearFromLevel(level),
          'member_ids': read(memberIdsIndex)
              .split('|')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
          'leader_id': read(leaderIdIndex),
          if (adviserNameIndex >= 0) 'adviser_name': read(adviserNameIndex),
          if (instructorNameIndex >= 0)
            'instructor_name': read(instructorNameIndex),
          if (instructorNameIndex < 0 && currentInstructor.isNotEmpty)
            'instructor_name': currentInstructor,
          if (effectiveSec.isNotEmpty) 'section': effectiveSec,
          if (index('system_name') >= 0)
            'system_name': read(index('system_name')),
          if (index('project_manager') >= 0)
            'project_manager': read(index('project_manager')),
        };
      })
      .where((row) => (row['member_ids'] as List).isNotEmpty)
      .toList();
  for (var i = 0; i < rows.length; i++) {
    if ((rows[i]['group_key'] ?? '').toString().isEmpty) {
      rows[i]['group_key'] = '$sourceKey/legacy$i';
    }
  }
  return ParsedBulkCsvResult(
    rows: rows,
    csvColumns: headers,
    section: section.isNotEmpty ? section : null,
    systemName: systemName.isNotEmpty ? systemName : null,
    projectManager: projectManager.isNotEmpty ? projectManager : null,
  );
}

String _yearFromLevel(String level) {
  if (level.startsWith('1st Year')) return '1st Year';
  if (level.startsWith('2nd Year')) return '2nd Year';
  if (level.startsWith('3rd Year')) return '3rd Year';
  if (level.startsWith('4th Year')) return '4th Year';
  return '';
}

void applyDerivedLevelToRow(
  Map<String, dynamic> row, {
  required bool isCapstoneAdmin,
  String? pitLeadYear,
}) {
  if (isCapstoneAdmin) {
    return;
  }
  final existingYear = (row['year_level'] ?? '').toString().trim();
  final targetYear = existingYear.isNotEmpty
      ? existingYear
      : (pitLeadYear ?? '');
  if (targetYear.isNotEmpty) {
    row['year_level'] = targetYear;
    row['level'] = '$targetYear PIT';
  }
}

ParsedBulkCsvResult parseTeamBulkCsvWithContext(
  String csv, {
  required bool isCapstoneAdmin,
  String? pitLeadYear,
}) {
  final result = parseTeamBulkCsv(csv);
  for (final row in result.rows) {
    applyDerivedLevelToRow(
      row,
      isCapstoneAdmin: isCapstoneAdmin,
      pitLeadYear: pitLeadYear,
    );
  }
  return result;
}

const teamSampleYearLevels = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

/// One demo team per year level (4 members each). Matches `sample_file/demo_teams_*`.
const Map<String, String> sampleTeamCsvByYear = {
  '1st Year':
      'Team Name,PIT Project,Team Members\n'
      'Team NovaPath,Campus Wayfinder App,James Rivera\n'
      ',,Sofia Lim\n'
      ',,Miguel Torres\n'
      ',,Chloe Nguyen\n'
      'Team ByteForce,Smart Locker System,Lucas Alcantara\n'
      ',,Elena Santos\n'
      ',,Mateo Garcia\n'
      ',,Olivia Diaz\n'
      'Team NexGen,Interactive Map,Gabriel Cruz\n'
      ',,Isabella Reyes\n'
      ',,Daniel Lee\n'
      ',,Ava Martinez\n',
  '2nd Year':
      'Team Name,PIT Project,Team Members\n'
      'Team Quantum,Automated Grade Calculator,Darren Kim\n'
      ',,Isabel Cruz\n'
      ',,Noah Ramos\n'
      ',,Leah Fernandez\n'
      'Team ByteForce,Library Seat Reservation,Nathan Lopez\n'
      ',,Mia Valenzuela\n'
      ',,Leo Mendoza\n'
      ',,Chloe Castillo\n'
      'Team NexGen,Student Health Tracker,Oliver Aquino\n'
      ',,Emma Corpuz\n'
      ',,Ethan Rivera\n'
      ',,Sophia Sy\n',
  '3rd Year':
      'Team Name,PIT Project,Team Members\n'
      'Team CodeLearners,Smart Campus Navigator,Carlos Reyes\n'
      ',,Maria Santos\n'
      ',,Juan Dela Cruz\n'
      ',,Ana Mendoza\n'
      'Team ByteForce,IoT-Based Smart Classroom Monitor,Jose Garcia\n'
      ',,Liza Torres\n'
      ',,Marco Villanueva\n'
      ',,Nina Flores\n'
      'Team NexGen,Online Complaint Management System,Diego Ramos\n'
      ',,Patricia Cruz\n'
      ',,Ryan Bautista\n'
      ',,Sophia Aquino\n',
  '4th Year':
      '$teamBulkImportHeader\n'
      'Team SkyLedger,Alumni Career Tracker,BSIT 4A,Prof. Alex Santos,Marcus Villar\n'
      ',,,,Patricia Ong\n'
      ',,,,Ethan Salazar\n'
      ',,,,Zoe Castillo\n'
      'Team ByteForce,AI-Powered Attendance System,BSIT 4A,Prof. Alex Santos,Ryan Torres\n'
      ',,,,Nina Villanueva\n'
      ',,,,Diego Garcia\n'
      ',,,,Patricia Ramos\n'
      'Team NexGen,Campus Lost and Found Portal,BSIT 4A,Prof. Alex Santos,Carlos Bautista\n'
      ',,,,Sophia Santos\n'
      ',,,,Miguel Cruz\n'
      ',,,,Isabella Alcantara\n',
};

String sampleTeamCsvForYear(String yearLevel, {required bool isCapstoneAdmin}) {
  final source =
      sampleTeamCsvByYear[yearLevel] ?? sampleTeamCsvByYear['3rd Year']!;
  if (isCapstoneAdmin) {
    return source.trim();
  }
  final result = parseTeamBulkCsv(source);
  return rowsToTeamCsv(result.rows, isCapstoneAdmin: false);
}

String sampleTeamCsvFilenameForYear(String yearLevel) {
  final slug = yearLevel
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');
  return 'defensys-team-import-sample-$slug.csv';
}

final sampleTeamCsvTemplateCapstone = sampleTeamCsvByYear['3rd Year']!.trim();

const sampleTeamCsvTemplatePit =
    'Team Name,PIT Project,Team Members\n'
    'Team CodeLearners,Smart Campus Navigator,Carlos Reyes\n'
    ',,Maria Santos\n'
    ',,Juan Dela Cruz\n'
    ',,Ana Mendoza\n';

List<Map<String, dynamic>> trimRowsAfterImport({
  required List<Map<String, dynamic>> rows,
  required List<dynamic> importedRows,
  List<int>? submittedRowNumbers,
}) {
  // The API numbers the submitted subset, which may omit staged invalid rows.
  final remove = <int>{
    for (final item in importedRows)
      if (int.tryParse(item.toString()) case final int number)
        if (submittedRowNumbers == null)
          number
        else if (number > 0 && number <= submittedRowNumbers.length)
          submittedRowNumbers[number - 1],
  };

  if (remove.isEmpty) {
    return rows;
  }

  final kept = <Map<String, dynamic>>[];
  for (var index = 0; index < rows.length; index++) {
    final rowNumber = index + 1;
    if (!remove.contains(rowNumber)) {
      kept.add(Map<String, dynamic>.from(rows[index]));
    }
  }
  return kept;
}

// Keep quoted multiline project titles in one logical row, including when an
// XLSX cell is converted to CSV for the existing roster parser.
List<String> _csvRecords(String csv) {
  final records = <String>[];
  var record = StringBuffer();
  var quoted = false;
  for (var index = 0; index < csv.length; index++) {
    final char = csv[index];
    if (char == '"') {
      record.write(char);
      if (quoted && index + 1 < csv.length && csv[index + 1] == '"') {
        record.write(csv[++index]);
      } else {
        quoted = !quoted;
      }
    } else if ((char == '\n' || char == '\r') && !quoted) {
      records.add(record.toString());
      record = StringBuffer();
      if (char == '\r' && index + 1 < csv.length && csv[index + 1] == '\n') {
        index++;
      }
    } else {
      record.write(char);
    }
  }
  records.add(record.toString());
  return records;
}
