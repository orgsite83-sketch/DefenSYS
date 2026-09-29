import 'package:excel/excel.dart';

List<int> generateOfficialTeamRosterExcelBytes({required bool isCapstone}) {
  final excel = Excel.createExcel();
  final sheetName = isCapstone ? 'defensys_team_roster_template' : 'defensys_pit_team_roster_template';
  
  // Set default sheet name
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != sheetName) {
    excel.rename(defaultSheet, sheetName);
  }
  final sheet = excel[sheetName];

  final thinBorder = Border(borderStyle: BorderStyle.Thin);
  final noBorder = Border(borderStyle: BorderStyle.None);

  // Headers: regular Arial (not bold, matching Image 2)
  final headerStyle = CellStyle(
    bold: false,
    fontFamily: getFontFamily(FontFamily.Arial),
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
    leftBorder: thinBorder,
    rightBorder: thinBorder,
    topBorder: thinBorder,
    bottomBorder: thinBorder,
  );

  final headerCenterStyle = CellStyle(
    bold: false,
    fontFamily: getFontFamily(FontFamily.Arial),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    leftBorder: thinBorder,
    rightBorder: thinBorder,
    topBorder: thinBorder,
    bottomBorder: thinBorder,
  );

  final metaLabelStyle = CellStyle(
    bold: false,
    fontFamily: getFontFamily(FontFamily.Arial),
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
    leftBorder: thinBorder,
    rightBorder: thinBorder,
    topBorder: thinBorder,
    bottomBorder: thinBorder,
  );

  final metaValueStyle = CellStyle(
    bold: false,
    fontFamily: getFontFamily(FontFamily.Arial),
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
    leftBorder: thinBorder,
    rightBorder: thinBorder,
    topBorder: thinBorder,
    bottomBorder: thinBorder,
  );

  // Set column widths matching Excel layout (Col A is margin, Col G is spacer)
  sheet.setColumnWidth(0, 4.0);  // Col A: Margin
  sheet.setColumnWidth(1, 24.0); // Col B: Team Name
  sheet.setColumnWidth(2, 46.0); // Col C: Project / Module
  sheet.setColumnWidth(3, 14.0); // Col D: Section
  sheet.setColumnWidth(4, 24.0); // Col E: Adviser / Instructor
  sheet.setColumnWidth(5, 24.0); // Col F: Team Members
  sheet.setColumnWidth(6, 4.0);  // Col G: Separator spacer
  sheet.setColumnWidth(7, 24.0); // Col H: Team Name / Meta Label
  sheet.setColumnWidth(8, 30.0); // Col I: Module / Meta Value
  sheet.setColumnWidth(9, 14.0); // Col J: Section
  sheet.setColumnWidth(10, 24.0);// Col K: Adviser / Instructor
  sheet.setColumnWidth(11, 24.0);// Col L: Team Members

  // Data definitions
  final leftTeams = isCapstone ? _capstone4ATeams : _pit2ATeams;
  final rightTeams = isCapstone ? _capstone4BTeams : _pit2BTeams;

  final leftSection = isCapstone ? 'BSIT-4A' : 'BSIT-2A';
  final rightSection = isCapstone ? 'BSIT-4B' : 'BSIT-2B';

  final systemName = isCapstone ? 'Hospital Management System' : 'Societree';
  final projectManager = 'Juan Dela Cruz';

  final projectColTitle = isCapstone ? 'Capstone Project' : 'PIT Project';
  final adviserColTitle = isCapstone ? 'Adviser' : 'Instructor';

  void setCell(int col, int row, String text, CellStyle style) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(text);
    cell.cellStyle = style;
  }

  void setBlockOuterBorder({
    required int col,
    required int startRow,
    required int endRow,
    required String text,
    HorizontalAlign align = HorizontalAlign.Left,
  }) {
    for (var r = startRow; r <= endRow; r++) {
      final cellStyle = CellStyle(
        bold: false,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: align,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinBorder,
        rightBorder: thinBorder,
        topBorder: r == startRow ? thinBorder : noBorder,
        bottomBorder: r == endRow ? thinBorder : noBorder,
      );
      setCell(col, r, r == startRow ? text : '', cellStyle);
    }
  }

  void setMembersBlockOuterBorder({
    required int col,
    required int startRow,
    required int endRow,
    required List<String> members,
    HorizontalAlign align = HorizontalAlign.Left,
  }) {
    for (var r = startRow; r <= endRow; r++) {
      final cellStyle = CellStyle(
        bold: false,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: align,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinBorder,
        rightBorder: thinBorder,
        topBorder: r == startRow ? thinBorder : noBorder,
        bottomBorder: r == endRow ? thinBorder : noBorder,
      );
      final mIdx = r - startRow;
      final text = mIdx < members.length ? members[mIdx] : '';
      setCell(col, r, text, cellStyle);
    }
  }

  // --- ROW 4 (row index 3 in 0-indexed) ---
  // Left: Table 1 Headers (Cols B to F, index 1 to 5)
  setCell(1, 3, 'Team Name', headerStyle);
  setCell(2, 3, projectColTitle, headerStyle);
  setCell(3, 3, 'Section', headerCenterStyle);
  setCell(4, 3, adviserColTitle, headerCenterStyle);
  setCell(5, 3, 'Team Members', headerStyle);

  // Right: System Name metadata (Cols H to I, index 7 to 8)
  setCell(7, 3, 'System Name:', metaLabelStyle);
  setCell(8, 3, systemName, metaValueStyle);

  // --- ROW 5 (row index 4 in 0-indexed) ---
  // Right: Project Manager metadata (Cols H to I, index 7 to 8)
  setCell(7, 4, 'Project Manager:', metaLabelStyle);
  setCell(8, 4, projectManager, metaValueStyle);

  // --- ROW 6 (row index 5 in 0-indexed) ---
  // Right: Table 2 Headers (Cols H to L, index 7 to 11)
  setCell(7, 5, 'Team Name', headerStyle);
  setCell(8, 5, 'Module', headerStyle);
  setCell(9, 5, 'Section', headerCenterStyle);
  setCell(10, 5, adviserColTitle, headerCenterStyle);
  setCell(11, 5, 'Team Members', headerStyle);

  // --- LEFT COHORT (BSIT-4A / BSIT-2A) ---
  // Rows 5 to 36 (row index 4 to 35)
  for (var t = 0; t < leftTeams.length; t++) {
    final team = leftTeams[t];
    final startR = 4 + t * 4;

    // Team Name (Col 1): outer box border for the 4-row block, no interior horizontal lines
    setBlockOuterBorder(
      col: 1,
      startRow: startR,
      endRow: startR + 3,
      text: team.team,
    );

    // Project (Col 2): outer box border for the 4-row block, no interior horizontal lines
    setBlockOuterBorder(
      col: 2,
      startRow: startR,
      endRow: startR + 3,
      text: team.item,
    );

    // Team Members (Col 5): outer box border for the 4-student block, no interior horizontal lines
    setMembersBlockOuterBorder(
      col: 5,
      startRow: startR,
      endRow: startR + 3,
      members: team.members,
    );
  }

  void setMergedColumn({
    required int col,
    required int startRow,
    required int endRow,
    required String text,
  }) {
    // 1. Merge first so spannedItems registers the merged cell range
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: startRow),
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: endRow),
    );

    // 2. Set cells and outer borders AFTER merge so Excel preserves cell boundaries in sheetData
    for (var r = startRow; r <= endRow; r++) {
      final cellStyle = CellStyle(
        bold: false,
        fontFamily: getFontFamily(FontFamily.Arial),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        leftBorder: thinBorder,
        rightBorder: thinBorder,
        topBorder: r == startRow ? thinBorder : noBorder,
        bottomBorder: r == endRow ? thinBorder : noBorder,
      );
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r));
      if (r == startRow) {
        cell.value = TextCellValue(text);
      }
      cell.cellStyle = cellStyle;
    }
  }

  // Section column for left cohort (Row index 4 to 35: 32 rows merged)
  setMergedColumn(
    col: 3,
    startRow: 4,
    endRow: 35,
    text: leftSection,
  );

  // Adviser column for left cohort
  if (isCapstone) {
    // Adviser 1: Prof. Alex Santos (Rows 4 to 19: 16 rows merged)
    setMergedColumn(
      col: 4,
      startRow: 4,
      endRow: 19,
      text: 'Prof. Alex Santos',
    );

    // Adviser 2: Prof. Elena Ramos (Rows 20 to 35: 16 rows merged)
    setMergedColumn(
      col: 4,
      startRow: 20,
      endRow: 35,
      text: 'Prof. Elena Ramos',
    );
  } else {
    // Single Instructor: Prof. Alex Santos (Rows 4 to 35: 32 rows merged)
    setMergedColumn(
      col: 4,
      startRow: 4,
      endRow: 35,
      text: 'Prof. Alex Santos',
    );
  }

  // --- RIGHT COHORT (BSIT-4B / BSIT-2B) ---
  // Rows 7 to 38 (row index 6 to 37)
  for (var t = 0; t < rightTeams.length; t++) {
    final team = rightTeams[t];
    final startR = 6 + t * 4;

    // Team Name (Col 7): outer box border for the 4-row block, no interior horizontal lines
    setBlockOuterBorder(
      col: 7,
      startRow: startR,
      endRow: startR + 3,
      text: team.team,
    );

    // Module (Col 8): outer box border for the 4-row block, no interior horizontal lines
    setBlockOuterBorder(
      col: 8,
      startRow: startR,
      endRow: startR + 3,
      text: team.item,
    );

    // Team Members (Col 11): outer box border for the 4-student block, no interior horizontal lines
    setMembersBlockOuterBorder(
      col: 11,
      startRow: startR,
      endRow: startR + 3,
      members: team.members,
    );
  }

  // Section column for right cohort (Row index 6 to 37: 32 rows merged)
  setMergedColumn(
    col: 9,
    startRow: 6,
    endRow: 37,
    text: rightSection,
  );

  // Adviser column for right cohort
  if (isCapstone) {
    // Adviser 1: Prof. Roberto Gomez (Rows 6 to 21: 16 rows merged)
    setMergedColumn(
      col: 10,
      startRow: 6,
      endRow: 21,
      text: 'Prof. Roberto Gomez',
    );

    // Adviser 2: Prof. Cynthia Morales (Rows 22 to 37: 16 rows merged)
    setMergedColumn(
      col: 10,
      startRow: 22,
      endRow: 37,
      text: 'Prof. Cynthia Morales',
    );
  } else {
    // Single Instructor: Prof. Alex Santos (Rows 6 to 37: 32 rows merged)
    setMergedColumn(
      col: 10,
      startRow: 6,
      endRow: 37,
      text: 'Prof. Alex Santos',
    );
  }

  final bytes = excel.save();
  return bytes ?? [];
}

const _capstone4ATeams = [
  (
    team: 'Team SkyLedger',
    item: 'Alumni Career Tracker',
    members: ['Marcus Villar', 'Patricia Ong', 'Ethan Salazar', 'Zoe Castillo'],
  ),
  (
    team: 'Team BioPulse',
    item: 'AI-Powered Vital Triage & Disease Predictor',
    members: ['Ryan Torres', 'Nina Villanueva', 'Diego Garcia', 'Patricia Ramos'],
  ),
  (
    team: 'Team SafeCity',
    item: 'Smart City IoT Infrastructure & Asset Sentinel',
    members: ['Carlos Bautista', 'Sophia Santos', 'Miguel Cruz', 'Isabella Alcantara'],
  ),
  (
    team: 'Team CodeLearners',
    item: 'Campus Event Hub',
    members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
  ),
  (
    team: 'Team CyberGuard',
    item: 'Automated Penetration Testing & Threat Hunter',
    members: ['Gabriel Mendoza', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
  ),
  (
    team: 'Team AgriSense',
    item: 'Smart Agriculture Crop & Soil Monitoring',
    members: ['Adrian Valdez', 'Stephanie Yap', 'Jerome De Leon', 'Camille Roxas'],
  ),
  (
    team: 'Team EduTrack',
    item: 'Student Performance Analytics & Early Warning',
    members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
  ),
  (
    team: 'Team EcoRoute',
    item: 'Intelligent Fleet Logistics & Route Optimizer',
    members: ['Miguel Torres', 'Angela Flores', 'Francis Dizon', 'Rhea Salazar'],
  ),
];

const _capstone4BTeams = [
  (
    team: 'Team MedRecord',
    item: 'Patient Records',
    members: ['Juan Dela Cruz', 'Maria Santos', 'Mark Reyes', 'Anna Garcia'],
  ),
  (
    team: 'Team MedBilling',
    item: 'Billing',
    members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
  ),
  (
    team: 'Team MedSchedule',
    item: 'Appointments',
    members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
  ),
  (
    team: 'Team MedPharma',
    item: 'Pharmacy',
    members: ['Kevin Villanueva', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
  ),
  (
    team: 'Team MedTriage',
    item: 'Triage',
    members: ['Cedric Valdez', 'Leila Soriano', 'Paolo Ramos', 'Diana Cruz'],
  ),
  (
    team: 'Team MedLab',
    item: 'Laboratory',
    members: ['Anthony Lim', 'Katrina Santos', 'Justin Ocampo', 'Bianca Reyes'],
  ),
  (
    team: 'Team MedInventory',
    item: 'Inventory',
    members: ['Patrick Mendoza', 'Christine Torres', 'Bea Bautista', 'Danica Sotto'],
  ),
  (
    team: 'Team MedWards',
    item: 'Wards',
    members: ['Kenneth Salazar', 'Nicole Dizon', 'Jerome Navarro', 'Alyssa Castillo'],
  ),
];

const _pit2ATeams = [
  (
    team: 'Group 1',
    item: 'Smart Campus Navigation System',
    members: ['Juan Dela Cruz', 'Maria Santos', 'Mark Reyes', 'Anna Garcia'],
  ),
  (
    team: 'Group 2',
    item: 'Automated Library Portal',
    members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
  ),
  (
    team: 'Group 3',
    item: 'Alumni Career Tracker',
    members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
  ),
  (
    team: 'Group 4',
    item: 'Event Booking System',
    members: ['Kevin Villanueva', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
  ),
  (
    team: 'Group 5',
    item: 'Hostel Reservation Portal',
    members: ['Cedric Valdez', 'Leila Soriano', 'Paolo Ramos', 'Diana Cruz'],
  ),
  (
    team: 'Group 6',
    item: 'Campus Lost & Found Sentinel',
    members: ['Anthony Lim', 'Katrina Santos', 'Justin Ocampo', 'Bianca Reyes'],
  ),
  (
    team: 'Group 7',
    item: 'Student Tutoring Exchange',
    members: ['Patrick Mendoza', 'Christine Torres', 'Lorenzo Garcia', 'Bea Bautista'],
  ),
  (
    team: 'Group 8',
    item: 'Green Campus Energy Tracker',
    members: ['Kenneth Salazar', 'Nicole Dizon', 'Jerome Navarro', 'Alyssa Castillo'],
  ),
];

const _pit2BTeams = [
  (
    team: 'Group 1',
    item: 'Site Module',
    members: ['Juan Dela Cruz', 'Maria Santos', 'Mark Reyes', 'Anna Garcia'],
  ),
  (
    team: 'Group 2',
    item: 'Arcu Module',
    members: ['David Aquino', 'Sarah Ocampo', 'Daniel Rivera', 'Jasmine Morales'],
  ),
  (
    team: 'Group 3',
    item: 'Events Module',
    members: ['Carlo Ramos', 'Nicole Bautista', 'John Mendoza', 'Patricia Cruz'],
  ),
  (
    team: 'Group 4',
    item: 'Membership Module',
    members: ['Kevin Villanueva', 'Bea Castro', 'Christian Lim', 'Joshua Navarro'],
  ),
  (
    team: 'Group 5',
    item: 'Finance Module',
    members: ['Cedric Valdez', 'Leila Soriano', 'Paolo Ramos', 'Diana Cruz'],
  ),
  (
    team: 'Group 6',
    item: 'Elections Module',
    members: ['Anthony Lim', 'Katrina Santos', 'Justin Ocampo', 'Bianca Reyes'],
  ),
  (
    team: 'Group 7',
    item: 'Publication Module',
    members: ['Patrick Mendoza', 'Christine Torres', 'Lorenzo Garcia', 'Bea Bautista'],
  ),
  (
    team: 'Group 8',
    item: 'Certificates Module',
    members: ['Kenneth Salazar', 'Nicole Dizon', 'Jerome Navarro', 'Alyssa Castillo'],
  ),
];
