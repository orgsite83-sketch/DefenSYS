import 'dart:convert';

import 'package:excel/excel.dart' as xl;

import '../csv_file_io.dart';
import '../excel_safe_decode.dart';
import 'team_bulk_import_csv.dart';

/// Read a batch atomically so a failed file is never silently omitted.
String readTeamImportFiles(List<PickedTabularFile> files) {
  final rows = <Map<String, dynamic>>[];
  final errors = <String>[];
  for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
    final file = files[fileIndex];
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
      final parsed = parseTeamBulkCsv(csv, sourceKey: 'file$fileIndex');
      if (parsed.rows.isEmpty) {
        throw const FormatException(
          'No team rows were found. Use the DefenSYS team roster template.',
        );
      }
      rows.addAll(parsed.rows);
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
  // Normalize each file independently. Concatenating raw sheets can align a
  // second file's unrelated columns with the first file's table blocks.
  const fields = [
    'team_name',
    'project_title',
    'level',
    'year_level',
    'member_ids',
    'leader_id',
    'adviser_name',
    'instructor_name',
    'section',
    'system_name',
    'project_manager',
    'group_key',
  ];
  String cell(dynamic value) {
    final text = value is List ? value.join('|') : value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  return [
    fields.join(','),
    for (final row in rows) fields.map((field) => cell(row[field])).join(','),
  ].join('\n');
}

String teamXlsxToCsv(List<int> bytes, {bool preserveTeamGroups = true}) {
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
  // Import-only group columns preserve the semantic Team Name merges. They
  // are omitted from the public CSV/copy template and never added to Excel.
  final groupColumns = <int, Map<int, String>>{};
  final groupHeaders = <int, int>{};
  if (preserveTeamGroups) {
    for (var r = 0; r < sheet.maxRows && r < 10; r++) {
      final row = sheet.rows[r];
      for (var col = 0; col < row.length; col++) {
        final label = _cellText(
          row[col]?.value,
        ).toLowerCase().replaceAll('*', '').trim();
        if (label != 'team name' && label != 'team_name') continue;
        var memberCol = -1;
        for (var c = col + 1; c < row.length; c++) {
          final header = _cellText(
            row[c]?.value,
          ).toLowerCase().replaceAll('*', '').trim();
          if (header == 'team name' || header == 'team_name') break;
          if (header == 'team members' || header == 'team_members') {
            memberCol = c;
            break;
          }
        }
        if (memberCol < 0) continue;
        final keys = <int, String>{};
        for (final span in sheet.spannedItems) {
          final endpoints = span
              .split(':')
              .map(xl.CellIndex.indexByString)
              .toList();
          if (endpoints.length != 2) continue;
          final start = endpoints.first, end = endpoints.last;
          if (start.columnIndex != col ||
              end.columnIndex != col ||
              start.rowIndex <= r ||
              end.rowIndex <= start.rowIndex) {
            continue;
          }
          for (
            var memberRow = start.rowIndex;
            memberRow <= end.rowIndex;
            memberRow++
          ) {
            keys[memberRow] = 'xlsx/c$col/r${start.rowIndex}';
          }
        }
        if (keys.isNotEmpty) {
          groupColumns[memberCol] = keys;
          groupHeaders[memberCol] = r;
        }
      }
    }
  }
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
  for (var r = 0; r < sheet.maxRows; r++) {
    final row = sheet.rows[r];
    final cells = <String>[];
    for (var c = 0; c < sheet.maxColumns; c++) {
      cells.add(c < row.length ? _cellText(row[c]?.value) : '');
      if (groupColumns.containsKey(c)) {
        cells.add(
          groupHeaders[c] == r ? 'group_key' : groupColumns[c]![r] ?? '',
        );
      }
    }
    // Preserve group separators, including empty rows between unnamed teams.
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
  if (lines.every((line) => line.replaceAll(',', '').trim().isEmpty)) {
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
