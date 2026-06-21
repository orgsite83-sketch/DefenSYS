const teamBulkImportHeader =
    'Team Name,Capstone Project,Adviser,Team Members';

const teamBulkImportHeaderPit =
    'Team Name,PIT Project,Team Members';

const teamBulkImportLegacyHeader =
    'team_name,project_title,level,year_level,member_ids,leader_id,adviser_id';

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
    final adviser = row['adviser_id']?.toString() ?? '';
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
    } else if (char == ',' && !inQuotes) {
      result.add(currentCell.toString().trim());
      currentCell.clear();
    } else {
      currentCell.write(char);
    }
  }
  result.add(currentCell.toString().trim());
  return result;
}

ParsedBulkCsvResult parseTeamBulkCsv(String csv) {
  final rawLines = csv
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
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
        headers.contains('member_ids');
    if (hasTeamName && hasMembers) {
      lineIndex = i;
      break;
    }
  }

  if (lineIndex == -1) {
    return const ParsedBulkCsvResult(rows: [], csvColumns: []);
  }

  String nextCell(List<String> row, int index) {
    for (var i = index + 1; i < row.length; i++) {
      final val = row[i].trim();
      if (val.isNotEmpty) return val;
    }
    return '';
  }

  for (var i = 0; i < lineIndex; i++) {
    final row = matrix[i];
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
      readMeta(const ['section'], (val) => section = val);
    }
    if (systemName.isEmpty) {
      readMeta(const ['system name', 'system_name'], (val) => systemName = val);
    }
    if (projectManager.isEmpty) {
      readMeta(const ['project manager', 'project_manager', 'pm'], (val) => projectManager = val);
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
      (headers.contains('team members') || headers.contains('team_members') || headers.contains('members'));

  if (isClientFormat) {
    final teamNameIdx = headers.contains('team name') ? headers.indexOf('team name') : headers.indexOf('team_name');
    
    var projectIdx = headers.indexOf('capstone project');
    if (projectIdx == -1) projectIdx = headers.indexOf('pit project');
    if (projectIdx == -1) projectIdx = headers.indexOf('project');
    if (projectIdx == -1) projectIdx = headers.indexOf('project title');
    if (projectIdx == -1) projectIdx = headers.indexOf('module');
    if (projectIdx == -1) projectIdx = headers.indexOf('project_title');
    
    final adviserIdx = headers.indexOf('adviser');
    
    var membersIdx = headers.indexOf('team members');
    if (membersIdx == -1) membersIdx = headers.indexOf('team_members');
    if (membersIdx == -1) membersIdx = headers.indexOf('members');

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
    Map<String, dynamic>? currentTeam;

    for (final line in lines.skip(1)) {
      final columns = _parseCsvLine(line);
      String read(int idx) => (idx >= 0 && idx < columns.length) ? columns[idx] : '';

      final teamName = read(teamNameIdx);
      final project = read(projectIdx);
      final adviser = read(adviserIdx);
      final member = read(membersIdx);

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
          if (adviserIdx >= 0) 'adviser_id': adviser,
          if (section.isNotEmpty) 'section': section,
        };
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
      section: section.isNotEmpty ? section : null,
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
  final adviserIdIndex = index('adviser_id');

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
          if (adviserIdIndex >= 0) 'adviser_id': read(adviserIdIndex),
          if (section.isNotEmpty) 'section': section,
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
      '$teamBulkImportHeader\n'
      'Team NovaPath,Campus Wayfinder App,,James Rivera\n'
      ',,,Sofia Lim\n'
      ',,,Miguel Torres\n'
      ',,,Chloe Nguyen\n',
  '2nd Year':
      '$teamBulkImportHeader\n'
      'Team ByteBridge,Library Seat Finder,,Darren Kim\n'
      ',,,Isabel Cruz\n'
      ',,,Noah Ramos\n'
      ',,,Leah Fernandez\n',
  '3rd Year':
      '$teamBulkImportHeader\n'
      'Team CodeLearners,Smart Campus Navigator,Ricardo Fontanilla,Carlos Reyes\n'
      ',,,Maria Santos\n'
      ',,,Juan Dela Cruz\n'
      ',,,Ana Mendoza\n',
  '4th Year':
      '$teamBulkImportHeader\n'
      'Team SkyLedger,Alumni Career Tracker,Ricardo Fontanilla,Marcus Villar\n'
      ',,,Patricia Ong\n'
      ',,,Ethan Salazar\n'
      ',,,Zoe Castillo\n',
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
