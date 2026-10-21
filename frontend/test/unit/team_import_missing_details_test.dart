import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'continuous workbook keeps unnamed teams distinct and counts actual members',
    () {
      final book = xl.Excel.decodeBytes(
        generateOfficialTeamRosterExcelBytes(isCapstone: false),
      );
      final sheet = book.tables.values.first;
      for (final cell in ['B5', 'B9', 'C5', 'C9', 'H7', 'H11', 'I7', 'I11']) {
        sheet.cell(xl.CellIndex.indexByString(cell)).value = xl.TextCellValue(
          '',
        );
      }
      // Team blocks remain intact while each team has a different member count.
      for (final cell in ['F8', 'F11', 'F12', 'L9', 'L10']) {
        sheet.cell(xl.CellIndex.indexByString(cell)).value = xl.TextCellValue(
          '',
        );
      }
      final rows = parseTeamBulkCsv(teamXlsxToCsv(book.encode()!)).rows;
      expect(rows, hasLength(16));
      expect(rows[0]['team_name'], '');
      expect(rows[1]['team_name'], '');
      expect(rows[8]['team_name'], '');
      expect(rows[9]['team_name'], '');
      expect(rows[0]['member_ids'], hasLength(3));
      expect(rows[1]['member_ids'], hasLength(2));
      expect(rows[8]['member_ids'], hasLength(2));
      expect(rows[9]['member_ids'], hasLength(4));
      expect(rows.map((row) => row['group_key']).toSet(), hasLength(16));
    },
  );

  test(
    'public templates have no helper content, group columns or separator rows',
    () {
      final book = xl.Excel.decodeBytes(
        generateOfficialTeamRosterExcelBytes(isCapstone: true),
      );
      final sheet = book.tables.values.first;
      expect(sheet.cell(xl.CellIndex.indexByString('B1')).value, isNull);
      expect(sheet.cell(xl.CellIndex.indexByString('B2')).value, isNull);
      for (var row = 4; row < 36; row++) {
        expect(
          sheet
              .cell(
                xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
              )
              .value
              .toString(),
          isNotEmpty,
        );
      }
      final csv = officialTeamRosterCsv(isCapstone: true);
      expect(csv, isNot(contains('group_key')));
      expect(csv, isNot(contains('Leave missing')));
      expect(csv, isNot(contains('Separate teams')));
    },
  );

  test(
    'mixed and consecutive unnamed groups use separators, not member count',
    () {
      const csv =
          'Team Name,PIT Project,Section,Instructor,Team Members\n'
          ',Campus Navigation,BSIT-3A,Ana Santos,Juan Cruz\n'
          ',,BSIT-3A,Ana Santos,Maria Santos\n'
          ',,BSIT-3A,Ana Santos,\n'
          ',,BSIT-3A,Ana Santos,Carlo Ramos\n'
          ',,BSIT-3A,Ana Santos,\n'
          'Named team,,BSIT-3A,Ana Santos,Bea Castro\n'
          ',,,,Kevin Reyes\n';
      final result = parseTeamBulkCsv(csv);
      expect(result.rows, hasLength(3));
      expect(result.rows.map((row) => row['team_name']), [
        '',
        '',
        'Named team',
      ]);
      expect(result.rows.map((row) => row['leader_id']), [
        'Juan Cruz',
        'Carlo Ramos',
        'Bea Castro',
      ]);
      expect(result.rows[0]['member_ids'], ['Juan Cruz', 'Maria Santos']);
      expect(result.rows[1]['project_title'], '');
      expect(result.rows.map((row) => row['group_key']).toSet(), hasLength(3));
      final before = result.rows.first['group_key'];
      result.rows.first['team_name'] = 'Edited name';
      expect(result.rows.first['group_key'], before);
    },
  );

  test(
    'side by side blocks preserve independent boundaries and shared metadata',
    () {
      const csv =
          'Team Name,PIT Project,Section,Instructor,Team Members,,System Name,Campus Services,,,\n'
          ',Title,BSIT-3A,Ana,Alice,,Project Manager,Rosa,,,\n'
          ',,,,Bob,,Team Name,Module,Section,Instructor,Team Members\n'
          ',,,,,,,Accounts,BSIT-3A,Ana,Rosa\n'
          ',,,,Carl,,,,,,Luis\n'
          ',,,,,,,,,,\n'
          'Named,,BSIT-3A,Ana,Dina,,,,BSIT-3A,Ana,Clara\n';
      final result = parseTeamBulkCsv(csv);
      expect(result.rows, hasLength(5));
      expect(result.rows[0]['member_ids'], ['Alice', 'Bob']);
      expect(result.rows[1]['member_ids'], ['Carl']);
      expect(result.rows[3]['member_ids'], ['Rosa', 'Luis']);
      expect(result.rows[4]['member_ids'], ['Clara']);
      expect(result.rows[3]['system_name'], 'Campus Services');
      expect(result.rows[3]['project_manager'], 'Rosa');
      expect(result.rows.map((r) => r['group_key']).toSet(), hasLength(5));
    },
  );

  test('omitted project column and legacy rows both support missing names', () {
    final result = parseTeamBulkCsv(
      'Team Name,Section,Team Members\n,BSIT-3A,Alice\n,,Bob\n\n,BSIT-3A,Clara',
    );
    expect(result.rows, hasLength(2));
    final legacy = parseTeamBulkCsv(
      'team_name,member_ids,leader_id\n,Alice|Bob,Alice\n,Clara,Clara',
    );
    expect(legacy.rows, hasLength(2));
  });

  test(
    'CSV re-export preserves missing-name grouping and literal multiline titles',
    () {
      final rows = [
        {
          'team_name': '',
          'project_title': '=Campus, "Records"\nSecond line',
          'member_ids': ['Alice', 'Bob'],
        },
        {
          'team_name': '',
          'project_title': '',
          'member_ids': ['Clara'],
        },
      ];
      final result = parseTeamBulkCsv(
        rowsToTeamCsv(rows, isCapstoneAdmin: false),
      );
      expect(result.rows, hasLength(2));
      expect(result.rows.first['project_title'], rows.first['project_title']);
      expect(result.rows.last['leader_id'], 'Clara');
    },
  );

  test('multiple different-width files keep source identity and metadata', () {
    final first = officialTeamRosterCsv(
      isCapstone: false,
      assignedSection: 'BSIT-3A',
    );
    const second =
        'Team Name,PIT Project,Section,Team Members\n,Other title,BSIT-3B,Other Student';
    final result = parseTeamBulkCsv(
      readTeamImportFiles([
        PickedTabularFile(
          name: 'first.csv',
          extension: 'csv',
          bytes: utf8.encode(first),
        ),
        PickedTabularFile(
          name: 'second.csv',
          extension: 'csv',
          bytes: utf8.encode(second),
        ),
      ]),
    );
    expect(result.rows, hasLength(17));
    expect(result.rows.map((r) => r['group_key']).toSet(), hasLength(17));
    expect(result.rows.last['member_ids'], ['Other Student']);
    expect(result.rows[8]['system_name'], 'Societree');
  });

  for (final capstone in [true, false]) {
    test(
      'official $capstone workbook has valid sheet properties and distinct groups',
      () {
        final bytes = generateOfficialTeamRosterExcelBytes(
          isCapstone: capstone,
          assignedSection: 'BSIT-3A',
        );
        final archive = ZipDecoder().decodeBytes(bytes);
        final xml = XmlDocument.parse(
          utf8.decode(
            archive.findFile('xl/workbook.xml')!.content as List<int>,
          ),
        );
        for (final sheet in xml.findAllElements('sheet')) {
          final name = sheet.getAttribute('name')!;
          expect(name.length, lessThanOrEqualTo(31));
          expect(RegExp(r'[\\/?*\[\]:]').hasMatch(name), isFalse);
        }
        final workbook = xl.Excel.decodeBytes(bytes);
        final sheet = workbook.tables.values.first;
        expect(
          sheet.cell(xl.CellIndex.indexByString('H4')).value.toString(),
          'System Name:',
        );
        expect(
          sheet.cell(xl.CellIndex.indexByString('I4')).value.toString(),
          capstone ? 'Hospital Management System' : 'Societree',
        );
        final rows = parseTeamBulkCsv(teamXlsxToCsv(bytes)).rows;
        expect(rows, hasLength(16));
        expect(rows.where((r) => r['team_name'] == ''), isEmpty);
        final members = rows.expand((r) => r['member_ids'] as List).toList();
        expect(members.toSet().length, members.length);
      },
    );
  }
}
