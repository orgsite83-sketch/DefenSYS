import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/excel_safe_decode.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

List<int> workbookBytes({String prefix = '', bool singleQuotes = false}) {
  final workbook = xl.Excel.createExcel();
  workbook['Sheet1'].appendRow([
    xl.TextCellValue('Team Name'),
    xl.TextCellValue('PIT Project'),
    xl.TextCellValue('Section'),
    xl.TextCellValue('Instructor'),
    xl.TextCellValue('Team Members'),
  ]);
  workbook['Sheet1'].appendRow([
    xl.TextCellValue('Team Peña'),
    xl.TextCellValue('Campus, records'),
    xl.TextCellValue('BSIT-2A'),
    xl.TextCellValue('Prof. José'),
    xl.TextCellValue('Ana Muñoz'),
  ]);
  workbook['Sheet1'].appendRow([
    null,
    null,
    null,
    null,
    xl.TextCellValue('Juan Cruz'),
  ]);
  workbook['Sheet1'].merge(
    xl.CellIndex.indexByString('A2'),
    xl.CellIndex.indexByString('A3'),
  );
  final bytes = workbook.encode()!;
  final archive = ZipDecoder().decodeBytes(bytes);
  final relations = archive.findFile('xl/_rels/workbook.xml.rels')!;
  final document = XmlDocument.parse(
    utf8.decode(relations.content as List<int>),
  );
  for (final node in document.findAllElements('Relationship')) {
    node.setAttribute('Target', '$prefix${node.getAttribute('Target')}');
  }
  // Non-ASCII attributes must survive normalization without mojibake.
  document.rootElement.setAttribute('description', 'José Peña');
  var xml = document.toXmlString();
  if (singleQuotes) xml = xml.replaceAll('"', "'");
  final content = utf8.encode(xml);
  archive.addFile(ArchiveFile(relations.name, content.length, content));
  return ZipEncoder().encode(archive)!;
}

void main() {
  test(
    'instructor template reuses the official format with assigned section and instructor',
    () {
      final bytes = generateOfficialTeamRosterExcelBytes(
        isCapstone: false,
        assignedSection: 'BSIT-3C',
        instructorName: 'Mara Reyes',
      );
      final result = parseTeamBulkCsv(teamXlsxToCsv(bytes));
      expect(result.rows, hasLength(16));
      expect(result.rows.every((r) => r['section'] == 'BSIT-3C'), isTrue);
      expect(
        result.rows.every((r) => r['instructor_name'] == 'Mara Reyes'),
        isTrue,
      );
    },
  );

  test(
    'admin template retains the two-section Capstone adviser assignments',
    () {
      final result = parseTeamBulkCsv(
        teamXlsxToCsv(generateOfficialTeamRosterExcelBytes(isCapstone: true)),
      );
      expect(result.rows, hasLength(16));
      expect(result.rows.map((r) => r['section']).toSet(), {
        'BSIT-4A',
        'BSIT-4B',
      });
      expect(result.rows.map((r) => r['adviser_name']).toSet(), hasLength(4));
    },
  );
  for (final prefix in ['', '/xl/', 'xl/']) {
    for (final singleQuotes in [false, true]) {
      test('imports $prefix relationships, single quotes: $singleQuotes', () {
        final bytes = workbookBytes(prefix: prefix, singleQuotes: singleQuotes);
        if (prefix.isNotEmpty) {
          // Reproduce the installed upstream decoder's failure first.
          expect(() => xl.Excel.decodeBytes(bytes), throwsA(anything));
        }
        final workbook = safeDecodeExcel(bytes);
        expect(workbook['Sheet1'].rows[1][0]!.value.toString(), 'Team Peña');
        final csv = readTeamImportFiles([
          PickedTabularFile(
            name: 'teams.xlsx',
            extension: 'xlsx',
            bytes: bytes,
          ),
        ]);
        final result = parseTeamBulkCsv(csv);
        expect(result.rows, hasLength(1));
        expect(result.rows.single['team_name'], 'Team Peña');
        expect(result.rows.single['project_title'], 'Campus, records');
        expect(result.rows.single['member_ids'], ['Ana Muñoz', 'Juan Cruz']);
      });
    }
  }

  test(
    'optional file provenance distinguishes files with identical names and exported keys',
    () {
      const files = [
        PickedTabularFile(
          name: 'roster.csv',
          extension: 'csv',
          bytes: [],
          text:
              'team_name,project_title,section,member_ids,leader_id,group_key,import_file_key\n'
              'Core,Directory,BSIT-2B,Ana Reyes,Ana Reyes,same,spoofed\n',
        ),
        PickedTabularFile(
          name: 'roster.csv',
          extension: 'csv',
          bytes: [],
          text:
              'team_name,project_title,section,member_ids,leader_id,group_key,import_file_key\n'
              'Auth,Sign in,BSIT-2B,Luis Santos,Luis Santos,same,spoofed\n',
        ),
      ];
      final rows = parseTeamBulkCsv(
        readTeamImportFiles(files, includeFileSources: true),
      ).rows;
      expect(rows.map((row) => row['import_file_key']), ['file0', 'file1']);
      expect(rows.map((row) => row['group_key']), ['file0/same', 'file1/same']);
      expect(rows.first['member_ids'], ['Ana Reyes']);
      expect(rows.last['member_ids'], ['Luis Santos']);
      expect(readTeamImportFiles(files), isNot(contains('import_file_key')));
    },
  );

  test('actual 16-team sample uses the production XLSX conversion', () {
    final bytes = File(
      '../Defensys_sample files/sample_file/16_Teams_2nd_Year/1st Sem/team/Team16roster.xlsx',
    ).readAsBytesSync();
    final result = parseTeamBulkCsv(teamXlsxToCsv(bytes));
    expect(result.rows, hasLength(16));
    expect(
      result.rows.where((row) => row['section'] == 'BSIT-2A'),
      hasLength(8),
    );
    expect(
      result.rows.where((row) => row['section'] == 'BSIT-2B'),
      hasLength(8),
    );
    expect(
      result.rows.every((row) => (row['member_ids'] as List).length == 4),
      isTrue,
    );
  });

  test('reports corrupt, empty, unsupported, and wrong-template filenames', () {
    expect(
      () => readTeamImportFiles([
        const PickedTabularFile(
          name: 'broken.xlsx',
          extension: 'xlsx',
          bytes: [1, 2, 3],
        ),
        const PickedTabularFile(name: 'empty.csv', extension: 'csv', bytes: []),
        const PickedTabularFile(name: 'old.xls', extension: 'xls', bytes: []),
        PickedTabularFile(
          name: 'students.csv',
          extension: 'csv',
          bytes: utf8.encode('name,email\nAna,ana@example.com'),
        ),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('broken.xlsx: Could not decode'),
            contains('empty.csv:'),
            contains('old.xls:'),
            contains('students.csv: No team rows'),
          ),
        ),
      ),
    );
  });

  test('mixed valid and corrupt files fail visibly as one batch', () {
    expect(
      () => readTeamImportFiles([
        PickedTabularFile(
          name: 'good.xlsx',
          extension: 'xlsx',
          bytes: workbookBytes(),
        ),
        const PickedTabularFile(name: 'bad.xlsx', extension: 'xlsx', bytes: []),
      ]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('No files were staged'), contains('bad.xlsx:')),
        ),
      ),
    );
  });

  test('empty worksheet has an explicit error', () {
    expect(
      () => teamXlsxToCsv(xl.Excel.createExcel().encode()!),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('is empty'),
        ),
      ),
    );
  });
}
