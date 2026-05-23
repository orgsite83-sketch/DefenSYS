const teamBulkImportHeader =
    'team_name,project_title,year_level,member_ids,leader_id,adviser_id';

const teamBulkImportHeaderPit =
    'team_name,project_title,member_ids,leader_id';

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
    final members = row['member_ids'];
    final memberText = members is List
        ? members.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).join('|')
        : members?.toString() ?? '';
    if (isCapstoneAdmin) {
      buffer.writeln([
        _csvCell(row['team_name']),
        _csvCell(row['project_title']),
        _csvCell(row['year_level']),
        _csvCell(memberText),
        _csvCell(row['leader_id']),
        _csvCell(row['adviser_id']),
      ].join(','));
    } else {
      buffer.writeln([
        _csvCell(row['team_name']),
        _csvCell(row['project_title']),
        _csvCell(memberText),
        _csvCell(row['leader_id']),
      ].join(','));
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

List<Map<String, dynamic>> parseTeamBulkCsv(String csv) {
  final lines = csv
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length < 2) {
    return [];
  }

  final headers = lines.first
      .split(',')
      .map((header) => header.trim().toLowerCase().replaceFirst('\ufeff', ''))
      .toList();
  int index(String name) => headers.indexOf(name);
  final teamNameIndex = index('team_name');
  final projectTitleIndex = index('project_title');
  final levelIndex = index('level');
  final yearLevelIndex = index('year_level');
  final memberIdsIndex = index('member_ids');
  final leaderIdIndex = index('leader_id');
  final adviserIdIndex = index('adviser_id');

  if ([teamNameIndex, memberIdsIndex, leaderIdIndex].contains(-1)) {
    return [];
  }

  return lines
      .skip(1)
      .map((line) {
        final columns = line.split(',').map((cell) => cell.trim()).toList();
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
        };
      })
      .where((row) => row['team_name'].toString().isNotEmpty)
      .toList();
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
  if (pitLeadYear != null && pitLeadYear.isNotEmpty) {
    row['year_level'] = pitLeadYear;
    row['level'] = '$pitLeadYear PIT';
    row.remove('adviser_id');
  }
}

List<Map<String, dynamic>> parseTeamBulkCsvWithContext(
  String csv, {
  required bool isCapstoneAdmin,
  String? pitLeadYear,
}) {
  final rows = parseTeamBulkCsv(csv);
  for (final row in rows) {
    applyDerivedLevelToRow(
      row,
      isCapstoneAdmin: isCapstoneAdmin,
      pitLeadYear: pitLeadYear,
    );
  }
  return rows;
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
      'Team NovaPath,Campus Wayfinder App,1st Year,James Rivera|Sofia Lim|Miguel Torres|Chloe Nguyen,James Rivera,\n',
  '2nd Year':
      '$teamBulkImportHeader\n'
      'Team ByteBridge,Library Seat Finder,2nd Year,Darren Kim|Isabel Cruz|Noah Ramos|Leah Fernandez,Darren Kim,\n',
  '3rd Year':
      '$teamBulkImportHeader\n'
      'Team CodeLearners,Smart Campus Navigator,3rd Year,Carlos Reyes|Maria Santos|Juan Dela Cruz|Ana Mendoza,Carlos Reyes,Ricardo Fontanilla\n',
  '4th Year':
      '$teamBulkImportHeader\n'
      'Team SkyLedger,Alumni Career Tracker,4th Year,Marcus Villar|Patricia Ong|Ethan Salazar|Zoe Castillo,Marcus Villar,Ricardo Fontanilla\n',
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
  final rows = parseTeamBulkCsv(source);
  return rowsToTeamCsv(rows, isCapstoneAdmin: false);
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
    '$teamBulkImportHeaderPit\n'
    'Team CodeLearners,Smart Campus Navigator,Carlos Reyes|Maria Santos|Juan Dela Cruz|Ana Mendoza,Carlos Reyes\n';

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
