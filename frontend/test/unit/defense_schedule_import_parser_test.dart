import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:excel/excel.dart';

void main() {
  group('schedule header safety', () {
    for (final alias in [
      'Chair',
      'Panel Chair',
      'Chair Panel',
      'Chairperson',
      'Panel Chairperson',
      'CHAIR-PANEL',
      ' Chair\nPanel ',
    ]) {
      test('recognizes "$alias" without treating it as a panel member', () {
        final parsed = parseScheduleImportMatrix([
          ['Time', 'Team Name', alias, 'Panel Member 1'],
          [
            '08:00-08:30',
            'Team SkyLedger',
            'Maricel Suarez',
            'Jonathan Beltran',
          ],
        ]);
        expect(parsed.rows.single.chair, 'Maricel Suarez');
        expect(parsed.rows.single.panelMembers, ['Jonathan Beltran']);
        expect(parsed.rows.single.parseIssues, isEmpty);
      });
    }

    test('detects headers using the same aliases as column extraction', () {
      final parsed = parseScheduleImportMatrix([
        ['Team', 'Chair Panel'],
        ['Team SkyLedger', 'Maricel Suarez'],
      ]);
      expect(parsed.rows.single.chair, 'Maricel Suarez');
    });

    test(
      'suggests typos without mapping unknown columns or losing diagnostics in drafts',
      () {
        final parsed = parseScheduleImportMatrix([
          ['Time', 'Team Name', 'Chiar Panel', 'Panel Member 1'],
          [
            '08:00-08:30',
            'Team SkyLedger',
            'Maricel Suarez',
            'Jonathan Beltran',
          ],
          ['08:30-09:00', 'Team BioPulse', '', 'Jonathan Beltran'],
        ]);
        for (final row in parsed.rows) {
          expect(row.chair, isEmpty);
          expect(row.parseIssues.single, contains('Chiar Panel'));
          expect(row.parseIssues.single, contains('Did you mean "Chair"?'));
          expect(row.copyWith().parseIssues, row.parseIssues);
        }
        final restored = ParsedScheduleImport.fromJson(parsed.toJson());
        expect(restored.rows.first.parseIssues, parsed.rows.first.parseIssues);
        final legacy = Map<String, dynamic>.from(parsed.rows.first.toJson())
          ..remove('parse_issues');
        expect(ParsedScheduleImportRow.fromJson(legacy).parseIssues, isEmpty);
      },
    );

    test(
      'rejects conflicting aliases instead of taking the first chair column',
      () {
        final parsed = parseScheduleImportMatrix([
          ['Time', 'Team Name', 'Chair', 'Chair Panel', 'Panel Member 1'],
          [
            '08:00-08:30',
            'Team SkyLedger',
            'Maricel Suarez',
            'Eduardo Padilla',
            'Jonathan Beltran',
          ],
        ]);
        expect(parsed.rows.single.chair, isEmpty);
        expect(
          parsed.rows.single.parseIssues.single,
          contains('multiple "Chair" columns (3, 4)'),
        );
      },
    );

    test('resets header issues between repeated tables', () {
      final parsed = parseScheduleImportMatrix([
        ['Time', 'Team Name', 'Chiar Panel'],
        ['08:00-08:30', 'Team SkyLedger', 'Maricel Suarez'],
        [],
        ['Time', 'Team Name', 'Chair Panel'],
        ['08:30-09:00', 'Team BioPulse', 'Eduardo Padilla'],
      ]);
      expect(parsed.rows.first.parseIssues, isNotEmpty);
      expect(parsed.rows.last.parseIssues, isEmpty);
      expect(parsed.rows.last.chair, 'Eduardo Padilla');
    });

    test(
      'flags unnamed data while allowing row numbering and empty spacer columns',
      () {
        final parsed = parseScheduleImportMatrix([
          ['#', 'Time', 'Team Name', 'Chair', '', ''],
          [
            '1',
            '08:00-08:30',
            'Team SkyLedger',
            'Maricel Suarez',
            '',
            'Eduardo Padilla',
          ],
        ]);
        expect(
          parsed.rows.single.parseIssues.single,
          contains('Unnamed column 6'),
        );
      },
    );

    test(
      'recognizes Chair Panel in XLSX with merged cells and multiple days',
      () {
        final workbook = Excel.createExcel();
        final sheet = workbook['Sheet1'];
        final matrix = [
          ['Concept Proposal'],
          ['Oct 20 2026'],
          ['Room 301'],
          [
            'Time',
            'Team Name',
            'Adviser',
            'Chair Panel',
            'Panel Member 1',
            'Documenter',
          ],
          [
            '08:00-08:30',
            'Team SkyLedger',
            'Ricardo Fontanilla',
            'Maricel Suarez',
            'Jonathan Beltran',
            'Cecilia Magbanua',
          ],
          [
            '08:30-09:00',
            'Team BioPulse',
            '',
            'Maricel Suarez',
            'Jonathan Beltran',
            '',
          ],
          [],
          ['Concept Proposal'],
          ['Oct 21 2026'],
          ['Room 301'],
          [
            'Time',
            'Team Name',
            'Adviser',
            'Chair Panel',
            'Panel Member 1',
            'Documenter',
          ],
          [
            '13:00-13:30',
            'Team MedRecord',
            'Analiza Corpuz',
            'Eduardo Padilla',
            'Jonathan Beltran',
            'Cecilia Magbanua',
          ],
        ];
        for (final row in matrix) {
          sheet.appendRow(row.map((value) => TextCellValue(value)).toList());
        }
        sheet.merge(
          CellIndex.indexByString('C5'),
          CellIndex.indexByString('C6'),
        );
        sheet.merge(
          CellIndex.indexByString('F5'),
          CellIndex.indexByString('F6'),
        );
        final parsed = parseScheduleImportFile(
          bytes: Uint8List.fromList(workbook.encode()!),
          filename: 'chair_panel.xlsx',
        );
        expect(parsed.rows, hasLength(3));
        expect(parsed.rows.map((row) => row.chair), [
          'Maricel Suarez',
          'Maricel Suarez',
          'Eduardo Padilla',
        ]);
        expect(parsed.rows[1].adviser, 'Ricardo Fontanilla');
        expect(parsed.rows[1].documenter, 'Cecilia Magbanua');
        expect(parsed.rows.last.date, 'Oct 21 2026');
        expect(parsed.rows.every((row) => row.parseIssues.isEmpty), isTrue);
      },
    );
  });
  group('parseScheduleImportFile', () {
    test('parses official client format with top 3 rows and multi-row members', () {
      const csv = '''
REDEFENSE - Capstone Project and Research 1,,,,,,,,,
"May 18, 2026",,,,,,,,,
SMART ROOM,,,,,,,,,
Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Panel Member 2,Panel Member 3,Documenter
9:00AM-9:30AM,Team SkyLedger,Alumni Career Tracker,"Ricardo Fontanilla","VILLAR, Marcus",Suarez,Beltran,Corpuz,Villanueva,Magbanua
,,,,"ONG, Patricia",,,,,
,,,,"SALAZAR, Ethan",,,,,
,,,,"CASTILLO, Zoe",,,,,
9:30AM-10:00AM,Team CodeLearners,Smart Campus Navigator,"Ricardo Fontanilla","REYES, Carlos",Suarez,Beltran,Corpuz,Villanueva,Magbanua
,,,,"SANTOS, Maria",,,,,
,,,,"DELA CRUZ, Juan",,,,,
''';

      final bytes = Uint8List.fromList(utf8.encode(csv));
      final result = parseScheduleImportFile(bytes: bytes, filename: 'test.csv');

      expect(result.stage, equals('REDEFENSE - Capstone Project and Research 1'));
      expect(result.date, equals('May 18, 2026'));
      expect(result.room, equals('SMART ROOM'));
      expect(result.isRedefense, isTrue);

      expect(result.rows, hasLength(2));

      final row1 = result.rows[0];
      expect(row1.teamName, equals('Team SkyLedger'));
      expect(row1.projectTitle, equals('Alumni Career Tracker'));
      expect(row1.adviser, equals('Ricardo Fontanilla'));
      expect(row1.members, equals([
        'VILLAR, Marcus',
        'ONG, Patricia',
        'SALAZAR, Ethan',
        'CASTILLO, Zoe',
      ]));
      expect(row1.chair, equals('Suarez'));
      expect(row1.panelMembers, equals(['Beltran', 'Corpuz', 'Villanueva']));
      expect(row1.documenter, equals('Magbanua'));

      final row2 = result.rows[1];
      expect(row2.teamName, equals('Team CodeLearners'));
      expect(row2.projectTitle, equals('Smart Campus Navigator'));
      expect(row2.members, equals([
        'REYES, Carlos',
        'SANTOS, Maria',
        'DELA CRUZ, Juan',
      ]));
    });

    test('parses old template format with metadata columns', () {
      const csv = '''
Stage,Date,Room,Time,Team Name,Capstone Project,Adviser,Chair,Panel Member 1,Panel Member 2,Panel Member 3,Documenter,Team Members
Concept Proposal,2026-06-18,Room 301,9:00AM-9:30AM,Team Site Avengers,DefenSYS,206,207,208,209,210,211,4081
,,,,,,,,,,,,4082
''';

      final bytes = Uint8List.fromList(utf8.encode(csv));
      final result = parseScheduleImportFile(bytes: bytes, filename: 'test.csv');

      expect(result.rows, hasLength(1));
      final row = result.rows.first;
      expect(row.stage, equals('Concept Proposal'));
      expect(row.date, equals('2026-06-18'));
      expect(row.room, equals('Room 301'));
      expect(row.teamName, equals('Team Site Avengers'));
      expect(row.members, equals(['4081', '4082']));
    });

    test('parses multi-day schedule with intermediate date headers and repeated table headers', () {
      const csv = '''
Concept Proposal,,,,,,,
6/18/2026,,,,,,,
Room 301,,,,,,,
Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Documenter
9:00AM-9:30AM,Team SkyLedger,Alumni Career Tracker,Ricardo Fontanilla,Marcus Villar,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
,,,,Patricia Ong,,,
,,,,Ethan Salazar,,,
,,,,Zoe Castillo,,,
9:30AM-10:00AM,Team ByteForce,AI Attendance,Ricardo Fontanilla,Ryan Torres,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
10:00AM-10:30AM,Team NexGen,Campus Lost,Ricardo Fontanilla,Carlos Bautista,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
,,,,Sophia Santos,,,

6/19/2026,,,2026,,,,
Room 301,,,,,,,
Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Documenter
9:00AM-9:30AM,Team Site Avengers,DefenSYS,Ricardo Fontanilla,Carlos Reyes,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
,,,,Maria Santos,,,
9:30AM-10:00AM,Team ByteForce,AI Attendance,Ricardo Fontanilla,Jose Garcia,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
10:00AM-10:30AM,Team NexGen,Campus Lost,Ricardo Fontanilla,Diego Ramos,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
''';

      final bytes = Uint8List.fromList(utf8.encode(csv));
      final result = parseScheduleImportFile(bytes: bytes, filename: 'test.csv');

      expect(result.rows, hasLength(6));
      expect(result.rows[0].date, equals('6/18/2026'));
      expect(result.rows[0].teamName, equals('Team SkyLedger'));
      expect(result.rows[1].date, equals('6/18/2026'));
      expect(result.rows[1].teamName, equals('Team ByteForce'));
      expect(result.rows[2].date, equals('6/18/2026'));
      expect(result.rows[2].teamName, equals('Team NexGen'));

      expect(result.rows[3].date, equals('6/19/2026'));
      expect(result.rows[3].teamName, equals('Team Site Avengers'));
      expect(result.rows[4].date, equals('6/19/2026'));
      expect(result.rows[4].teamName, equals('Team ByteForce'));
      expect(result.rows[5].date, equals('6/19/2026'));
      expect(result.rows[5].teamName, equals('Team NexGen'));
    });

    test('parses spreadsheet with coloqium in preamble row without hardcoded stage words', () {
      const csv = '''
coloqium,,,,,,,
6/18/2026,,,,,,,
Room 301,,,,,,,
Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Documenter
9:00AM-9:30AM,Team SkyLedger,Alumni Career Tracker,Ricardo Fontanilla,Marcus Villar,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
''';
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final result = parseScheduleImportFile(
        bytes: bytes,
        filename: 'schedule_import.csv',
        configuredStages: ['Concept Proposal', 'Project Proposal'],
      );

      expect(result.stage, equals('coloqium'));
      expect(result.date, equals('6/18/2026'));
      expect(result.room, equals('Room 301'));
      expect(result.rows, hasLength(1));
      expect(result.rows.first.stage, equals('coloqium'));
    });

    test('parses dynamic custom stage and preserves uppercase / caps lock in stage header', () {
      const csv = '''
FINAL ORAL EXAMINATION,,,,,,,
2026-07-20,,,,,,,
AVR 1,,,,,,,
Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Documenter
1:00PM-2:00PM,Team CyberShield,Threat Analytics,Ricardo Fontanilla,Alice Guo,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua
''';
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final result = parseScheduleImportFile(
        bytes: bytes,
        filename: 'oral_exam.csv',
        configuredStages: ['Final Oral Examination', 'Concept Proposal'],
      );

      expect(result.stage, equals('FINAL ORAL EXAMINATION'));
      expect(result.date, equals('2026-07-20'));
      expect(result.room, equals('AVR 1'));
      expect(result.rows.first.stage, equals('FINAL ORAL EXAMINATION'));
    });

    test('parses school defense schedule with DAY banner, merged adviser, and merged documenter', () {
      const csv = '''
DAY 4 - APRIL 25, 2026,,,,,,,,
#,Time,Team Name,Adviser,Panel Chair,Panel Member 1,Panel Member 2,Panel Member 3,Documenter
1,8:00 - 9:00,P3R,ARNEL F. MANGGA,Jubilee S. Daga-ang,Kilven Mark P. Badiang,Janice Ruiz - Ocampo,Io Rowan M. Borata,MARITES D. HABAGAT
2,9:00 - 10:00,Year4ward,,Jubilee S. Daga-ang,Kilven Mark P. Badiang,Janice Ruiz - Ocampo,Io Rowan M. Borata,
3,10:00 - 11:00,Aurea's Crew,JANICE RUIZ - OCAMPO,Janice Ruiz - Ocampo,Lutherly G. Bongcawel,Markony L. Undag,Kilven Mark P. Badiang,RICHARD C. PALER
4,11:00 - 12:00,Talk2Doc,,Janice Ruiz - Ocampo,Lutherly G. Bongcawel,Markony L. Undag,Kilven Mark P. Badiang,
''';
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final result = parseScheduleImportFile(
        bytes: bytes,
        filename: 'defense_schedule_day4.csv',
      );

      expect(result.date, equals('APRIL 25, 2026'));
      expect(result.rows, hasLength(4));

      // Row 1: P3R
      expect(result.rows[0].teamName, equals('P3R'));
      expect(result.rows[0].adviser, equals('ARNEL F. MANGGA'));
      expect(result.rows[0].chair, equals('Jubilee S. Daga-ang'));
      expect(result.rows[0].panelMembers, equals([
        'Kilven Mark P. Badiang',
        'Janice Ruiz - Ocampo',
        'Io Rowan M. Borata',
      ]));
      expect(result.rows[0].documenter, equals('MARITES D. HABAGAT'));

      // Row 2: Year4ward (inherited adviser & documenter, but own panel members)
      expect(result.rows[1].teamName, equals('Year4ward'));
      expect(result.rows[1].adviser, equals('ARNEL F. MANGGA'));
      expect(result.rows[1].chair, equals('Jubilee S. Daga-ang'));
      expect(result.rows[1].panelMembers, equals([
        'Kilven Mark P. Badiang',
        'Janice Ruiz - Ocampo',
        'Io Rowan M. Borata',
      ]));
      expect(result.rows[1].documenter, equals('MARITES D. HABAGAT'));

      // Row 3: Aurea's Crew (new adviser & documenter)
      expect(result.rows[2].teamName, equals("Aurea's Crew"));
      expect(result.rows[2].adviser, equals('JANICE RUIZ - OCAMPO'));
      expect(result.rows[2].chair, equals('Janice Ruiz - Ocampo'));
      expect(result.rows[2].panelMembers, equals([
        'Lutherly G. Bongcawel',
        'Markony L. Undag',
        'Kilven Mark P. Badiang',
      ]));
      expect(result.rows[2].documenter, equals('RICHARD C. PALER'));

      // Row 4: Talk2Doc (inherited adviser & documenter)
      expect(result.rows[3].teamName, equals('Talk2Doc'));
      expect(result.rows[3].adviser, equals('JANICE RUIZ - OCAMPO'));
      expect(result.rows[3].chair, equals('Janice Ruiz - Ocampo'));
      expect(result.rows[3].panelMembers, equals([
        'Lutherly G. Bongcawel',
        'Markony L. Undag',
        'Kilven Mark P. Badiang',
      ]));
      expect(result.rows[3].documenter, equals('RICHARD C. PALER'));
    });
  });
}

