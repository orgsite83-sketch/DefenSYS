import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/excel_safe_decode.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
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

  test('actual 16-team sample uses the production XLSX conversion', () {
    final bytes = File(
      '../sample_file/16_Teams_2nd_Year/1st Sem/team/Team16roster.xlsx',
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
