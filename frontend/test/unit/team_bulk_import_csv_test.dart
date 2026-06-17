import 'package:flutter_test/flutter_test.dart';
import 'package:user/utils/team_bulk_import_csv.dart';

void main() {
  group('parseTeamBulkCsv', () {
    test('parses valid capstone CSV rows', () {
      const csv = '''
team_name,project_title,year_level,member_ids,leader_id,adviser_id
Team Alpha,Project A,3rd Year,101|102,101,201
''';

      final result = parseTeamBulkCsv(csv);

      expect(result.rows, hasLength(1));
      expect(result.rows.first['team_name'], 'Team Alpha');
      expect(result.rows.first['project_title'], 'Project A');
      expect(result.rows.first['year_level'], '3rd Year');
      expect(result.rows.first['member_ids'], ['101', '102']);
      expect(result.rows.first['leader_id'], '101');
    });

    test('returns empty list when headers are invalid', () {
      expect(parseTeamBulkCsv('foo,bar\n1,2').rows, isEmpty);
    });

    test('parses client multi-row template and collapses teams correctly', () {
      const csv = '''
Team Name,Capstone Project,Adviser,Team Members
TechVision,Eventify,RAY AN J. QUIÑON,"DOMINGUEZ, Noel R."
,,,"DAGO-OC, Evan John S."
,,,"PINGKIAN, El Jane"
,,,"DIU, Sciemon Jed"
Techpro,Campus Tutoring to FMCP,RAY AN J. QUIÑON,"CABANTAC, John Mike B."
''';

      final result = parseTeamBulkCsv(csv);

      expect(result.rows, hasLength(2));
      expect(result.rows[0]['team_name'], 'TechVision');
      expect(result.rows[0]['project_title'], 'Eventify');
      expect(result.rows[0]['adviser_id'], 'RAY AN J. QUIÑON');
      expect(result.rows[0]['member_ids'], [
        'DOMINGUEZ, Noel R.',
        'DAGO-OC, Evan John S.',
        'PINGKIAN, El Jane',
        'DIU, Sciemon Jed',
      ]);
      expect(result.rows[0]['leader_id'], 'DOMINGUEZ, Noel R.');

      expect(result.rows[1]['team_name'], 'Techpro');
      expect(result.rows[1]['project_title'], 'Campus Tutoring to FMCP');
      expect(result.rows[1]['adviser_id'], 'RAY AN J. QUIÑON');
      expect(result.rows[1]['member_ids'], ['CABANTAC, John Mike B.']);
      expect(result.rows[1]['leader_id'], 'CABANTAC, John Mike B.');
    });
  });

  group('rowsToTeamCsv', () {
    test('round-trips core fields', () {
      final csv = rowsToTeamCsv(
        [
          {
            'team_name': 'Team Beta',
            'project_title': 'Beta Project',
            'year_level': '4th Year',
            'member_ids': [1, 2],
            'leader_id': 1,
            'adviser_id': 9,
          },
        ],
        isCapstoneAdmin: true,
      );

      expect(csv, contains('Team Name,Capstone Project'));
      expect(csv, contains('Team Beta'));
      expect(csv, contains('1'));
      expect(csv, contains('2'));
    });
  });

  group('parseTeamBulkCsvWithContext', () {
    test('applies PIT level for pit lead context', () {
      const csv = '''
team_name,project_title,year_level,member_ids,leader_id,adviser_id
Team PIT,Title,3rd Year,101,101,
''';

      final result = parseTeamBulkCsvWithContext(
        csv,
        isCapstoneAdmin: false,
        pitLeadYear: '3rd Year',
      );

      expect(result.rows.first['level'], '3rd Year PIT');
      expect(result.rows.first.containsKey('adviser_id'), isTrue);
    });

    test('PIT header omits adviser column', () {
      final csv = rowsToTeamCsv(
        [
          {
            'team_name': 'Team PIT',
            'project_title': 'PIT Project',
            'member_ids': ['101', '102'],
            'leader_id': '101',
          },
        ],
        isCapstoneAdmin: false,
      );

      expect(csv.startsWith(teamBulkImportHeaderPit), isTrue);
      expect(csv.contains('Adviser'), isFalse);
      expect(csv.contains('adviser_id'), isFalse);
    });

    test('does not set level for capstone admin context', () {
      const csv = '''
team_name,project_title,year_level,member_ids,leader_id,adviser_id
Team Cap,Title,3rd Year,101,101,
''';

      final result = parseTeamBulkCsvWithContext(
        csv,
        isCapstoneAdmin: true,
        pitLeadYear: '3rd Year',
      );

      expect(result.rows.first.containsKey('level'), isFalse);
    });
  });

  group('sampleTeamCsvForYear', () {
    test('each year level has one team with four members', () {
      for (final year in teamSampleYearLevels) {
        final result = parseTeamBulkCsv(sampleTeamCsvForYear(
          year,
          isCapstoneAdmin: true,
        ));
        expect(result.rows, hasLength(1), reason: year);
        expect(result.rows.first['member_ids'], hasLength(4));
      }
    });

    test('PIT export strips year_level and adviser columns', () {
      final csv = sampleTeamCsvForYear('2nd Year', isCapstoneAdmin: false);
      expect(csv.startsWith(teamBulkImportHeaderPit), isTrue);
      expect(csv.contains('Year Level'), isFalse);
      expect(csv.contains('year_level'), isFalse);
    });
  });

  group('trimRowsAfterImport', () {
    test('removes imported row numbers', () {
      final rows = [
        {'team_name': 'A'},
        {'team_name': 'B'},
        {'team_name': 'C'},
      ];

      final kept = trimRowsAfterImport(rows: rows, importedRows: [2]);

      expect(kept, hasLength(2));
      expect(kept.map((r) => r['team_name']).toList(), ['A', 'C']);
    });
  });
}
