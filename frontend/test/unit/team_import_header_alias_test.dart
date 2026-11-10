import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final header in [
    'Team',
    'Group',
    'Group Name',
    'group_name',
    ' TEAM : * ',
  ]) {
    test('recognizes $header with the school column order', () {
      final rows = parseTeamBulkCsv(
        'No.,$header,Adviser,Names,Capstone Project Title,Section\n'
        '1,CodeCrafters,Prof. Reyes,"REYES, Ana",Campus Records,BSIT-4D\n'
        ',,,"CRUZ, Ben",,\n'
        '2,SysIgnite,Prof. Santos,"LIM, Carla",Document Tracking,BSIT-4A',
      ).rows;
      expect(rows, hasLength(2));
      expect(rows.first['team_name'], 'CodeCrafters');
      expect(rows.first['member_ids'], ['REYES, Ana', 'CRUZ, Ben']);
      expect(rows.first['project_title'], 'Campus Records');
      expect(rows.first['adviser_name'], 'Prof. Reyes');
      expect(rows.last['section'], 'BSIT-4A');
    });
  }

  test('normalizes header whitespace including line breaks', () {
    final rows = parseTeamBulkCsv(
      '"Team\n Name",Project,"Team   Members"\n'
      'Orion,Campus Records,Ana Reyes',
    ).rows;
    expect(rows.single['team_name'], 'Orion');
    expect(rows.single['member_ids'], ['Ana Reyes']);
  });

  test('recognizes aliases across side-by-side tables', () {
    final rows = parseTeamBulkCsv(
      'Team,Names,Capstone Project Title,,Group Name,Names,Capstone Project Title\n'
      'Orion,Ana Reyes,Campus Records,,Vega,Ben Cruz,Library Portal',
    ).rows;
    expect(rows.map((row) => row['team_name']), ['Orion', 'Vega']);
    expect(rows.map((row) => row['project_title']), [
      'Campus Records',
      'Library Portal',
    ]);
  });

  test('skips repeated headers without skipping a team named Team', () {
    final rows = parseTeamBulkCsv(
      'Team,Names,Capstone Project Title\n'
      'Team,Ana Reyes,Campus Records\n'
      'Team,Names,Capstone Project Title\n'
      'Vega,Ben Cruz,Library Portal',
    ).rows;
    expect(rows.map((row) => row['team_name']), ['Team', 'Vega']);
    expect(rows.first['member_ids'], ['Ana Reyes']);
  });

  test('still requires both a team column and a roster member column', () {
    for (final csv in [
      'Team,Project\nOrion,Campus Records',
      'Names,Email\nAna Reyes,ana@example.com',
      'Team Manager,Names\nProf. Reyes,Ana Reyes',
    ]) {
      expect(parseTeamBulkCsv(csv).rows, isEmpty);
    }
  });

  test('team aliases in data do not create extra table blocks', () {
    final rows = parseTeamBulkCsv(
      'Team,Names,Project\n'
      'Orion,Ana Reyes,Group\n'
      'Vega,Ben Cruz,Team',
    ).rows;
    expect(rows.map((row) => row['team_name']), ['Orion', 'Vega']);
    expect(rows.map((row) => row['project_title']), ['Group', 'Team']);
  });
}
