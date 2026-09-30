import 'dart:typed_data';

import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/export/defense_schedule_excel_generator.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final isCapstone in [true, false]) {
    final scope = isCapstone ? 'Capstone' : 'PIT';

    test('$scope workbook preserves the proposed timetable layout', () {
      final workbook = Excel.decodeBytes(
        generateDefenseScheduleExcelBytes(isCapstone: isCapstone),
      );
      expect(workbook.tables.keys, ['Defense Schedule']);
      final sheet = workbook['Defense Schedule'];
      final lastColumn = isCapstone ? 'L' : 'K';
      expect(sheet.maxRows, 10);
      expect(sheet.maxColumns, isCapstone ? 12 : 11);
      expect(
        sheet.rows
            .take(2)
            .every((row) => row.every((cell) => cell?.value == null)),
        isTrue,
        reason: 'The first two rows provide top spacing.',
      );
      expect(
        sheet.rows.every(
          (row) => row.take(3).every((cell) => cell?.value == null),
        ),
        isTrue,
        reason: 'Columns A-C remain blank to inset the table.',
      );
      expect(
        sheet.spannedItems,
        unorderedEquals([
          'D3:${lastColumn}3',
          'D4:${lastColumn}4',
          'D5:${lastColumn}5',
          'G7:G10',
          if (isCapstone) 'L7:L10',
        ]),
      );
      expect(sheet.cell(CellIndex.indexByString('D6')).value.toString(), '#');
      expect(
        sheet.cell(CellIndex.indexByString('K6')).value.toString(),
        'Panel Member 3',
      );
      expect(
        sheet.cell(CellIndex.indexByString('G7')).value.toString(),
        'Prof. Alex Santos',
      );
      // The Excel decoder drops alignment and merged-cell styles. Check the
      // retained body styles here and merged geometry/import behavior separately.
      final bodyStyle = sheet.cell(CellIndex.indexByString('F8')).cellStyle!;
      expect(bodyStyle.topBorder.borderStyle, BorderStyle.Thin);
      expect(bodyStyle.bottomBorder.borderStyle, BorderStyle.Thin);
      expect(bodyStyle.leftBorder.borderStyle, BorderStyle.Thin);
      expect(bodyStyle.rightBorder.borderStyle, BorderStyle.Thin);
      expect(bodyStyle.fontFamily, 'Calibri');
      expect(bodyStyle.fontSize, 11);
      expect(bodyStyle.isBold, isFalse);
      expect(sheet.getColumnWidth(10), greaterThanOrEqualTo(20));
    });

    test('$scope template imports all four slots and merged metadata', () {
      final result = parseScheduleImportFile(
        bytes: Uint8List.fromList(
          generateDefenseScheduleExcelBytes(isCapstone: isCapstone),
        ),
        filename: 'schedule.xlsx',
      );
      expect(
        result.stage,
        isCapstone ? 'Concept Proposal' : 'PIT Capstone Defense',
      );
      expect(result.date, isCapstone ? '6/18/2026' : '5/18/2026');
      expect(result.room, isCapstone ? 'Room 301' : 'Smart Room');
      expect(result.rows, hasLength(4));
      expect(result.rows.map((row) => row.sheetRow), [7, 8, 9, 10]);
      expect(
        result.rows.map((row) => row.teamName),
        isCapstone
            ? ['Team Apex', 'Team Horizon', 'Team Nexus', 'Team Pulse']
            : [
                'Team SkyLedger',
                'Team BioPulse',
                'Team SafeCity',
                'Team CodeLearners',
              ],
      );
      for (final row in result.rows) {
        expect(row.adviser, 'Prof. Alex Santos');
        expect(row.documenter, isCapstone ? 'Engr. Mark Mendoza' : '');
        expect(row.stage, result.stage);
        expect(row.date, result.date);
        expect(row.room, result.room);
        expect(row.panelMembers, hasLength(3));
        expect(row.slotDuration, 60);
      }
      expect(result.rows.map((row) => row.time), [
        '8:00 - 9:00',
        '9:00 - 10:00',
        '10:00 - 11:00',
        '11:00 - 12:00',
      ]);
      expect(
        result.rows.map((row) => row.chair),
        isCapstone
            ? [
                'Dr. Alan Turing',
                'Dr. Alan Turing',
                'Dr. Maria Santos',
                'Dr. Maria Santos',
              ]
            : ['Suarez', 'Suarez', 'Tan', 'Tan'],
      );
      expect(
        result.rows.first.panelMembers,
        isCapstone
            ? ['Prof. Ada Lovelace', 'Dr. Grace Hopper', 'Prof. Claude Shannon']
            : ['Beltran', 'Corpuz', 'Villanueva'],
      );
      expect(
        result.rows.last.panelMembers,
        isCapstone
            ? ['Prof. Robert Taylor', 'Dr. Grace Miller', 'Engr. Alan Cruz']
            : ['Reyes', 'Cruz', 'Santos'],
      );
    });
  }
}
