import 'dart:convert';

import 'package:excel/excel.dart' as xl;

import '../csv_file_io.dart';
import '../excel_safe_decode.dart';
import 'team_bulk_import_csv.dart';

/// Read a batch atomically so a failed file is never silently omitted.
String readTeamImportFiles(List<PickedTabularFile> files) {
  final texts = <String>[];
  final errors = <String>[];
  for (final file in files) {
    try {
      if (!file.isXlsx && !file.isCsv) {
        throw const FormatException('Choose a .csv or .xlsx team roster.');
      }
      final csv = file.isXlsx
          ? teamXlsxToCsv(file.bytes)
          : file.text ?? utf8.decode(file.bytes);
      if (csv.trim().isEmpty) {
        throw const FormatException('The file contains no team data.');
      }
      if (parseTeamBulkCsv(csv).rows.isEmpty) {
        throw const FormatException(
          'No team rows were found. Use the DefenSYS team roster template.',
        );
      }
      texts.add(csv);
    } catch (error) {
      final detail = error is FormatException ? error.message : '$error';
      errors.add('${file.name}: $detail');
    }
  }
  if (errors.isNotEmpty) {
    throw FormatException(
      'No files were staged. Fix the following and try again:\n${errors.join('\n')}',
    );
  }
  return texts.join('\n\n');
}

String teamXlsxToCsv(List<int> bytes) {
  late final xl.Excel workbook;
  try {
    workbook = safeDecodeExcel(bytes);
  } catch (error) {
    throw FormatException(
      'Could not decode the XLSX workbook. Open it in Excel and save a new '
      '.xlsx or CSV copy. Details: $error',
    );
  }
  if (workbook.tables.isEmpty) {
    throw const FormatException('The workbook has no worksheets.');
  }
  final sheet = workbook.tables.values.first;
  // Copy the spans: editing merged cells can change the sheet's span list.
  for (final span in List<String>.of(sheet.spannedItems)) {
    final parts = span.split(':');
    if (parts.length != 2) continue;
    final start = xl.CellIndex.indexByString(parts[0]);
    final end = xl.CellIndex.indexByString(parts[1]);
    final value = sheet.cell(start).value;
    if (value == null) continue;
    for (var row = start.rowIndex; row <= end.rowIndex; row++) {
      for (var col = start.columnIndex; col <= end.columnIndex; col++) {
        if (row == start.rowIndex && col == start.columnIndex) continue;
        sheet.updateCell(
          xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
          value,
        );
      }
    }
  }
  final lines = <String>[];
  for (final row in sheet.rows) {
    final cells = row.map((cell) => _cellText(cell?.value)).toList();
    if (cells.every((text) => text.isEmpty)) continue;
    lines.add(
      cells
          .map((text) {
            if (text.contains(',') ||
                text.contains('"') ||
                text.contains('\n')) {
              return '"${text.replaceAll('"', '""')}"';
            }
            return text;
          })
          .join(','),
    );
  }
  if (lines.isEmpty) {
    throw FormatException('The first worksheet "${sheet.sheetName}" is empty.');
  }
  return lines.join('\n');
}

String _cellText(xl.CellValue? value) {
  if (value == null) return '';
  if (value is xl.TextCellValue) return (value.value.text ?? '').trim();
  if (value is xl.IntCellValue) return value.value.toString();
  if (value is xl.DoubleCellValue) {
    final number = value.value;
    return number == number.roundToDouble()
        ? number.round().toString()
        : number.toString();
  }
  if (value is xl.FormulaCellValue) return value.formula.trim();
  if (value is xl.BoolCellValue) return value.value ? 'true' : 'false';
  return value.toString().trim();
}
