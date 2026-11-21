import 'dart:io';
import 'dart:typed_data';

import 'package:defensys/utils/import/defense_schedule_import_parser.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:flutter_test/flutter_test.dart';

// Produced by the real report API on Django's isolated test database:
// DEFENSYS_EXPORT_TEMPLATE_FIXTURES=1 manage.py test reports.test_import_template_exports --keepdb
Uint8List _fixture(String name) =>
    File('test/fixtures/import_template_exports/$name').readAsBytesSync();

void main() {
  test(
    'exported Capstone roster imports all members and keeps the leader first',
    () {
      final imported = parseTeamBulkCsv(
        teamXlsxToCsv(_fixture('capstone-teams.xlsx')),
      );
      expect(imported.rows, hasLength(1));
      final team = imported.rows.single;
      expect(team['team_name'], 'Team EcoSort');
      expect(team['project_title'], 'AI-Powered Waste Sorting');
      expect(team['section'], 'BSIT-4B');
      expect(team['adviser_name'], 'Renato Villanueva');
      expect(team['member_ids'], [
        'Kenneth DIZON',
        'Camille RAMOS',
        'Mark VALENZUELA',
        'Princess LOPEZ',
      ]);
      expect(team['leader_id'], 'Kenneth DIZON');
    },
  );

  test(
    'exported shared PIT roster retains section metadata and instructor',
    () {
      final team = parseTeamBulkCsv(
        teamXlsxToCsv(_fixture('pit-shared-teams.xlsx')),
      ).rows.single;
      expect(team['team_name'], 'Team PIT');
      expect(team['system_name'], 'Societree');
      expect(team['project_manager'], 'Princess LOPEZ');
      expect(team['project_kind'], 'module');
      expect(team['instructor_name'], 'Ana Peña');
      expect(team['section'], 'BSIT-2A');
      expect(team['leader_id'], 'Princess LOPEZ');
    },
  );

  test(
    'mixed workbook imports every roster sheet and ignores the signature sheet',
    () {
      final rows = parseTeamBulkCsv(
        teamXlsxToCsv(_fixture('mixed-teams.xlsx')),
      ).rows;
      expect(rows, hasLength(2));
      expect(rows.map((row) => row['team_name']), ['Team EcoSort', 'Team PIT']);
      expect(rows.map((row) => row['group_key']).toSet(), hasLength(2));
      expect(rows.last['instructor_name'], 'Ana Peña');
      expect(rows.first['member_ids'], hasLength(4));
    },
  );

  test(
    'exported Capstone timetable retains the chair, panel members and documenter',
    () {
      final parsed = parseScheduleImportFile(
        bytes: _fixture('capstone-schedules.xlsx'),
        filename: 'schedule.xlsx',
      );
      expect(parsed.rows, hasLength(1));
      final row = parsed.rows.single;
      expect(row.teamName, 'Team EcoSort');
      expect(row.stage, 'Concept Proposal');
      expect(row.date, contains('2031'));
      expect(row.room, 'Room 301');
      expect(row.adviser, 'Renato Villanueva');
      expect(row.chair, 'Panel Person 2');
      expect(row.panelMembers, [
        'Panel Person 0',
        'Panel Person 1',
        'Panel Person 3',
      ]);
      expect(row.documenter, 'Mia Cruz');
      expect(row.time, '11:30 AM - 12:30 PM');
      expect(row.parseIssues, isEmpty);
    },
  );

  test('exported PIT timetable retains the instructor with no documenter', () {
    final row = parseScheduleImportFile(
      bytes: _fixture('pit-schedules.xlsx'),
      filename: 'schedule.xlsx',
    ).rows.single;
    expect(row.teamName, 'Team PIT');
    expect(row.instructor, 'Ana Peña');
    expect(row.adviser, isEmpty);
    expect(row.documenter, isEmpty);
    expect(row.stage, 'PIT Capstone Defense');
    expect(row.parseIssues, isEmpty);
  });

  test('mixed schedules import both scopes and ignore optional signatures', () {
    final rows = parseScheduleImportFile(
      bytes: _fixture('mixed-schedules.xlsx'),
      filename: 'schedule.xlsx',
    ).rows;
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.teamName), ['Team EcoSort', 'Team PIT']);
    expect(rows.first.documenter, 'Mia Cruz');
    expect(rows.last.instructor, 'Ana Peña');
    expect(rows.last.stage, 'PIT Capstone Defense');
    expect(rows.every((row) => row.parseIssues.isEmpty), isTrue);
  });

  test(
    'multiple timetable blocks preserve dates, rooms and merged staff boundaries',
    () {
      final rows = parseScheduleImportFile(
        bytes: _fixture('multi-day-schedules.xlsx'),
        filename: 'schedule.xlsx',
      ).rows;
      expect(rows, hasLength(3));
      expect(rows.map((row) => row.room), ['Room 301', 'Room 301', 'Room 302']);
      expect(rows.map((row) => row.date).toSet(), hasLength(2));
      expect(rows.every((row) => row.adviser == 'Renato Villanueva'), isTrue);
      expect(rows.every((row) => row.documenter == 'Mia Cruz'), isTrue);
      expect(rows.every((row) => row.parseIssues.isEmpty), isTrue);
    },
  );
}
