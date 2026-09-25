import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/team_bulk_import_csv.dart';

void main() {
  group('parseTeamBulkCsv', () {
    test('parses valid capstone CSV rows', () {
      const csv = '''
team_name,project_title,year_level,member_ids,leader_id,adviser_name
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
Team SkyLedger,Alumni Career Tracker,Ricardo Fontanilla,"VILLAR, Marcus"
,,,"ONG, Patricia"
,,,"SALAZAR, Ethan"
,,,"CASTILLO, Zoe"
Team CodeLearners,Smart Campus Navigator,Ricardo Fontanilla,"REYES, Carlos"
''';

      final result = parseTeamBulkCsv(csv);

      expect(result.rows, hasLength(2));
      expect(result.rows[0]['team_name'], 'Team SkyLedger');
      expect(result.rows[0]['project_title'], 'Alumni Career Tracker');
      expect(result.rows[0]['adviser_name'], 'Ricardo Fontanilla');
      expect(result.rows[0]['member_ids'], [
        'VILLAR, Marcus',
        'ONG, Patricia',
        'SALAZAR, Ethan',
        'CASTILLO, Zoe',
      ]);
      expect(result.rows[0]['leader_id'], 'VILLAR, Marcus');

      expect(result.rows[1]['team_name'], 'Team CodeLearners');
      expect(result.rows[1]['project_title'], 'Smart Campus Navigator');
      expect(result.rows[1]['adviser_name'], 'Ricardo Fontanilla');
      expect(result.rows[1]['member_ids'], ['REYES, Carlos']);
      expect(result.rows[1]['leader_id'], 'REYES, Carlos');
    });

    test('parses standard multi-row sheet with section column and multiple advisers per section', () {
      const csv = '''
Team Name,Capstone Project,Section,Adviser,Team Members
Team Alpha,Campus Navigation System,BSIT-4A,Prof. Alex Santos,"DELA CRUZ, Juan"
,,,,"SANTOS, Maria"
,,,,"REYES, Mark"
,,,,"GARCIA, Anna"
Team Beta,Automated Library Portal,BSIT-4A,Prof. Elena Ramos,"TORRES, Miguel"
,,,,"FLORES, Angela"
Team Gamma,Security Access System,BSIT-4B,Prof. Roberto Cruz,"RAMOS, Carlo"
''';

      final result = parseTeamBulkCsv(csv);

      expect(result.rows, hasLength(3));

      // Team Alpha in BSIT-4A with Prof. Alex Santos
      expect(result.rows[0]['team_name'], 'Team Alpha');
      expect(result.rows[0]['section'], 'BSIT-4A');
      expect(result.rows[0]['adviser_name'], 'Prof. Alex Santos');
      expect(result.rows[0]['member_ids'], [
        'DELA CRUZ, Juan',
        'SANTOS, Maria',
        'REYES, Mark',
        'GARCIA, Anna',
      ]);
      expect(result.rows[0]['leader_id'], 'DELA CRUZ, Juan');

      // Team Beta ALSO in BSIT-4A with Prof. Elena Ramos (2 advisers in Section 4A)
      expect(result.rows[1]['team_name'], 'Team Beta');
      expect(result.rows[1]['section'], 'BSIT-4A');
      expect(result.rows[1]['adviser_name'], 'Prof. Elena Ramos');
      expect(result.rows[1]['member_ids'], [
        'TORRES, Miguel',
        'FLORES, Angela',
      ]);

      // Team Gamma in BSIT-4B
      expect(result.rows[2]['team_name'], 'Team Gamma');
      expect(result.rows[2]['section'], 'BSIT-4B');
      expect(result.rows[2]['adviser_name'], 'Prof. Roberto Cruz');
    });

    test('parses multi-row template with section preamble at top so section is not repeated per team', () {
      const csv = '''
Section,BSIT-4A
Team Name,Capstone Project,Adviser,Team Members
Team Alpha,Campus Navigation System,Prof. Alex Santos,"DELA CRUZ, Juan"
,,,,"SANTOS, Maria"
Team Beta,Automated Library Portal,Prof. Elena Ramos,"TORRES, Miguel"
,,,,"FLORES, Angela"
''';

      final result = parseTeamBulkCsv(csv);
      expect(result.rows, hasLength(2));
      expect(result.rows[0]['team_name'], 'Team Alpha');
      expect(result.rows[0]['section'], 'BSIT-4A');
      expect(result.rows[0]['adviser_name'], 'Prof. Alex Santos');
      expect(result.rows[1]['team_name'], 'Team Beta');
      expect(result.rows[1]['section'], 'BSIT-4A');
      expect(result.rows[1]['adviser_name'], 'Prof. Elena Ramos');
    });

    test('parses official department team roster template with shared system (Option 2 canonical standard)', () {
      const csv = '''
System Name,Hospital Management System
Section,BSIT-4A
Project Manager,Juan Dela Cruz

ADVISER: Prof. Alex Santos
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Patient Records
,Maria Santos,
Group 2,Mark Reyes,Billing
,Anna Garcia,
Group 3,David Aquino,Appointments
,Sarah Ocampo,
Group 4,Daniel Rivera,Triage
,Jasmine Morales,

ADVISER: Prof. Elena Ramos
Team Name,Names,Project / Module
Group 5,Miguel Torres,Pharmacy
,Angela Flores,
Group 6,Carlo Ramos,Laboratory
,Nicole Bautista,
Group 7,Kevin Villanueva,Inventory
,Bea Castro,
Group 8,Christian Lim,Wards
,Joshua Navarro,
''';

      final result = parseTeamBulkCsv(csv);

      expect(result.rows, hasLength(8));
      expect(result.section, 'BSIT-4A');
      expect(result.systemName, 'Hospital Management System');
      expect(result.projectManager, 'Juan Dela Cruz');

      // Groups 1 to 4 should be assigned to Prof. Alex Santos
      for (var i = 0; i < 4; i++) {
        final row = result.rows[i];
        expect(row['adviser_name'], 'Prof. Alex Santos', reason: 'Row $i adviser');
        expect(row['section'], 'BSIT-4A', reason: 'Row $i section');
        expect(row['system_name'], 'Hospital Management System', reason: 'Row $i system_name');
        expect(row['project_manager'], 'Juan Dela Cruz', reason: 'Row $i project_manager');
        expect(row['member_ids'], hasLength(2));
      }

      // Specific checks for Group 1 & Group 2
      expect(result.rows[0]['team_name'], 'Group 1');
      expect(result.rows[0]['project_title'], 'Patient Records');
      expect(result.rows[0]['member_ids'], ['Juan Dela Cruz', 'Maria Santos']);
      expect(result.rows[0]['leader_id'], 'Juan Dela Cruz');

      expect(result.rows[1]['team_name'], 'Group 2');
      expect(result.rows[1]['project_title'], 'Billing');
      expect(result.rows[1]['member_ids'], ['Mark Reyes', 'Anna Garcia']);
      expect(result.rows[1]['leader_id'], 'Mark Reyes');

      // Groups 5 to 8 should be assigned to Prof. Elena Ramos
      for (var i = 4; i < 8; i++) {
        final row = result.rows[i];
        expect(row['adviser_name'], 'Prof. Elena Ramos', reason: 'Row $i adviser');
        expect(row['section'], 'BSIT-4A', reason: 'Row $i section');
        expect(row['system_name'], 'Hospital Management System', reason: 'Row $i system_name');
        expect(row['project_manager'], 'Juan Dela Cruz', reason: 'Row $i project_manager');
        expect(row['member_ids'], hasLength(2));
      }

      // Specific checks for Group 5 & Group 8
      expect(result.rows[4]['team_name'], 'Group 5');
      expect(result.rows[4]['project_title'], 'Pharmacy');
      expect(result.rows[4]['member_ids'], ['Miguel Torres', 'Angela Flores']);
      expect(result.rows[4]['leader_id'], 'Miguel Torres');

      expect(result.rows[7]['team_name'], 'Group 8');
      expect(result.rows[7]['project_title'], 'Wards');
      expect(result.rows[7]['member_ids'], ['Christian Lim', 'Joshua Navarro']);
      expect(result.rows[7]['leader_id'], 'Christian Lim');
    });

    test('parses official department team roster with independent systems per team (no system name preamble)', () {
      const csv = '''
Section,BSIT-4A

ADVISER: Prof. Alex Santos
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Smart Campus Navigation System
,Maria Santos,
Group 2,Mark Reyes,Automated Library Portal
,Anna Garcia,

ADVISER: Prof. Elena Ramos
Team Name,Names,Project / Module
Group 3,Miguel Torres,Hospital Inventory System
,Angela Flores,
Group 4,Carlo Ramos,Laboratory Management Portal
,Nicole Bautista,
''';

      final result = parseTeamBulkCsv(csv);

      expect(result.rows, hasLength(4));
      expect(result.section, 'BSIT-4A');
      expect(result.systemName, isNull);
      expect(result.projectManager, isNull);

      // Check Group 1 (under Prof. Alex Santos with independent system)
      expect(result.rows[0]['team_name'], 'Group 1');
      expect(result.rows[0]['project_title'], 'Smart Campus Navigation System');
      expect(result.rows[0]['section'], 'BSIT-4A');
      expect(result.rows[0]['adviser_name'], 'Prof. Alex Santos');
      expect(result.rows[0].containsKey('system_name'), isFalse);
      expect(result.rows[0]['member_ids'], ['Juan Dela Cruz', 'Maria Santos']);

      // Check Group 2 (under Prof. Alex Santos with independent system)
      expect(result.rows[1]['team_name'], 'Group 2');
      expect(result.rows[1]['project_title'], 'Automated Library Portal');
      expect(result.rows[1]['section'], 'BSIT-4A');
      expect(result.rows[1]['adviser_name'], 'Prof. Alex Santos');

      // Check Group 3 (under Prof. Elena Ramos with independent system)
      expect(result.rows[2]['team_name'], 'Group 3');
      expect(result.rows[2]['project_title'], 'Hospital Inventory System');
      expect(result.rows[2]['section'], 'BSIT-4A');
      expect(result.rows[2]['adviser_name'], 'Prof. Elena Ramos');

      // Check Group 4 (under Prof. Elena Ramos with independent system)
      expect(result.rows[3]['team_name'], 'Group 4');
      expect(result.rows[3]['project_title'], 'Laboratory Management Portal');
      expect(result.rows[3]['section'], 'BSIT-4A');
      expect(result.rows[3]['adviser_name'], 'Prof. Elena Ramos');
    });

    test('parses Option 3: Adviser-First with section sub-headers (e.g. three 4A and one 4C)', () {
      const csv = '''
ADVISER: Prof. Alex Santos

Section,BSIT-4A
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Smart Campus Navigation System
,Maria Santos,
,Mark Reyes,
,Anna Garcia,
Group 2,David Aquino,Automated Library Portal
,Sarah Ocampo,
,Daniel Rivera,
,Jasmine Morales,
Group 3,Carlo Ramos,Alumni Career Tracker
,Nicole Bautista,
,John Mendoza,
,Patricia Cruz,

Section,BSIT-4C
Team Name,Names,Project / Module
Group 1,Miguel Torres,Hospital Inventory System
,Angela Flores,
,Francis Dizon,
,Rhea Salazar,

ADVISER: Prof. Elena Ramos

Section,BSIT-4A
Team Name,Names,Project / Module
Group 4,Kevin Villanueva,Event Booking System
,Bea Castro,
,Christian Lim,
,Joshua Navarro,

Section,BSIT-4B
Team Name,Names,Project / Module
Group 1,Gabriel Tan,Laboratory Management Portal
,Chloe Soriano,
,Pauline Mercado,
,Rafael Pascual,
''';

      final result = parseTeamBulkCsv(csv);
      expect(result.rows, hasLength(6));

      // Prof. Alex Santos - Section 4A (3 teams)
      expect(result.rows[0]['team_name'], 'Group 1');
      expect(result.rows[0]['section'], 'BSIT-4A');
      expect(result.rows[0]['adviser_name'], 'Prof. Alex Santos');

      expect(result.rows[1]['team_name'], 'Group 2');
      expect(result.rows[1]['section'], 'BSIT-4A');
      expect(result.rows[1]['adviser_name'], 'Prof. Alex Santos');

      expect(result.rows[2]['team_name'], 'Group 3');
      expect(result.rows[2]['section'], 'BSIT-4A');
      expect(result.rows[2]['adviser_name'], 'Prof. Alex Santos');

      // Prof. Alex Santos - Section 4C (1 team)
      expect(result.rows[3]['team_name'], 'Group 1');
      expect(result.rows[3]['section'], 'BSIT-4C');
      expect(result.rows[3]['adviser_name'], 'Prof. Alex Santos');

      // Prof. Elena Ramos - Section 4A (1 team)
      expect(result.rows[4]['team_name'], 'Group 4');
      expect(result.rows[4]['section'], 'BSIT-4A');
      expect(result.rows[4]['adviser_name'], 'Prof. Elena Ramos');

      // Prof. Elena Ramos - Section 4B (1 team)
      expect(result.rows[5]['team_name'], 'Group 1');
      expect(result.rows[5]['section'], 'BSIT-4B');
      expect(result.rows[5]['adviser_name'], 'Prof. Elena Ramos');
    });

    test('csvToTsv converts CSV commas to tabs outside quotes for Excel pasting and parses TSV correctly', () {
      const csv = '''Section,BSIT-4A
ADVISER: Prof. Alex Santos
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Smart Campus Navigation System
,Maria Santos,''';

      final tsv = csvToTsv(csv);
      expect(tsv, contains('Section\tBSIT-4A'));
      expect(tsv, contains('Team Name\tNames\tProject / Module'));
      expect(tsv, contains('Group 1\tJuan Dela Cruz\tSmart Campus Navigation System'));

      // Parse the TSV directly (simulating pasting from Excel)
      final result = parseTeamBulkCsv(tsv);
      expect(result.rows, hasLength(1));
      expect(result.section, 'BSIT-4A');
      expect(result.rows[0]['team_name'], 'Group 1');
      expect(result.rows[0]['project_title'], 'Smart Campus Navigation System');
      expect(result.rows[0]['member_ids'], ['Juan Dela Cruz', 'Maria Santos']);
    });

    test('parses PIT team roster with single instructor declared at top', () {
      const csv = '''Section,BSIT-2A
Instructor,Prof. Alex Santos

Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Smart Campus Navigation System
,Maria Santos,
,Mark Reyes,
,Anna Garcia,
Group 2,David Aquino,Automated Library Portal
,Sarah Ocampo,
,Daniel Rivera,
,Jasmine Morales,
''';

      final result = parseTeamBulkCsv(csv);
      expect(result.rows, hasLength(2));
      expect(result.section, 'BSIT-2A');
      expect(result.rows[0]['adviser_name'], 'Prof. Alex Santos');
      expect(result.rows[1]['adviser_name'], 'Prof. Alex Santos');
      expect(result.rows[0]['member_ids'], hasLength(4));
      expect(result.rows[1]['member_ids'], hasLength(4));
    });

    test('parses sequential multi-section blocks in a single CSV file', () {
      const csv = '''Section,BSIT-4A
ADVISER: Prof. Alex Santos
Team Name,Names,Project / Module
Group 1,Juan Dela Cruz,Smart Campus
,Maria Santos,
Group 2,Mark Reyes,Library Portal
,Anna Garcia,

Section,BSIT-4B
ADVISER: Prof. Elena Ramos
Team Name,Names,Project / Module
Group 1,Pedro Gomez,Hospital Inventory
,Clara Santos,
Group 2,Luis Tan,Dormitory System
,Bea Perez,
''';

      final result = parseTeamBulkCsv(csv);
      expect(result.rows, hasLength(4));
      expect(result.section, 'BSIT-4A, BSIT-4B');

      // Section 4A teams
      expect(result.rows[0]['section'], 'BSIT-4A');
      expect(result.rows[0]['team_name'], 'Group 1');
      expect(result.rows[0]['adviser_name'], 'Prof. Alex Santos');

      expect(result.rows[1]['section'], 'BSIT-4A');
      expect(result.rows[1]['team_name'], 'Group 2');
      expect(result.rows[1]['adviser_name'], 'Prof. Alex Santos');

      // Section 4B teams
      expect(result.rows[2]['section'], 'BSIT-4B');
      expect(result.rows[2]['team_name'], 'Group 1');
      expect(result.rows[2]['adviser_name'], 'Prof. Elena Ramos');

      expect(result.rows[3]['section'], 'BSIT-4B');
      expect(result.rows[3]['team_name'], 'Group 2');
      expect(result.rows[3]['adviser_name'], 'Prof. Elena Ramos');
    });

    test('parses multi-column side-by-side section groupings (Image 4 format)', () {
      const csv = '''
OFFICIAL LIST OF GROUPINGS,,,,,,,,
2A,,,2B,,,2C,,
PROJECT MANAGER: Cabahug,,,PROJECT MANAGER: Duma-og,,,PROJECT MANAGER: Candawan,,
Team Name,Names,Modules,Team Name,Names,Modules,Team Name,Names,Modules
Group 1,Kristine Dayap,Core,Group 1,Franz Duma-og,Auth,CTRL Freaks,Yanoyan,UI
,Maiko Pactoran,,,Aaron John Patigayon,,,Jumamil,
,Eron Maniabo,,,Ana Marie Campos,,,Calib,
,Arl Nathan Cabahug,,,Efren Baron,,,Barot,
V.O.I.D.,Xian Salac,Security,Redcrew,Earl John Parami,Billing,TECH4CE,Baguingco,API
,Velasquez,,,Alianah Hashemah Omaguing,,,Igoy,
''';

      final result = parseTeamBulkCsv(csv);

      expect(result.rows, hasLength(6));

      // Check Section 2A teams
      expect(result.rows[0]['team_name'], 'Group 1');
      expect(result.rows[0]['section'], '2A');
      expect(result.rows[0]['project_manager'], 'Cabahug');
      expect(result.rows[0]['project_title'], 'Core');
      expect(result.rows[0]['member_ids'], [
        'Kristine Dayap',
        'Maiko Pactoran',
        'Eron Maniabo',
        'Arl Nathan Cabahug',
      ]);
      expect(result.rows[0]['leader_id'], 'Kristine Dayap');

      expect(result.rows[1]['team_name'], 'V.O.I.D.');
      expect(result.rows[1]['section'], '2A');
      expect(result.rows[1]['project_manager'], 'Cabahug');
      expect(result.rows[1]['member_ids'], ['Xian Salac', 'Velasquez']);

      // Check Section 2B teams
      expect(result.rows[2]['team_name'], 'Group 1');
      expect(result.rows[2]['section'], '2B');
      expect(result.rows[2]['project_manager'], 'Duma-og');
      expect(result.rows[2]['member_ids'], [
        'Franz Duma-og',
        'Aaron John Patigayon',
        'Ana Marie Campos',
        'Efren Baron',
      ]);

      expect(result.rows[3]['team_name'], 'Redcrew');
      expect(result.rows[3]['section'], '2B');
      expect(result.rows[3]['project_manager'], 'Duma-og');

      // Check Section 2C teams
      expect(result.rows[4]['team_name'], 'CTRL Freaks');
      expect(result.rows[4]['section'], '2C');
      expect(result.rows[4]['project_manager'], 'Candawan');
      expect(result.rows[4]['member_ids'], ['Yanoyan', 'Jumamil', 'Calib', 'Barot']);

      expect(result.rows[5]['team_name'], 'TECH4CE');
      expect(result.rows[5]['section'], '2C');
      expect(result.rows[5]['project_manager'], 'Candawan');
      expect(result.rows[5]['member_ids'], ['Baguingco', 'Igoy']);
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
            'adviser_name': 9,
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
team_name,project_title,year_level,member_ids,leader_id,adviser_name
Team PIT,Title,3rd Year,101,101,
''';

      final result = parseTeamBulkCsvWithContext(
        csv,
        isCapstoneAdmin: false,
        pitLeadYear: '3rd Year',
      );

      expect(result.rows.first['level'], '3rd Year PIT');
      expect(result.rows.first.containsKey('adviser_name'), isTrue);
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
      expect(csv.contains('adviser_name'), isFalse);
    });

    test('does not set level for capstone admin context', () {
      const csv = '''
team_name,project_title,year_level,member_ids,leader_id,adviser_name
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
    test('each year level has three teams with four members', () {
      for (final year in teamSampleYearLevels) {
        final result = parseTeamBulkCsv(sampleTeamCsvForYear(
          year,
          isCapstoneAdmin: true,
        ));
        expect(result.rows, hasLength(3), reason: year);
        for (final row in result.rows) {
          expect(row['member_ids'], hasLength(4));
        }
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
