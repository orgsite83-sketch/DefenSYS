import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/import/defense_schedule_import_parser.dart';

void main() {
  test(
    'vertical team and time merges retain member continuation without duplicate appointments',
    () {
      final book = Excel.createExcel();
      final sheet = book['Schedule'];
      for (final row in [
        ['Time', 'Team Name', 'Team Members', 'Chair'],
        ['08:00-09:00', 'Alpha', 'student-1', 'Chair A'],
        ['', '', 'student-2', ''],
      ]) {
        sheet.appendRow(row.map(TextCellValue.new).toList());
      }
      for (final range in ['A2:A3', 'B2:B3', 'D2:D3']) {
        final ends = range.split(':');
        sheet.merge(
          CellIndex.indexByString(ends[0]),
          CellIndex.indexByString(ends[1]),
        );
      }
      final parsed = parseScheduleImportFile(
        bytes: Uint8List.fromList(book.encode()!),
        filename: 'members.xlsx',
      );
      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.single.members, ['student-1', 'student-2']);
    },
  );

  test(
    'course heading, horizontal banners and vertical staff merges stay distinct',
    () {
      final book = Excel.createExcel();
      final sheet = book['Schedule'];
      final rows = [
        ['', 'BSIT CAPSTONE PROJECT and RESEARCH 2'],
        ['', 'PROJECT PROPOSAL SCHEDULE'],
        ['', 'November 9-14, 2026 | SMART Classroom'],
        [
          '',
          'Time',
          'Team Name',
          'Adviser',
          'Panel Chair',
          'Panel Member 1',
          'Documenter',
        ],
        ['', 'DAY 1 - November 9, 2026 - Monday'],
        [
          '',
          '8:00 - 9:30 AM',
          'Alpha',
          'Adviser A',
          'Chair A',
          'Panel A',
          'Documenter A',
        ],
        ['', '9:30 - 11:00 AM', 'Beta'],
        ['', '12:30 - 1:00 PM', 'LUNCH BREAK'],
        [
          '',
          '1:00 - 2:30 PM',
          'Gamma',
          'Adviser B',
          'Chair B',
          'Panel B',
          'Documenter B',
        ],
        ['', 'DAY 5 - November 14, 2026 - Saturday'],
        [
          '',
          '8:00 - 9:30 AM',
          'Delta',
          'Adviser C',
          'Chair C',
          'Panel C',
          'Documenter C',
        ],
        ['', '2:30 - 4:00 PM', 'RE-DEFENSE'],
        ['', '4:00 - 5:30 PM'],
      ];
      for (final row in rows) {
        sheet.appendRow(row.map(TextCellValue.new).toList());
      }
      for (final range in [
        'B1:G1',
        'B2:G2',
        'B3:G3',
        'B5:G5',
        'B10:G10',
        'C8:G8',
        'C12:G13',
        'D6:D7',
        'E6:E7',
        'F6:F7',
        'G6:G7',
      ]) {
        final ends = range.split(':');
        sheet.merge(
          CellIndex.indexByString(ends[0]),
          CellIndex.indexByString(ends[1]),
        );
      }
      final parsed = parseScheduleImportFile(
        bytes: Uint8List.fromList(book.encode()!),
        filename: 'schedule.xlsx',
        configuredStages: ['Project Proposal', 'Final Defense'],
      );
      expect(parsed.stage, 'PROJECT PROPOSAL SCHEDULE');
      expect(parsed.rows.map((r) => r.teamName), [
        'Alpha',
        'Beta',
        'Gamma',
        'Delta',
      ]);
      expect(parsed.rows[1].chair, 'Chair A');
      expect(parsed.rows[1].panelMembers, ['Panel A']);
      expect(parsed.rows[2].startTime, '13:00');
      expect(parsed.rows.last.date, 'November 14, 2026');
      expect(parsed.rows.every((r) => r.room == 'SMART Classroom'), isTrue);
      expect(parsed.rows.every((r) => r.stage == parsed.stage), isTrue);
      expect(parsed.isRedefense, isFalse);
    },
  );

  test('noon ranges and explicitly reversed times are handled safely', () {
    for (final entry in {
      '12:30 - 1:00 PM': ['12:30', '13:00'],
      '11:00 - 12:30 PM': ['11:00', '12:30'],
      '8:00 - 9:30 AM': ['08:00', '09:30'],
      '1:00 - 2:30 PM': ['13:00', '14:30'],
    }.entries) {
      final parsed = parseScheduleImportMatrix([
        ['Time', 'Team Name', 'Chair'],
        [entry.key, 'Alpha', 'Chair A'],
      ]);
      expect([
        parsed.rows.single.startTime,
        parsed.rows.single.endTime,
      ], entry.value);
    }
    final reversed = parseScheduleImportMatrix([
      ['Time', 'Team Name', 'Chair'],
      ['2:00 PM - 1:00 PM', 'Alpha', 'Chair A'],
    ]);
    expect(reversed.rows.single.parseIssues, isNotEmpty);
  });

  test(
    'course-only preamble and time-only rows do not manufacture assignments',
    () {
      final parsed = parseScheduleImportMatrix(
        [
          ['BSIT CAPSTONE PROJECT and RESEARCH 2'],
          ['Time', 'Team Name', 'Chair'],
          ['8:00 - 9:30 AM', 'Alpha', 'Chair A'],
          ['9:30 - 11:00 AM', '', ''],
        ],
        configuredStages: ['Project Proposal'],
      );
      expect(parsed.stage, isEmpty);
      expect(parsed.rows, hasLength(1));
    },
  );
}
