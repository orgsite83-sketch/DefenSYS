import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';

void main() {
  test('instructor preambles and divider rows retain their role', () {
    final result = parseTeamBulkCsv('''
Section,BSIT-1A
INSTRUCTOR: Eduardo Padilla
Team Name,PIT Project,Team Members
Team DevCraft,Campus Directory,Liam Liwanag
,,Chloe Marquez
INSTRUCTOR,Ricardo Fontanilla
Team Next,Library Finder,Andrei Catapang
''');
    expect(result.rows[0]['instructor_name'], 'Eduardo Padilla');
    expect(result.rows[1]['instructor_name'], 'Ricardo Fontanilla');
    expect(result.rows.every((row) => !row.containsKey('adviser_name')), isTrue);
  });

  test('instructor and adviser columns remain distinct', () {
    final result = parseTeamBulkCsv('''
Team Name,PIT Project,Section,Instructor,Adviser,Team Members
Team DevCraft,Campus Directory,BSIT-1A,Eduardo Padilla,Ada Lovelace,Liam Liwanag
''');
    expect(result.rows.single['instructor_name'], 'Eduardo Padilla');
    expect(result.rows.single['adviser_name'], 'Ada Lovelace');
    final legacy = parseTeamBulkCsv('''
team_name,project_title,member_ids,leader_id,section,instructor_name
Team DevCraft,Campus Directory,1065|1066,1065,BSIT-1A,Eduardo Padilla
''');
    expect(legacy.rows.single['instructor_name'], 'Eduardo Padilla');
  });

  test('section dividers do not carry an earlier instructor forward', () {
    final result = parseTeamBulkCsv('''
Section,BSIT-1A
Instructor,Eduardo Padilla
Team Name,PIT Project,Team Members
Team One,Campus Directory,Liam Liwanag
Section,BSIT-1B
Team Two,Library Finder,Andrei Catapang
''');
    expect(result.rows[0]['instructor_name'], 'Eduardo Padilla');
    expect(result.rows[1].containsKey('instructor_name'), isFalse);
  });

  test('PIT CSV export preserves section and instructor on round trip', () {
    final rows = [
      {
        'team_name': 'Team DevCraft',
        'project_title': 'Campus Directory',
        'section': 'BSIT-1A',
        'instructor_name': 'Eduardo Padilla',
        'member_ids': ['Liam Liwanag', 'Chloe Marquez'],
        'leader_id': 'Liam Liwanag',
      },
    ];
    final parsed = parseTeamBulkCsv(rowsToTeamCsv(rows, isCapstoneAdmin: false));
    expect(parsed.rows.single['instructor_name'], 'Eduardo Padilla');
    expect(parsed.rows.single['section'], 'BSIT-1A');
    expect(parsed.rows.single['member_ids'], rows.single['member_ids']);
  });

  test('reported 16-team first-year sample preserves both section instructors', () {
    final file = File('../Defensys_sample files/sample_file/16_Teams_1st_Year_Set_2/1st Sem/team/team_roster_combined_1A_and_1B.csv');
    final result = parseTeamBulkCsv(file.readAsStringSync());
    expect(result.rows, hasLength(16));
    expect(result.rows.map((r) => r['instructor_name']).toSet(), {
      'Eduardo Padilla',
      'Florencia Dela Torre',
      'Arsenio Macasaet',
      'Teresita Buenaventura',
    });
    for (final instructor in result.rows.map((r) => r['instructor_name']).toSet()) {
      expect(result.rows.where((r) => r['instructor_name'] == instructor), hasLength(4));
    }
    expect(result.rows.every((r) => !r.containsKey('adviser_name')), isTrue);
  });
}
