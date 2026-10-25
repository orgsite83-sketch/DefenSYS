import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  for (final variant in [(true, false), (false, false), (false, true)]) {
    final (isCapstone, instructorWorkspace) = variant;
    final scope = isCapstone
        ? 'Capstone'
        : instructorWorkspace
        ? 'Instructor'
        : 'PIT';
    test('$scope XLSX retains every merged block perimeter', () {
      final archive = ZipDecoder().decodeBytes(
        generateOfficialTeamRosterExcelBytes(
          isCapstone: isCapstone,
          instructorWorkspace: instructorWorkspace,
        ),
      );
      XmlDocument readXml(String path) => XmlDocument.parse(
        utf8.decode(archive.findFile(path)!.content as List<int>),
      );

      // Inspect the saved XML: decoding merges can hide missing border cells.
      final sheet = readXml('xl/worksheets/sheet1.xml');
      final styles = readXml('xl/styles.xml');
      final formats = styles
          .findAllElements('cellXfs')
          .single
          .findElements('xf')
          .toList();
      final borders = styles
          .findAllElements('borders')
          .single
          .findElements('border')
          .toList();
      final cells = {
        for (final cell in sheet.findAllElements('c'))
          cell.getAttribute('r')!: cell,
      };
      final mergedRanges = sheet
          .findAllElements('mergeCell')
          .map((merge) => merge.getAttribute('ref')!)
          .toList();
      expect(
        mergedRanges,
        containsAll([
          'B5:B8',
          'B33:B36',
          instructorWorkspace ? 'G7:G10' : 'H7:H10',
          instructorWorkspace ? 'G35:G38' : 'H35:H38',
        ]),
      );

      for (final range in mergedRanges) {
        final endpoints = range.split(':');
        final start = CellIndex.indexByString(endpoints.first);
        final end = CellIndex.indexByString(endpoints.last);
        for (var row = start.rowIndex; row <= end.rowIndex; row++) {
          final address = CellIndex.indexByColumnRow(
            columnIndex: start.columnIndex,
            rowIndex: row,
          ).cellId;
          final cell = cells[address];
          expect(cell, isNotNull, reason: '$range needs border cell $address');
          final format = formats[int.parse(cell!.getAttribute('s') ?? '0')];
          final border = borders[int.parse(format.getAttribute('borderId')!)];
          for (final side in ['left', 'right', 'top', 'bottom']) {
            final isOuterEdge =
                side == 'left' ||
                side == 'right' ||
                (side == 'top' && row == start.rowIndex) ||
                (side == 'bottom' && row == end.rowIndex);
            expect(
              border.findElements(side).singleOrNull?.getAttribute('style'),
              isOuterEdge ? 'thin' : anyOf(isNull, 'none'),
              reason: '$range: $address $side border',
            );
          }
        }
      }
    });
  }
}
