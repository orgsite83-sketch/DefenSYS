import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:defensys/utils/team_bulk_import_csv.dart';

void main() {
  test('generateOfficialTeamRosterExcelBytes produces valid excel bytes that round-trip through student_teams parser', () {
    final bytes = generateOfficialTeamRosterExcelBytes(isCapstone: true);
    expect(bytes, isNotEmpty);
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel['defensys_team_roster_template'];
    expect(sheet.spannedItems, isNotEmpty);
    expect(sheet.spannedItems, contains('D5:D36'));
    expect(sheet.spannedItems, contains('E5:E20'));
    expect(sheet.spannedItems, contains('E21:E36'));
    expect(sheet.spannedItems, contains('J7:J38'));
    expect(sheet.spannedItems, contains('K7:K22'));
    expect(sheet.spannedItems, contains('K23:K38'));

    // Expand merged cells like student_teams_screen does (if any)
    for (final span in sheet.spannedItems) {
      final parts = span.split(':');
      if (parts.length != 2) continue;
      final start = CellIndex.indexByString(parts[0]);
      final end = CellIndex.indexByString(parts[1]);
      final startVal = sheet.cell(start).value;
      if (startVal == null) continue;
      final minR = start.rowIndex < end.rowIndex ? start.rowIndex : end.rowIndex;
      final maxR = start.rowIndex > end.rowIndex ? start.rowIndex : end.rowIndex;
      final minC = start.columnIndex < end.columnIndex ? start.columnIndex : end.columnIndex;
      final maxC = start.columnIndex > end.columnIndex ? start.columnIndex : end.columnIndex;
      for (var r = minR; r <= maxR; r++) {
        for (var c = minC; c <= maxC; c++) {
          if (r == start.rowIndex && c == start.columnIndex) continue;
          sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), startVal);
        }
      }
    }

    // Convert to CSV
    final csvRows = <String>[];
    for (var r = 0; r < sheet.maxRows; r++) {
      final cells = <String>[];
      for (var c = 0; c < sheet.maxColumns; c++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value;
        final str = val?.toString() ?? '';
        cells.add(str);
      }
      csvRows.add(cells.join(','));
    }
    final csvText = csvRows.join('\n');

    final parsed = parseTeamBulkCsv(csvText);
    expect(parsed.rows, hasLength(16));
    expect(parsed.systemName, 'Hospital Management System');
    expect(parsed.projectManager, 'Juan Dela Cruz');
    expect(parsed.section, contains('BSIT-4A'));
    expect(parsed.section, contains('BSIT-4B'));

    // Check first 4A team
    expect(parsed.rows[0]['team_name'], 'Team SkyLedger');
    expect(parsed.rows[0]['section'], 'BSIT-4A');
    expect(parsed.rows[0]['adviser_name'], 'Prof. Alex Santos');

    // Check second adviser in 4A
    expect(parsed.rows[4]['team_name'], 'Team CyberGuard');
    expect(parsed.rows[4]['section'], 'BSIT-4A');
    expect(parsed.rows[4]['adviser_name'], 'Prof. Elena Ramos');

    // Check first 4B team
    expect(parsed.rows[8]['team_name'], 'Team MedRecord');
    expect(parsed.rows[8]['section'], 'BSIT-4B');
    expect(parsed.rows[8]['adviser_name'], 'Prof. Roberto Gomez');
    expect(parsed.rows[8]['project_manager'], 'Juan Dela Cruz');

    // Check second adviser in 4B
    expect(parsed.rows[12]['team_name'], 'Team MedTriage');
    expect(parsed.rows[12]['section'], 'BSIT-4B');
    expect(parsed.rows[12]['adviser_name'], 'Prof. Cynthia Morales');
  });

  test('generateOfficialTeamRosterExcelBytes PIT produces valid excel bytes that round-trip', () {
    final bytes = generateOfficialTeamRosterExcelBytes(isCapstone: false);
    expect(bytes, isNotEmpty);

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel['defensys_pit_team_roster_template'];
    expect(sheet.spannedItems, isNotEmpty);
    expect(sheet.spannedItems, contains('D5:D36'));
    expect(sheet.spannedItems, contains('E5:E36'));
    expect(sheet.spannedItems, contains('J7:J38'));
    expect(sheet.spannedItems, contains('K7:K38'));

    // Expand merged cells (if any)
    for (final span in sheet.spannedItems) {
      final parts = span.split(':');
      if (parts.length != 2) continue;
      final start = CellIndex.indexByString(parts[0]);
      final end = CellIndex.indexByString(parts[1]);
      final startVal = sheet.cell(start).value;
      if (startVal == null) continue;
      final minR = start.rowIndex < end.rowIndex ? start.rowIndex : end.rowIndex;
      final maxR = start.rowIndex > end.rowIndex ? start.rowIndex : end.rowIndex;
      final minC = start.columnIndex < end.columnIndex ? start.columnIndex : end.columnIndex;
      final maxC = start.columnIndex > end.columnIndex ? start.columnIndex : end.columnIndex;
      for (var r = minR; r <= maxR; r++) {
        for (var c = minC; c <= maxC; c++) {
          if (r == start.rowIndex && c == start.columnIndex) continue;
          sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), startVal);
        }
      }
    }

    final csvRows = <String>[];
    for (var r = 0; r < sheet.maxRows; r++) {
      final cells = <String>[];
      for (var c = 0; c < sheet.maxColumns; c++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value;
        final str = val?.toString() ?? '';
        cells.add(str);
      }
      csvRows.add(cells.join(','));
    }
    final csvText = csvRows.join('\n');

    final parsed = parseTeamBulkCsv(csvText);
    expect(parsed.rows, hasLength(16));
    expect(parsed.systemName, 'Societree');
    expect(parsed.projectManager, 'Juan Dela Cruz');
    expect(parsed.section, contains('BSIT-2A'));
    expect(parsed.section, contains('BSIT-2B'));
  });
}
