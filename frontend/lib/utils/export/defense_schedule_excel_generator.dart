import 'package:excel/excel.dart';

/// Builds the editable timetable shown in the schedule import blueprint.
List<int> generateDefenseScheduleExcelBytes({required bool isCapstone}) {
  final workbook = Excel.createExcel();
  const sheetName = 'Defense Schedule';
  workbook.rename(workbook.getDefaultSheet()!, sheetName);
  final sheet = workbook[sheetName];
  // Leave columns A-C and rows 1-2 blank, matching the inset reference layout.
  const firstColumn = 3;
  const firstRow = 2;
  final lastColumn = isCapstone ? 'L' : 'K';
  final headers = [
    '#',
    'Time',
    'Team Name',
    'Adviser',
    'Panel Chair',
    'Panel Member 1',
    'Panel Member 2',
    'Panel Member 3',
    if (isCapstone) 'Documenter',
  ];
  final preamble = isCapstone
      ? ['Concept Proposal', '6/18/2026', 'Room 301']
      : ['PIT Capstone Defense', '5/18/2026', 'Smart Room'];
  final teams = isCapstone
      ? ['Team Apex', 'Team Horizon', 'Team Nexus', 'Team Pulse']
      : [
          'Team SkyLedger',
          'Team BioPulse',
          'Team SafeCity',
          'Team CodeLearners',
        ];
  final panels = isCapstone
      ? [
          [
            'Dr. Alan Turing',
            'Prof. Ada Lovelace',
            'Dr. Grace Hopper',
            'Prof. Claude Shannon',
          ],
          [
            'Dr. Maria Santos',
            'Prof. Robert Taylor',
            'Dr. Grace Miller',
            'Engr. Alan Cruz',
          ],
        ]
      : [
          ['Suarez', 'Beltran', 'Corpuz', 'Villanueva'],
          ['Tan', 'Reyes', 'Cruz', 'Santos'],
        ];

  final border = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.black,
  );
  final cellStyle = CellStyle(
    fontFamily: getFontFamily(FontFamily.Calibri),
    fontSize: 11,
    fontColorHex: ExcelColor.black,
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
    leftBorder: border,
    rightBorder: border,
    topBorder: border,
    bottomBorder: border,
  );
  final centeredStyle = cellStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Center,
  );
  final numberStyle = cellStyle.copyWith(
    horizontalAlignVal: HorizontalAlign.Right,
  );

  // Explicit widths keep every sample name and header visible on opening.
  final widths = [
    16.0,
    13.0,
    isCapstone ? 13.0 : 22.0,
    16.0,
    16.0,
    18.0,
    17.0,
    20.0,
    20.0,
  ];
  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnWidth(firstColumn + column, widths[column]);
  }
  for (var row = 0; row < 8; row++) {
    sheet.setRowHeight(firstRow + row, 15);
  }

  void mergeLabel(String start, String end, String value) {
    final startCell = CellIndex.indexByString(start);
    sheet.merge(
      startCell,
      CellIndex.indexByString(end),
      customValue: TextCellValue(value),
    );
    // Style after merging to retain the perimeter without interior borders.
    sheet.setMergedCellStyle(startCell, centeredStyle);
  }

  for (var row = 0; row < preamble.length; row++) {
    final sheetRow = firstRow + row + 1;
    mergeLabel('D$sheetRow', '$lastColumn$sheetRow', preamble[row]);
  }
  sheet.insertRowIterables(
    headers.map(TextCellValue.new).toList(),
    firstRow + 3,
    startingColumn: firstColumn,
  );
  for (var slot = 0; slot < teams.length; slot++) {
    sheet.insertRowIterables(
      [
        IntCellValue(slot + 1),
        TextCellValue('${slot + 8}:00 - ${slot + 9}:00'),
        TextCellValue(teams[slot]),
        null, // The adviser is shared by the four slots below.
        ...panels[slot ~/ 2].map(TextCellValue.new),
        if (isCapstone) null,
      ],
      firstRow + 4 + slot,
      startingColumn: firstColumn,
    );
  }
  for (var row = 3; row < 8; row++) {
    for (var column = 0; column < headers.length; column++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(
          columnIndex: firstColumn + column,
          rowIndex: firstRow + row,
        ),
      );
      cell.cellStyle = column == 0 && row > 3 ? numberStyle : cellStyle;
    }
  }
  mergeLabel('G7', 'G10', 'Prof. Alex Santos');
  if (isCapstone) {
    mergeLabel('L7', 'L10', 'Engr. Mark Mendoza');
  }

  final bytes = workbook.encode();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Unable to generate the defense schedule template.');
  }
  return bytes;
}
