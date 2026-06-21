import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:user/utils/defense_schedule_import_parser.dart';

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
  });
}
