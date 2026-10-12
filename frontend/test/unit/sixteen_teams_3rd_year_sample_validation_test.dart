import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/official_class_list_parser.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:excel/excel.dart' as xl;

void main() {
  const baseDir = '../sample_file/16_Teams_3rd_Year/1st Sem';

  group('16 Teams 3rd Year PIT Suite Validation', () {
    test('validates student import CSV (64 students, 3rd Year)', () {
      final file = File('$baseDir/USer/students_3rd_year_by_year_level.csv');
      expect(file.existsSync(), isTrue);

      final result = parseOfficialClassListCsv(file.readAsStringSync());
      expect(result.students, hasLength(64));
      expect(result.metadata['school_year'], '2026-2027');
      expect(result.metadata['semester'], '1st Semester');

      for (var i = 0; i < 64; i++) {
        final expectedId = '${3001 + i}';
        final student = result.students[i];
        expect(student['id_number'], expectedId);
        expect(student['year_level'], '3rd Year');
        expect(student['email'], '$expectedId@ustp.edu.ph');
        expect(student['first_name'], isNotEmpty);
        expect(student['last_name'], isNotEmpty);
      }
    });

    test('validates student import XLSX (64 students, 3rd Year)', () {
      final file = File('$baseDir/USer/students_3rd_year_by_year_level.xlsx');
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final result = parseOfficialClassListXlsx(bytes);
      expect(result.students, hasLength(64));

      for (var i = 0; i < 64; i++) {
        final expectedId = '${3001 + i}';
        final student = result.students[i];
        expect(student['id_number'], expectedId);
        expect(student['year_level'], '3rd Year');
      }
    });

    test('validates team roster Excel (16 teams: 3A One System, 3B Different Systems)', () {
      final file = File('$baseDir/team/Team16roster.xlsx');
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final excel = xl.Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first;

      // Expand spanned items as student_teams_screen.dart does
      for (final span in sheet.spannedItems) {
        final parts = span.split(':');
        if (parts.length != 2) continue;
        final start = xl.CellIndex.indexByString(parts[0]);
        final end = xl.CellIndex.indexByString(parts[1]);
        final startVal = sheet.cell(start).value;
        if (startVal == null) continue;
        final minR = start.rowIndex < end.rowIndex ? start.rowIndex : end.rowIndex;
        final maxR = start.rowIndex > end.rowIndex ? start.rowIndex : end.rowIndex;
        final minC = start.columnIndex < end.columnIndex ? start.columnIndex : end.columnIndex;
        final maxC = start.columnIndex > end.columnIndex ? start.columnIndex : end.columnIndex;
        for (var r = minR; r <= maxR; r++) {
          for (var c = minC; c <= maxC; c++) {
            if (r == start.rowIndex && c == start.columnIndex) continue;
            sheet.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), startVal);
          }
        }
      }

      final buffer = StringBuffer();
      for (final row in sheet.rows) {
        final line = row.map((cell) {
          final val = cell?.value;
          if (val == null) return '';
          String text = '';
          if (val is xl.TextCellValue) {
            text = (val.value.text ?? '').trim();
          } else if (val is xl.IntCellValue) {
            text = val.value.toString();
          } else {
            text = val.toString().trim();
          }
          if (text.contains(',') || text.contains('"') || text.contains('\n')) {
            return '"${text.replaceAll('"', '""')}"';
          }
          return text;
        }).join(',');
        if (line.replaceAll(',', '').trim().isNotEmpty) {
          buffer.writeln(line);
        }
      }

      final result = parseTeamBulkCsv(buffer.toString());
      expect(result.rows, hasLength(16));
      expect(result.section, contains('BSIT-3A'));
      expect(result.section, contains('BSIT-3B'));
      expect(result.systemName, 'Smart Agro-Industrial IoT & Sustainable Supply Platform');
      expect(result.projectManager, 'Gabriel Navarro');

      // 3A teams
      final sec3A = result.rows.where((r) => r['section'] == 'BSIT-3A').toList();
      final sec3B = result.rows.where((r) => r['section'] == 'BSIT-3B').toList();
      expect(sec3A, hasLength(8));
      expect(sec3B, hasLength(8));

      // 3A teams should have system_name and project_manager
      for (final team in sec3A) {
        expect(team['system_name'], 'Smart Agro-Industrial IoT & Sustainable Supply Platform');
        expect(team['project_manager'], 'Gabriel Navarro');
        expect(team['member_ids'], hasLength(4));
        expect(team['project_title'], contains('Module'));
      }

      // 3B teams should NOT have system_name
      for (final team in sec3B) {
        expect(team.containsKey('system_name'), isFalse);
        expect(team['member_ids'], hasLength(4));
        expect(team['project_title'], isNotEmpty);
      }
    });

    test('validates team roster sequential combined CSV (16 teams)', () {
      final file = File('$baseDir/team/team_roster_combined_3A_and_3B.csv');
      expect(file.existsSync(), isTrue);

      final result = parseTeamBulkCsv(file.readAsStringSync());
      expect(result.rows, hasLength(16));
      final sec3A = result.rows.where((r) => r['section'] == 'BSIT-3A').toList();
      final sec3B = result.rows.where((r) => r['section'] == 'BSIT-3B').toList();
      expect(sec3A, hasLength(8));
      expect(sec3B, hasLength(8));
    });

    test('validates defense schedule CSV (16 slots, zero adviser conflict)', () {
      final file = File('$baseDir/schedule/defense_schedule_import.csv');
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final parsed = parseScheduleImportFile(bytes: bytes, filename: 'defense_schedule_import.csv');
      expect(parsed.rows, hasLength(16));
      expect(parsed.stage, 'PIT Capstone Defense');
      expect(parsed.date, 'Oct 23 2026');
      expect(parsed.room, 'Room 302');

      for (final row in parsed.rows) {
        expect(row.parseIssues, isEmpty);
        expect(row.chair, isNotEmpty);
        expect(row.panelMembers, hasLength(3));
        expect(row.adviser, isNotEmpty);

        // Ethical rule: Adviser must never be chair or panelist
        expect(row.chair, isNot(equals(row.adviser)));
        expect(row.panelMembers, isNot(contains(row.adviser)));
      }
    });

    test('validates defense schedule XLSX (16 slots)', () {
      final file = File('$baseDir/schedule/defense_schedule_import.xlsx');
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final parsed = parseScheduleImportFile(bytes: bytes, filename: 'defense_schedule_import.xlsx');
      expect(parsed.rows, hasLength(16));
      expect(parsed.stage, 'PIT Capstone Defense');
      expect(parsed.date, 'Oct 23 2026');
      expect(parsed.room, 'Room 302');
    });
  });
}
