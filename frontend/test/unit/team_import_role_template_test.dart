import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'instructor workbook has four columns per table and intact team merges',
    () {
      final bytes = generateOfficialTeamRosterExcelBytes(
        isCapstone: false,
        instructorWorkspace: true,
        assignedSection: 'BSIT-2B',
      );
      final sheet = xl.Excel.decodeBytes(bytes).tables.values.first;
      String cell(String address) =>
          '${sheet.cell(xl.CellIndex.indexByString(address)).value ?? ''}';
      expect(cell('E4'), 'Team Members');
      expect(cell('J6'), 'Team Members');
      expect(cell('G4'), 'System Name:');
      expect(cell('H4'), 'Societree');
      expect(sheet.spannedItems, contains('B5:B8'));
      expect(sheet.spannedItems, contains('G7:G10'));
      expect(
        sheet.rows
            .expand((r) => r)
            .whereType<xl.Data>()
            .any((c) => '${c.value}'.contains('Instructor')),
        isFalse,
      );
      final parsed = parseTeamBulkCsv(teamXlsxToCsv(bytes));
      expect(parsed.rows, hasLength(16));
      expect(parsed.rows.every((r) => r['section'] == 'BSIT-2B'), isTrue);
      expect(
        parsed.rows.every((r) => (r['member_ids'] as List).length == 4),
        isTrue,
      );
      expect(parsed.rows.map((r) => r['group_key']).toSet(), hasLength(16));
      expect(
        parsed.rows.take(8).every((r) => r['system_name'] == null),
        isTrue,
      );
      expect(
        parsed.rows.skip(8).every((r) => r['system_name'] == 'Societree'),
        isTrue,
      );
      final csv = officialTeamRosterCsv(
        isCapstone: false,
        instructorWorkspace: true,
        assignedSection: 'BSIT-2B',
      );
      expect(csv, isNot(contains('Instructor')));
      expect(parseTeamBulkCsv(csv).rows, hasLength(16));
    },
  );

  test('public management templates retain faculty columns', () {
    expect(officialTeamRosterCsv(isCapstone: false), contains('Instructor'));
    expect(officialTeamRosterCsv(isCapstone: true), contains('Adviser'));
  });

  test(
    'metadata and Module intent survive normalization and CSV draft export',
    () {
      final bytes = generateOfficialTeamRosterExcelBytes(
        isCapstone: false,
        instructorWorkspace: true,
      );
      final parsed = parseTeamBulkCsv(
        readTeamImportFiles([
          PickedTabularFile(
            name: 'roster.xlsx',
            extension: 'xlsx',
            bytes: bytes,
          ),
        ]),
      );
      final restored = parseTeamBulkCsv(
        rowsToTeamCsv(parsed.rows, isCapstoneAdmin: false),
      );
      expect(restored.rows, hasLength(16));
      expect(
        restored.rows.take(8).every((r) => '${r['system_name'] ?? ''}'.isEmpty),
        isTrue,
      );
      expect(
        restored.rows.skip(8).every((r) => r['project_kind'] == 'module'),
        isTrue,
      );
      expect(
        restored.rows.skip(8).every((r) => r['system_name'] == 'Societree'),
        isTrue,
      );
      expect(
        restored.rows
            .skip(8)
            .every((r) => '${r['project_manager']}'.isNotEmpty),
        isTrue,
      );
    },
  );

  test(
    'new section clears inherited shared headers and conflicting headers remain distinct',
    () {
      const csv =
          'Section,BSIT-2A\nSystem Name:,First system\nProject Manager:,Ana Reyes\n'
          'Team Name,Module,Section,Team Members\nFirst,Module A,BSIT-2A,Ana Reyes\n'
          'Section,BSIT-2B\nSecond,Module B,BSIT-2B,Luis Santos\n'
          'System Name:,Second system\nThird,Module C,BSIT-2B,Bea Cruz\n'
          'System Name:,Conflicting system\nFourth,Module D,BSIT-2B,Carlo Ramos\n';
      final rows = parseTeamBulkCsv(csv).rows;
      expect(rows, hasLength(4));
      expect(rows[0]['system_name'], 'First system');
      expect(rows[1]['system_name'], isNull);
      expect(rows[1]['project_manager'], isNull);
      expect(rows[2]['system_name'], 'Second system');
      expect(rows[3]['system_name'], 'Conflicting system');
    },
  );
}
