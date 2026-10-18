import 'package:defensys/screens/web/admin/user_management/bulk_import/official_class_list_parser.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:defensys/utils/import/class_list_template.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:defensys/utils/platform/download_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final year in ['1st', '2nd', '3rd', '4th']) {
    test(
      '$year year sample keeps metadata and every student in the assigned section',
      () {
        final number = year[0];
        final sample = ClassListTemplate(
          level: '$year Year ${year == '4th' ? 'Capstone' : 'PIT'}',
          section: 'BSIT-${number}B',
          term: '1st Semester, A.Y. 2027-2028',
          instructor: 'Dr. Santos, "Ana"',
        );
        final parsed = parseOfficialClassListCsv(sample.csv);
        expect(parsed.metadata['section'], 'BSIT-${number}B');
        expect(parsed.metadata['year_level'], '$year Year');
        expect(parsed.metadata['faculty'], 'Dr. Santos, "Ana"');
        expect(parsed.students, hasLength(4));
        expect(
          parsed.students.every((row) => row['year_level'] == '$year Year'),
          isTrue,
        );
        expect(
          parsed.students.every((row) => row['section'] == 'BSIT-${number}B'),
          isTrue,
        );
        expect(sample.csv, contains('$year Yr.'));
        expect(
          sample.filename,
          'defensys-class-list-bsit-${number}b-$year-year.csv',
        );
        expect(downloadMimeType(sample.filename), 'text/csv;charset=utf-8');
      },
    );
  }

  test(
    'missing section uses the selected year rather than a first-year class',
    () {
      const sample = ClassListTemplate(
        level: '3rd Year PIT',
        section: '',
        term: 'Active Semester',
        instructor: 'Sample Instructor',
      );
      expect(sample.classSection, 'BSIT-3A');
      expect(sample.studentLevel, '3rd Yr.');
    },
  );

  test('template uses current academic term and full instructor name', () {
    expect(
      templateTermLabel({'school_year': '2027-2028', 'label': '2nd Semester'}),
      '2027-2028 2nd Semester',
    );
    expect(
      templateTermLabel({'display_name': 'Configured Term'}),
      'Configured Term',
    );
    expect(
      templateInstructorName({
        'first_name': 'Ana',
        'last_name': 'Santos',
        'username': '213',
      }),
      'Ana Santos',
    );
    expect(
      templateInstructorName({
        'full_name': '',
        'first_name': 'Ana',
        'last_name': 'Santos',
      }),
      'Ana Santos',
    );
  });

  test('named XLSX team template round-trips with the assigned section', () {
    final bytes = generateOfficialTeamRosterExcelBytes(
      isCapstone: false,
      assignedSection: 'BSIT-3A',
      instructorName: 'Ana Santos',
    );
    expect(bytes.take(2), [0x50, 0x4b]);
    final result = parseTeamBulkCsv(teamXlsxToCsv(bytes));
    expect(result.rows, isNotEmpty);
    expect(result.rows.every((row) => row['section'] == 'BSIT-3A'), isTrue);
    final name = importTemplateFilename(
      kind: 'pit-teams',
      section: 'BSIT-3A',
      level: '3rd Year',
      extension: 'xlsx',
    );
    expect(name, 'defensys-pit-teams-bsit-3a-3rd-year.xlsx');
    expect(
      downloadMimeType(name),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(downloadMimeType('results.PDF'), 'application/pdf');
  });
}
