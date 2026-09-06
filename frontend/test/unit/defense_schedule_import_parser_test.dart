import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';

void main() {
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
  });
}

