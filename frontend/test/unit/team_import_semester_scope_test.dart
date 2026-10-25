import 'dart:io';

import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reported third-year 16-team workbook does not hardcode PIT scope', () {
    final file = File('../Defensys_sample files/sample_file/16_Teams_3rd_Year/1st Sem/team/Team16roster.xlsx');
    final csv = readTeamImportFiles([
      PickedTabularFile(name: 'Team16roster.xlsx', extension: 'xlsx', bytes: file.readAsBytesSync()),
    ]);
    final parsed = parseTeamBulkCsvWithContext(csv, isCapstoneAdmin: true);
    expect(parsed.rows, hasLength(16));
    expect(parsed.rows.every((row) => row['year_level'] == '3rd Year'), isTrue);
    expect(parsed.rows.every((row) => row['level'] == null), isTrue);
    expect(parsed.rows.where((row) => row['section'] == 'BSIT-3A'), hasLength(8));
    expect(parsed.rows.where((row) => row['section'] == 'BSIT-3B'), hasLength(8));
    final safeguard = parsed.rows.singleWhere((row) => row['team_name'] == 'Team SafeGuard');
    expect(safeguard['member_ids'], ['Hazel CORONEL', 'Bryan OROZCO', 'Gillian SANDOVAL']);
    expect(safeguard['leader_id'], 'Hazel CORONEL');
    expect(parsed.rows.every((row) => row['leader_id'] == (row['member_ids'] as List).first), isTrue);
  });

  test('third-year XLSX shared and separate projects retain neutral scope through upload', () {
    final workbook = xl.Excel.createExcel();
    final sheet = workbook['Sheet1'];
    final cells = <List<String>>[
      ['System Name:', 'Agro Platform'],
      ['Project Manager:', 'Gabriel Navarro'],
      ['Team Name', 'Module', 'Section', 'Adviser', 'Team Members', '',
        'Team Name', 'Project', 'Section', 'Adviser', 'Team Members'],
      ['Team AgriPulse', 'Soil Sensor', 'BSIT-3A', 'Eduardo Padilla', 'Gabriel Navarro', '',
        'Team EcoSort', 'Waste Sorting', 'BSIT-3B', 'Arsenio Macasaet', 'Kenneth Dizon'],
      ['', '', '', '', 'Daphne Alcantara', '', '', '', '', '', 'Princess Lopez'],
    ];
    for (final row in cells) {
      sheet.appendRow(row.map(xl.TextCellValue.new).toList());
    }
    final csv = readTeamImportFiles([
      PickedTabularFile(name: 'Team16roster.xlsx', extension: 'xlsx', bytes: workbook.encode()!),
    ]);
    final parsed = parseTeamBulkCsvWithContext(csv, isCapstoneAdmin: true);
    expect(parsed.rows, hasLength(2));
    for (final row in parsed.rows) {
      expect(row['year_level'], '3rd Year');
      expect(row['level'], isNull);
      expect(row['member_ids'], hasLength(2));
      expect(row['adviser_name'], isNotEmpty);
    }
    expect(parsed.rows.first['team_name'], 'Team AgriPulse');
    expect(parsed.rows.first['system_name'], 'Agro Platform');
    expect(parsed.rows.first['project_manager'], 'Gabriel Navarro');
    final exported = parseTeamBulkCsv(rowsToTeamCsv(parsed.rows, isCapstoneAdmin: true));
    expect(exported.rows.every((row) => row['level'] == null), isTrue);
    expect(exported.rows.every((row) => row['year_level'] == '3rd Year'), isTrue);
  });

  test('staggered third-year tables do not invent a PIT level', () {
    const csv = 'Team Name,Project,Section,Adviser,Team Members,,System Name:,Shared Platform\n'
        'Solo,Sensor,BSIT-3B,Ada Lovelace,Alice,,Project Manager:,Carlo\n'
        ',,,,Bob,,Team Name,Module,Section,Adviser,Team Members\n'
        ',,,,,,Shared,Telemetry,BSIT-3A,Ada Lovelace,Carlo\n'
        ',,,,,,,,,,Dina\n';
    final parsed = parseTeamBulkCsvWithContext(csv, isCapstoneAdmin: true);
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows.every((row) => row['year_level'] == '3rd Year'), isTrue);
    expect(parsed.rows.every((row) => row['level'] == null), isTrue);
  });

  test('a team name above its first member uses the first listed member as leader', () {
    const csv = 'Team Name,Module,Section,Adviser,Team Members\n'
        'SafeGuard,PPE Detection,BSIT-3B,Ada,\n'
        ',,,,Hazel Coronel\n'
        ',,,,Bryan Orozco\n'
        'Next team,Dispatch,BSIT-3B,Ada,Martin Brillantes\n';
    final parsed = parseTeamBulkCsv(csv);
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows.first['member_ids'], ['Hazel Coronel', 'Bryan Orozco']);
    expect(parsed.rows.first['leader_id'], 'Hazel Coronel');
    expect(parsed.rows.last['member_ids'], ['Martin Brillantes']);
  });

  test('explicit program and PIT caller scope are preserved for server validation', () {
    const explicit = 'team_name,project_title,level,year_level,member_ids,leader_id\n'
        'Explicit,Project,3rd Year PIT,3rd Year,Alice,Alice';
    expect(parseTeamBulkCsvWithContext(explicit, isCapstoneAdmin: true).rows.single['level'], '3rd Year PIT');
    const implicit = 'Team Name,Module,Section,Instructor,Team Members\n'
        'PIT team,Project,BSIT-3A,Ada,Alice';
    expect(parseTeamBulkCsvWithContext(implicit, isCapstoneAdmin: false,
        pitLeadYear: '3rd Year').rows.single['level'], '3rd Year PIT');
  });
}

