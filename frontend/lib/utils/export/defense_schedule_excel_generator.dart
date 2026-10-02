import 'package:excel/excel.dart';

/// Shared sample data keeps the blueprint and downloaded workbook in sync.
class DefenseScheduleTemplateDay {
  const DefenseScheduleTemplateDay({
    required this.stage,
    required this.date,
    required this.room,
    required this.teams,
    required this.adviser,
    required this.panels,
    this.documenter = '',
  });

  final String stage, date, room, adviser, documenter;
  final List<String> teams;
  final List<List<String>> panels;

  String timeForSlot(int slot) => '${slot + 8}:00 - ${slot + 9}:00';
}

List<DefenseScheduleTemplateDay> defenseScheduleTemplateDays({
  required bool isCapstone,
}) {
  final panels = isCapstone
      ? const [
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
      : const [
          ['Suarez', 'Beltran', 'Corpuz', 'Villanueva'],
          ['Tan', 'Reyes', 'Cruz', 'Santos'],
        ];
  final stage = isCapstone ? 'Concept Proposal' : 'PIT Capstone Defense';
  final room = isCapstone ? 'Room 301' : 'Smart Room';
  return [
    DefenseScheduleTemplateDay(
      stage: stage,
      date: isCapstone ? '6/18/2026' : '5/18/2026',
      room: room,
      teams: isCapstone
          ? const ['Team Apex', 'Team Horizon', 'Team Nexus', 'Team Pulse']
          : const [
              'Team SkyLedger',
              'Team BioPulse',
              'Team SafeCity',
              'Team CodeLearners',
            ],
      adviser: 'Prof. Alex Santos',
      panels: panels,
      documenter: isCapstone ? 'Engr. Mark Mendoza' : '',
    ),
    DefenseScheduleTemplateDay(
      stage: stage,
      date: isCapstone ? '6/19/2026' : '5/19/2026',
      room: room,
      teams: isCapstone
          ? const ['Team Orbit', 'Team Beacon', 'Team Summit', 'Team Harbor']
          : const [
              'Team CyberGuard',
              'Team AgriSense',
              'Team EduTrack',
              'Team EcoRoute',
            ],
      adviser: 'Prof. Jamie Reyes',
      panels: panels.reversed.toList(),
      documenter: isCapstone ? 'Engr. Dana Cruz' : '',
    ),
  ];
}

/// Builds the editable timetable shown in the schedule import blueprint.
List<int> generateDefenseScheduleExcelBytes({required bool isCapstone}) {
  final workbook = Excel.createExcel();
  const sheetName = 'Defense Schedule';
  workbook.rename(workbook.getDefaultSheet()!, sheetName);
  final sheet = workbook[sheetName];
  // Leave columns A-C and rows 1-2 blank, matching the inset reference layout.
  const firstColumn = 3;
  const firstRow = 2;
  final days = defenseScheduleTemplateDays(isCapstone: isCapstone);
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

  var blockStart = firstRow;
  for (final day in days) {
    final preamble = [day.stage, day.date, day.room];
    final blockLength = preamble.length + 1 + day.teams.length;
    for (var row = 0; row < blockLength; row++) {
      sheet.setRowHeight(blockStart + row, 15);
    }
    for (var row = 0; row < preamble.length; row++) {
      final sheetRow = blockStart + row + 1;
      mergeLabel('D$sheetRow', '$lastColumn$sheetRow', preamble[row]);
    }
    sheet.insertRowIterables(
      headers.map(TextCellValue.new).toList(),
      blockStart + 3,
      startingColumn: firstColumn,
    );
    for (var slot = 0; slot < day.teams.length; slot++) {
      sheet.insertRowIterables(
        [
          IntCellValue(slot + 1),
          TextCellValue(day.timeForSlot(slot)),
          TextCellValue(day.teams[slot]),
          null, // Shared adviser cells are merged within this day only.
          ...day.panels[slot ~/ 2].map(TextCellValue.new),
          if (isCapstone) null,
        ],
        blockStart + 4 + slot,
        startingColumn: firstColumn,
      );
    }
    for (var row = 3; row < blockLength; row++) {
      for (var column = 0; column < headers.length; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: firstColumn + column,
            rowIndex: blockStart + row,
          ),
        );
        cell.cellStyle = column == 0 && row > 3 ? numberStyle : cellStyle;
      }
    }
    final firstSlotRow = blockStart + 5;
    final lastSlotRow = blockStart + blockLength;
    mergeLabel('G$firstSlotRow', 'G$lastSlotRow', day.adviser);
    if (isCapstone) {
      mergeLabel('L$firstSlotRow', 'L$lastSlotRow', day.documenter);
    }
    // One blank row separates complete day blocks on the same worksheet.
    blockStart += blockLength + 1;
  }

  final bytes = workbook.encode();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Unable to generate the defense schedule template.');
  }
  return bytes;
}
