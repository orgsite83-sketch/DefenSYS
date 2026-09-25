const teamBulkImportHeader =
    'Team Name,Capstone Project,Adviser,Team Members';

const teamBulkImportHeaderPit =
    'Team Name,PIT Project,Team Members';

const teamBulkImportLegacyHeader =
    'team_name,project_title,level,year_level,member_ids,leader_id,adviser_name';

String bulkImportHeaderFor({required bool isCapstoneAdmin}) =>
    isCapstoneAdmin ? teamBulkImportHeader : teamBulkImportHeaderPit;

String rowsToTeamCsv(
  List<Map<String, dynamic>> rows, {
  required bool isCapstoneAdmin,
}) {
  final header = bulkImportHeaderFor(isCapstoneAdmin: isCapstoneAdmin);
  final buffer = StringBuffer('$header\n');
  for (final row in rows) {
    final teamName = row['team_name']?.toString() ?? '';
    final project = row['project_title']?.toString() ?? '';
    final adviser = row['adviser_name']?.toString() ?? row['adviser_id']?.toString() ?? '';
    final members = row['member_ids'];
    final membersList = members is List
        ? members.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList()
        : (members?.toString().split('|').map((item) => item.trim()).where((item) => item.isNotEmpty).toList() ?? []);

    if (membersList.isEmpty) {
      if (isCapstoneAdmin) {
        buffer.writeln([
          _csvCell(teamName),
          _csvCell(project),
          _csvCell(adviser),
          '',
        ].join(','));
      } else {
        buffer.writeln([
          _csvCell(teamName),
          _csvCell(project),
          '',
        ].join(','));
      }
      continue;
    }

    for (var i = 0; i < membersList.length; i++) {
      final member = membersList[i];
      if (isCapstoneAdmin) {
        if (i == 0) {
          buffer.writeln([
            _csvCell(teamName),
            _csvCell(project),
            _csvCell(adviser),
            _csvCell(member),
          ].join(','));
        } else {
          buffer.writeln([
            '',
            '',
            '',
            _csvCell(member),
          ].join(','));
        }
      } else {
        if (i == 0) {
          buffer.writeln([
            _csvCell(teamName),
            _csvCell(project),
            _csvCell(member),
          ].join(','));
        } else {
          buffer.writeln([
            '',
            '',
            _csvCell(member),
          ].join(','));
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
  final lines = csv.split(RegExp(r'\r?\n'));
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      buffer.writeln();
      continue;
    }
    final cells = _parseCsvLine(line);
    buffer.writeln(cells.join('\t'));
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

    final pmRegex = RegExp(
      r'(?:PROJECT\s*MANAGER|PM)\s*:\s*(.+)',
      caseSensitive: false,
    );
    final adviserRegex = RegExp(
      r'(?:ADVISER|INSTRUCTOR)\s*:\s*(.+)',
      caseSensitive: false,
    );

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

        if (blockSection.isEmpty) {
          final bsitMatch = RegExp(r'\b(BSIT-[1-4][A-Za-z])\b', caseSensitive: false).firstMatch(text);
          if (bsitMatch != null) {
            blockSection = bsitMatch.group(1)!.toUpperCase();
          } else {
            final simpleMatch = RegExp(r'\b([1-4][A-Za-z])\b', caseSensitive: false).firstMatch(text);
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
      blockHeaders.add(headerRow[c].trim().toLowerCase().replaceFirst('\ufeff', ''));
    }

    int findInBlock(bool Function(String) test) {
      for (var i = 0; i < blockHeaders.length; i++) {
        if (test(blockHeaders[i])) return i;
      }
      return -1;
    }

    final teamNameRelIdx = findInBlock((h) => h == 'team name' || h == 'team_name');
    final membersRelIdx = findInBlock((h) =>
        h.contains('team members') ||
        h.contains('team_members') ||
        h.contains('members') ||
        h.contains('names') ||
        h.contains('member_ids'));
    final projectRelIdx = findInBlock((h) =>
        h.contains('capstone project') ||
        h.contains('pit project') ||
        h.contains('project') ||
        h.contains('module') ||
        h.contains('modules') ||
        h.contains('system'));
    final adviserRelIdx = findInBlock((h) => h.contains('adviser'));

    if (teamNameRelIdx == -1 || membersRelIdx == -1) continue;

    final teamNameCol = colStart + teamNameRelIdx;
    final membersCol = colStart + membersRelIdx;
    final projectCol = projectRelIdx != -1 ? colStart + projectRelIdx : -1;
    final adviserCol = adviserRelIdx != -1 ? colStart + adviserRelIdx : -1;

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
      String cell(int col) => (col >= 0 && col < row.length) ? row[col].trim() : '';

      final teamName = cell(teamNameCol);
      final member = cell(membersCol);
      final project = projectCol != -1 ? cell(projectCol) : '';
      final adviser = adviserCol != -1 ? cell(adviserCol) : '';

      if (teamName.isNotEmpty) {
        if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
        }
        currentTeam = {
          'team_name': teamName,
          'project_title': project.isNotEmpty ? project : teamName,
          'year_level': yearLevel,
          if (yearLevel.isNotEmpty) 'level': '$yearLevel PIT',
          'member_ids': <String>[if (member.isNotEmpty) member],
          'leader_id': member,
          if (blockSection.isNotEmpty) 'section': blockSection,
          if (blockPm.isNotEmpty) 'project_manager': blockPm,
          if (adviser.isNotEmpty)
            'adviser_name': adviser
          else if (blockAdviser.isNotEmpty)
            'adviser_name': blockAdviser,
        };
      } else if (member.isNotEmpty && currentTeam != null) {
        if (member.contains('|')) {
          final items = member.split('|').map((m) => m.trim()).where((m) => m.isNotEmpty);
          (currentTeam['member_ids'] as List<String>).addAll(items);
        } else {
          (currentTeam['member_ids'] as List<String>).add(member);
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

ParsedBulkCsvResult parseTeamBulkCsv(String csv) {
  final rawLines = csv
      .split(RegExp(r'\r?\n'))
      .map((line) => line.replaceAll('\r', ''))
      .toList();
  if (rawLines.isEmpty) {
    return const ParsedBulkCsvResult(rows: [], csvColumns: []);
  }

  var section = '';
  var systemName = '';
  var projectManager = '';

  final matrix = rawLines.map(_parseCsvLine).toList();
  var lineIndex = -1;

  for (var i = 0; i < matrix.length; i++) {
    final row = matrix[i];
    final headers = row
        .map((cell) => cell.trim().toLowerCase().replaceFirst('\ufeff', ''))
        .toSet();
    final hasTeamName = headers.contains('team name') || headers.contains('team_name');
    final hasMembers = headers.contains('team members') ||
        headers.contains('team_members') ||
        headers.contains('members') ||
        headers.contains('names') ||
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
    final h = matrix[lineIndex][c].trim().toLowerCase().replaceFirst('\ufeff', '');
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

  for (var i = 0; i < lineIndex; i++) {
    final row = matrix[i];
    final rowText = row.join(' ').trim();
    final normalized = row
        .map((cell) => cell.trim().toLowerCase().replaceFirst('\ufeff', ''))
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
      readMeta(const ['section', 'class section', 'class_section'], (val) => section = val);
      if (section.isEmpty) {
        final m = RegExp(r'(?:SECTION|CLASS\s*SECTION)\s*:\s*(.+)', caseSensitive: false).firstMatch(rowText);
        if (m != null) section = m.group(1)!.trim();
      }
    }
    if (systemName.isEmpty) {
      readMeta(const ['system name', 'system_name', 'system', 'subject'], (val) => systemName = val);
      if (systemName.isEmpty) {
        final m = RegExp(r'(?:SYSTEM\s*NAME|SYSTEM)\s*:\s*(.+)', caseSensitive: false).firstMatch(rowText);
        if (m != null) systemName = m.group(1)!.trim();
      }
    }
    if (projectManager.isEmpty) {
      readMeta(const ['project manager', 'project_manager', 'pm'], (val) => projectManager = val);
      if (projectManager.isEmpty) {
        final m = RegExp(r'(?:PROJECT\s*MANAGER|PM)\s*:\s*(.+)', caseSensitive: false).firstMatch(rowText);
        if (m != null) projectManager = m.group(1)!.trim();
      }
    }
    if (currentAdviser.isEmpty) {
      readMeta(const ['adviser', 'instructor'], (val) => currentAdviser = val);
      if (currentAdviser.isEmpty) {
        final m = RegExp(r'(?:ADVISER|INSTRUCTOR)\s*:\s*(.+)', caseSensitive: false).firstMatch(rowText);
        if (m != null) currentAdviser = m.group(1)!.trim();
      }
    }
  }

  final lines = rawLines
      .skip(lineIndex)
      .where((line) => line.isNotEmpty)
      .toList();

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
      .map((header) => header.trim().toLowerCase().replaceFirst('\ufeff', ''))
      .toList();

  final isClientFormat = (headers.contains('team name') || headers.contains('team_name')) &&
      (headers.contains('team members') || headers.contains('team_members') || headers.contains('members') || headers.contains('names'));

  if (isClientFormat) {
    final teamNameIdx = headers.contains('team name') ? headers.indexOf('team name') : headers.indexOf('team_name');
    
    var projectIdx = headers.indexWhere((h) =>
        h == 'capstone project' ||
        h == 'pit project' ||
        h == 'project' ||
        h == 'project title' ||
        h == 'project_title' ||
        h == 'module' ||
        h == 'modules' ||
        h == 'project / module' ||
        h == 'project/module' ||
        h == 'project / system' ||
        h == 'system / module' ||
        h == 'system/module' ||
        h == 'system' ||
        h.contains('project') ||
        h.contains('module'));
    
    final adviserIdx = headers.indexOf('adviser');
    
    var sectionIdx = headers.indexOf('section');
    if (sectionIdx == -1) sectionIdx = headers.indexOf('class section');
    if (sectionIdx == -1) sectionIdx = headers.indexOf('class_section');

    var membersIdx = headers.indexOf('team members');
    if (membersIdx == -1) membersIdx = headers.indexOf('team_members');
    if (membersIdx == -1) membersIdx = headers.indexOf('members');
    if (membersIdx == -1) membersIdx = headers.indexOf('names');

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

    for (final line in lines.skip(1)) {
      final lineTrimmed = line.trim();
      if (lineTrimmed.isEmpty) continue;

      final columns = _parseCsvLine(line);
      final firstCol = columns.isNotEmpty ? columns[0].trim() : '';
      final fullRowText = columns.join(' ').trim();

      // Check for intermediate SECTION: divider header or Section, <Name>
      final sectionHeaderMatch = RegExp(
        r'^(?:SECTION|CLASS\s*SECTION)\s*:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(firstCol.isNotEmpty ? firstCol : fullRowText);
      if (sectionHeaderMatch != null) {
        if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        section = sectionHeaderMatch.group(1)!.trim();
        allSections.add(section);
        continue;
      }

      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'section' || firstCol.toLowerCase() == 'class section')) {
        if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        section = columns[1].trim();
        allSections.add(section);
        continue;
      }

      // Check for intermediate System Name or Project Manager
      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'system name' || firstCol.toLowerCase() == 'system_name' || firstCol.toLowerCase() == 'system')) {
        systemName = columns[1].trim();
        continue;
      }
      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'project manager' || firstCol.toLowerCase() == 'project_manager' || firstCol.toLowerCase() == 'pm')) {
        projectManager = columns[1].trim();
        continue;
      }

      // Check for intermediate ADVISER: or INSTRUCTOR: divider header
      final adviserHeaderMatch = RegExp(
        r'^(?:ADVISER|INSTRUCTOR)\s*:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(firstCol.isNotEmpty ? firstCol : fullRowText);
      if (adviserHeaderMatch != null) {
        if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        currentAdviser = adviserHeaderMatch.group(1)!.trim();
        continue;
      }

      // Check for ADVISER, <Name> format
      if (columns.length >= 2 &&
          (firstCol.toLowerCase() == 'adviser' || firstCol.toLowerCase() == 'instructor')) {
        if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
          currentTeam = null;
        }
        currentAdviser = columns[1].trim();
        continue;
      }

      // Check if this line is a repeated table header (e.g. "Team Name,Names,Modules")
      final lineNormalized = columns.map((c) => c.trim().toLowerCase()).toList();
      if (lineNormalized.contains('team name') || lineNormalized.contains('team_name')) {
        continue;
      }

      String read(int idx) => (idx >= 0 && idx < columns.length) ? columns[idx] : '';

      final teamName = read(teamNameIdx);
      final project = read(projectIdx);
      final rowAdviser = adviserIdx >= 0 ? read(adviserIdx) : '';
      final effectiveAdviser = rowAdviser.isNotEmpty ? rowAdviser : currentAdviser;
      final member = read(membersIdx);
      final rowSection = read(sectionIdx);
      final effectiveSection = rowSection.isNotEmpty ? rowSection : section;

      if (teamName.isNotEmpty) {
        if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
          parsedRows.add(currentTeam);
        }
        currentTeam = {
          'team_name': teamName,
          'project_title': project.isNotEmpty ? project : teamName,
          'year_level': '',
          'member_ids': <String>[if (member.isNotEmpty) member],
          'leader_id': member,
          if (effectiveAdviser.isNotEmpty) 'adviser_name': effectiveAdviser,
          if (effectiveSection.isNotEmpty) 'section': effectiveSection,
          if (systemName.isNotEmpty) 'system_name': systemName,
          if (projectManager.isNotEmpty) 'project_manager': projectManager,
        };
        if (rowSection.isNotEmpty) {
          section = rowSection;
          allSections.add(section);
        }
      } else {
        if (currentTeam != null && member.isNotEmpty) {
          (currentTeam['member_ids'] as List<String>).add(member);
        }
      }
    }
    if (currentTeam != null && (currentTeam['member_ids'] as List).isNotEmpty) {
      parsedRows.add(currentTeam);
    }
    return ParsedBulkCsvResult(
      rows: parsedRows,
      csvColumns: headers,
      section: allSections.isNotEmpty ? allSections.join(', ') : (section.isNotEmpty ? section : null),
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
          'team_name': read(teamNameIndex),
          'project_title': read(projectTitleIndex),
          if (level.isNotEmpty) 'level': level,
          'year_level': yearLevel.isNotEmpty ? yearLevel : _yearFromLevel(level),
          'member_ids': read(memberIdsIndex)
              .split('|')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
          'leader_id': read(leaderIdIndex),
          if (adviserNameIndex >= 0) 'adviser_name': read(adviserNameIndex),
          if (effectiveSec.isNotEmpty) 'section': effectiveSec,
        };
      })
      .where((row) => row['team_name'].toString().isNotEmpty)
      .toList();
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
  final targetYear = existingYear.isNotEmpty ? existingYear : (pitLeadYear ?? '');
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

const teamSampleYearLevels = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
];

/// One demo team per year level (4 members each). Matches `sample_file/demo_teams_*`.
const Map<String, String> sampleTeamCsvByYear = {
  '1st Year':
      '$teamBulkImportHeaderPit\n'
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
      '$teamBulkImportHeaderPit\n'
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
      '$teamBulkImportHeaderPit\n'
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
      'Team SkyLedger,Alumni Career Tracker,Ricardo Fontanilla,Marcus Villar\n'
      ',,,Patricia Ong\n'
      ',,,Ethan Salazar\n'
      ',,,Zoe Castillo\n'
      'Team ByteForce,AI-Powered Attendance System,Ricardo Fontanilla,Ryan Torres\n'
      ',,,Nina Villanueva\n'
      ',,,Diego Garcia\n'
      ',,,Patricia Ramos\n'
      'Team NexGen,Campus Lost and Found Portal,Ricardo Fontanilla,Carlos Bautista\n'
      ',,,Sophia Santos\n'
      ',,,Miguel Cruz\n'
      ',,,Isabella Alcantara\n',
};

String sampleTeamCsvForYear(
  String yearLevel, {
  required bool isCapstoneAdmin,
}) {
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

final sampleTeamCsvTemplateCapstone =
    sampleTeamCsvByYear['3rd Year']!.trim();

const sampleTeamCsvTemplatePit =
    'Team Name,PIT Project,Team Members\n'
    'Team CodeLearners,Smart Campus Navigator,Carlos Reyes\n'
    ',,Maria Santos\n'
    ',,Juan Dela Cruz\n'
    ',,Ana Mendoza\n';

List<Map<String, dynamic>> trimRowsAfterImport({
  required List<Map<String, dynamic>> rows,
  required List<dynamic> importedRows,
}) {
  final remove = <int>{
    for (final item in importedRows)
      if (int.tryParse(item.toString()) != null) int.parse(item.toString()),
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
