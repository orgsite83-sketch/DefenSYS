import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';

class AdminOfficialClassListParseResult {
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> students;

  const AdminOfficialClassListParseResult({
    required this.metadata,
    required this.students,
  });
}

class OfficialNameParts {
  final String firstName;
  final String lastName;

  const OfficialNameParts({
    required this.firstName,
    required this.lastName,
  });
}

/// Official Class List CSV Parser logic for bulk student imports.
AdminOfficialClassListParseResult parseOfficialClassListCsv(String rawCsv) {
  final lines = rawCsv
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();

  final rows = lines.map(splitCsvLine).toList();
  return parseOfficialClassListRows(rows);
}

/// Official Class List XLSX Parser logic for bulk student imports.
AdminOfficialClassListParseResult parseOfficialClassListXlsx(List<int> bytes) {
  try {
    final workbook = xl.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      return const AdminOfficialClassListParseResult(metadata: {}, students: []);
    }
    final sheet = workbook.tables.values.first;
    try {
      for (final span in sheet.spannedItems) {
        final parts = span.split(':');
        if (parts.length != 2) continue;
        final start = xl.CellIndex.indexByString(parts[0]);
        final end = xl.CellIndex.indexByString(parts[1]);
        final startVal = sheet.cell(start).value;
        if (startVal == null) continue;
        final minR = start.rowIndex < end.rowIndex ? start.rowIndex : end.rowIndex;
        final maxR = start.rowIndex > end.rowIndex ? start.rowIndex : end.rowIndex;
        final minC = start.columnIndex < end.columnIndex ? start.columnIndex : end.columnIndex;
        final maxC = start.columnIndex > end.columnIndex ? start.columnIndex : end.columnIndex;
        for (var r = minR; r <= maxR; r++) {
          for (var c = minC; c <= maxC; c++) {
            if (r == start.rowIndex && c == start.columnIndex) continue;
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = startVal;
          }
        }
      }
    } catch (_) {}
    final rows = sheet.rows
        .map((row) => row.map((cell) => _excelCellText(cell?.value)).toList())
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    return parseOfficialClassListRows(rows);
  } catch (_) {
    return const AdminOfficialClassListParseResult(metadata: {}, students: []);
  }
}

String _excelCellText(xl.CellValue? value) {
  if (value == null) return '';
  if (value is xl.TextCellValue) {
    return (value.value.text ?? '').trim();
  }
  if (value is xl.IntCellValue) return value.value.toString();
  if (value is xl.DoubleCellValue) {
    final number = value.value;
    if (number == number.roundToDouble()) {
      return number.round().toString();
    }
    return number.toString();
  }
  if (value is xl.FormulaCellValue) return value.formula.trim();
  if (value is xl.BoolCellValue) return value.value ? 'true' : 'false';
  if (value is xl.DateCellValue) {
    final dt = value.asDateTimeLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
  if (value is xl.DateTimeCellValue) {
    final dt = value.asDateTimeLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
  if (value is xl.TimeCellValue) {
    final d = value.asDuration();
    final h = (d.inHours % 24).toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
  return value.toString().trim();
}

AdminOfficialClassListParseResult parseOfficialClassListRows(List<List<String>> rows) {
  String? csvSchoolYear;
  String? csvSemester;
  String? detectedProgram;

  final schoolYearRegex = RegExp(r'(?:s\.?y\.?\s*)?(\d{4}\s*-\s*\d{4})', caseSensitive: false);
  final semesterRegex = RegExp(r'(\d(?:st|nd|rd)?\s*sem(?:ester)?|summer)', caseSensitive: false);

  // 1. Scan for Academic Term (School Year & Semester) and Program metadata from top rows
  final preambleLimit = rows.length < 50 ? rows.length : 50;
  for (var r = 0; r < preambleLimit; r++) {
    final row = rows[r];
    for (final cell in row) {
      final trimmed = cell.trim();
      if (trimmed.isEmpty) continue;

      if (csvSchoolYear == null) {
        final syMatch = schoolYearRegex.firstMatch(trimmed);
        if (syMatch != null) {
          csvSchoolYear = syMatch.group(1);
        }
      }

      if (csvSemester == null) {
        final semMatch = semesterRegex.firstMatch(trimmed);
        if (semMatch != null) {
          final rawSem = semMatch.group(1)!.toLowerCase();
          if (rawSem.contains('1st')) {
            csvSemester = '1st Semester';
          } else if (rawSem.contains('2nd')) {
            csvSemester = '2nd Semester';
          } else if (rawSem.contains('summer')) {
            csvSemester = 'Summer';
          }
        }
      }

      if (detectedProgram == null) {
        final lower = trimmed.toLowerCase();
        if (lower.startsWith('bachelor of') ||
            lower.startsWith('bachelor in') ||
            lower.startsWith('master of') ||
            lower.startsWith('doctor of') ||
            lower == 'bsit' ||
            lower == 'bscs' ||
            lower == 'bsemc' ||
            lower == 'bsis') {
          detectedProgram = trimmed;
        }
      }
    }
  }

  final metadata = <String, dynamic>{
    if (csvSchoolYear != null) 'school_year': csvSchoolYear,
    if (csvSemester != null) 'semester': csvSemester,
    if (detectedProgram != null) 'program': detectedProgram,
  };

  // 2. Scan for key-value preamble metadata (e.g. Instructor, Section, Year Level, Subject Code, Subject Title)
  for (var i = 0; i < preambleLimit; i++) {
    final normalized = rows[i].map(normalizeHeader).toList();

    // Ignore rows that look like standard tabular headers
    final isTabularHeader = normalized.contains('id number') ||
        normalized.contains('first name') ||
        normalized.contains('last name') ||
        (normalized.contains('email') && normalized.contains('role')) ||
        _isTableHeaderRow(rows[i]);

    if (!isTabularHeader) {
      void readMeta(String key, List<String> labels) {
        if (metadata[key]?.toString().trim().isNotEmpty == true) return;
        for (final label in labels) {
          final index = normalized.indexWhere((cell) => cell == label);
          if (index == -1) continue;
          final value = nextCell(rows[i], index);
          if (value.isNotEmpty) {
            final valLower = value.toLowerCase();
            if (valLower.contains('omitted') ||
                valLower.contains('pending') ||
                valLower.contains('auto-assigned') ||
                value.startsWith('[')) {
              return;
            }
            metadata[key] = value;
          }
          return;
        }
      }

      readMeta('faculty', ['faculty', 'instructor', 'teacher', 'professor', 'prof']);
      readMeta('section', ['class section', 'section', 'class sec']);
      readMeta('year_level', ['year level', 'level', 'year']);
      readMeta('subject_code', ['subject code', 'course code', 'subj code']);
      readMeta('subject_title', ['subject title', 'course title', 'description']);
    }
  }

  if (metadata['year_level'] != null) {
    metadata['year_level'] = normalizeYearLevel(
      metadata['year_level'].toString(),
    );
  }

  // 3. Find first student table header
  var firstHeaderIndex = -1;
  for (var i = 0; i < rows.length; i++) {
    if (_isTableHeaderRow(rows[i])) {
      firstHeaderIndex = i;
      break;
    }
  }

  if (firstHeaderIndex == -1) {
    return AdminOfficialClassListParseResult(
      metadata: metadata,
      students: const [],
    );
  }

  _ClassListColumnIndices currentCols =
      _ClassListColumnIndices.fromRow(rows[firstHeaderIndex]);

  final section = metadata['section']?.toString() ?? '';
  final yearLevel = metadata['year_level']?.toString() ?? '';
  final students = <Map<String, dynamic>>[];
  final seenStudentIds = <String>{};

  // 4. Iterate all rows after firstHeaderIndex
  for (var i = firstHeaderIndex + 1; i < rows.length; i++) {
    final row = rows[i];
    final lineText = row
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .join(' ')
        .toLowerCase();
    if (lineText.isEmpty) continue;

    // A. Check if this row is a repeating table header from a new page
    if (_isTableHeaderRow(row)) {
      currentCols = _ClassListColumnIndices.fromRow(row);
      continue;
    }

    // B. Check if this row is a page interval row (USTP Print Info, Page X of Y, dates, repeat title, totals)
    if (_isPageIntervalRow(row, lineText)) {
      continue;
    }

    // C. Read fields using current column mapping
    String read(int index) =>
        index >= 0 && index < row.length ? row[index].trim() : '';

    final id = read(currentCols.idIndex);
    final name = read(currentCols.nameIndex);

    // D. Validate student row
    if (!_isValidStudentRow(id, name)) {
      continue;
    }

    // Prevent duplicate student IDs within the same file (e.g. repeated page boundary records)
    final cleanIdForDedup = id.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (seenStudentIds.contains(cleanIdForDedup)) {
      continue;
    }
    seenStudentIds.add(cleanIdForDedup);

    final splitName = splitOfficialFullName(name);
    final rawLevel = currentCols.levelIndex != -1 ? read(currentCols.levelIndex) : '';
    final rowYear = rawLevel.isNotEmpty ? normalizeYearLevel(rawLevel) : yearLevel;
    final rowSection = currentCols.sectionIndex != -1 ? read(currentCols.sectionIndex) : section;
    final contact = currentCols.contactIndex != -1 ? read(currentCols.contactIndex) : '';
    final gender = currentCols.genderIndex != -1 ? read(currentCols.genderIndex) : '';
    final program = currentCols.programIndex != -1
        ? read(currentCols.programIndex)
        : (metadata['program']?.toString() ?? '');
    final status = currentCols.statusIndex != -1 ? read(currentCols.statusIndex) : '';

    String email = currentCols.emailIndex != -1 ? read(currentCols.emailIndex) : '';
    if (email.isEmpty && id.isNotEmpty) {
      final cleanId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      email = cleanId.isNotEmpty ? '$cleanId@ustp.edu.ph' : '$id@ustp.edu.ph';
    }

    students.add({
      'id_number': id,
      'first_name': splitName.firstName,
      'last_name': splitName.lastName,
      'email': email,
      if (contact.isNotEmpty) 'phone_number': contact,
      if (contact.isNotEmpty) 'contact': contact,
      if (gender.isNotEmpty) 'gender': gender,
      if (program.isNotEmpty) 'program': program,
      if (status.isNotEmpty) 'status': status,
      'role': 'student',
      if (rowYear.isNotEmpty) 'year_level': rowYear,
      'section': rowSection,
      if (metadata['faculty'] != null) 'faculty': metadata['faculty'],
      '_fileMetadata': metadata,
    });
  }

  // 5. In case year_level was not in header metadata, infer it from cohort students
  if ((metadata['year_level'] == null || metadata['year_level'].toString().isEmpty) && students.isNotEmpty) {
    final counts = <String, int>{};
    for (final s in students) {
      final y = s['year_level']?.toString() ?? '';
      if (y.isNotEmpty) {
        counts[y] = (counts[y] ?? 0) + 1;
      }
    }
    if (counts.isNotEmpty) {
      final dominantYear = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      metadata['year_level'] = dominantYear;
    }
  }

  return AdminOfficialClassListParseResult(
    metadata: metadata,
    students: students,
  );
}

class _ClassListColumnIndices {
  final int idIndex;
  final int nameIndex;
  final int levelIndex;
  final int sectionIndex;
  final int emailIndex;
  final int contactIndex;
  final int genderIndex;
  final int programIndex;
  final int statusIndex;

  const _ClassListColumnIndices({
    required this.idIndex,
    required this.nameIndex,
    required this.levelIndex,
    required this.sectionIndex,
    required this.emailIndex,
    required this.contactIndex,
    required this.genderIndex,
    required this.programIndex,
    required this.statusIndex,
  });

  factory _ClassListColumnIndices.fromRow(List<String> row) {
    final headers = row.map(normalizeHeader).toList();
    int find(bool Function(String v) match) => headers.indexWhere(match);

    final id = find((v) =>
        v == 'id' ||
        v == 'id number' ||
        v == 'student id' ||
        (v.contains('student') &&
            (v.contains('number') ||
                v.contains('no') ||
                v.contains('id') ||
                v == 'student n')));

    final name = find((v) =>
        v == 'full name' ||
        v == 'student name' ||
        v == 'name' ||
        v == 'students');

    final level = find((v) => v == 'level' || v == 'year level' || v == 'year');
    final section = find((v) => v == 'section' || v == 'class section');
    final email = find((v) => v == 'email' || v == 'email address' || v.contains('email'));
    final contact = find((v) =>
        v == 'contact' ||
        v == 'contact no' ||
        v == 'contact no.' ||
        v == 'contact number' ||
        v == 'phone' ||
        v == 'phone no' ||
        v == 'phone no.' ||
        v == 'phone number' ||
        v == 'mobile' ||
        v == 'mobile no' ||
        v == 'mobile no.' ||
        v == 'mobile number' ||
        v == 'cellphone');
    final gender = find((v) => v == 'gender' || v == 'sex');
    final program = find((v) => v == 'program' || v == 'course' || v == 'degree');
    final status = find((v) => v == 'status' || v == 'enrollment status');

    return _ClassListColumnIndices(
      idIndex: id,
      nameIndex: name,
      levelIndex: level,
      sectionIndex: section,
      emailIndex: email,
      contactIndex: contact,
      genderIndex: gender,
      programIndex: program,
      statusIndex: status,
    );
  }
}

bool _isTableHeaderRow(List<String> row) {
  final normalized = row.map(normalizeHeader).toList();
  final hasStudentNumber = normalized.any(
    (cell) =>
        cell == 'id' ||
        cell == 'id number' ||
        cell == 'student id' ||
        (cell.contains('student') &&
            (cell.contains('number') ||
                cell.contains('no') ||
                cell.contains('id') ||
                cell == 'student n')),
  );
  final hasFullName = normalized.contains('full name') ||
      normalized.contains('student name') ||
      normalized.contains('name') ||
      normalized.contains('students');
  return hasStudentNumber && hasFullName;
}

bool _isPageIntervalRow(List<String> row, String lineText) {
  if (lineText.contains('print info')) return true;
  if (lineText.contains('page ') && (lineText.contains(' of ') || lineText.contains(' of'))) return true;
  if (lineText.contains('list of enrollment')) return true;
  if (lineText.contains('official list of enrolled students')) return true;
  if (lineText.contains('officially enrolled') && lineText.contains('registered')) return true;
  if (lineText.startsWith('total') || lineText.contains('total count') || lineText == 'total') return true;

  // Day names for print dates: e.g. "Monday 22 June 2026"
  final dayPrefixes = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  if (dayPrefixes.any((d) => lineText.startsWith(d))) return true;

  // Single term headers repeating on each page: e.g. "2026-2027 1st Semester"
  if (RegExp(r'^\d{4}\s*-\s*\d{4}\s+\d(?:st|nd|rd)?\s+sem', caseSensitive: false).hasMatch(lineText)) return true;

  // Program header repeating on each page: e.g. "Bachelor of Science in Information Technology"
  if (lineText.startsWith('bachelor of') || lineText.startsWith('bachelor in')) return true;

  return false;
}

bool _isValidStudentRow(String id, String name) {
  if (id.isEmpty || name.isEmpty) return false;

  final idLower = id.toLowerCase();
  final nameLower = name.toLowerCase();

  const blockedTerms = {
    'student no',
    'student number',
    'student id',
    'id',
    'id number',
    'student n',
    'name',
    'student name',
    'full name',
    'students',
    'program',
    'major',
    'level',
    'gender',
    'status',
    'date',
    'total',
    'print info',
  };

  if (blockedTerms.contains(idLower) || blockedTerms.contains(nameLower)) {
    return false;
  }

  if (idLower.contains('print info') || nameLower.contains('print info')) {
    return false;
  }
  if (idLower.contains('page ') || nameLower.contains('page ')) {
    return false;
  }

  // An ID must have at least one alphanumeric character
  if (!RegExp(r'[a-zA-Z0-9]').hasMatch(id)) return false;

  // A name must have at least two alphabetic characters
  final letters = RegExp(r'[a-zA-Z]').allMatches(name).length;
  if (letters < 2) return false;

  return true;
}

List<String> splitCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      values.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  values.add(buffer.toString().trim());
  return values;
}

String nextCell(List<String> row, int index) {
  for (var i = index + 1; i < row.length; i++) {
    final value = row[i].trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String normalizeHeader(String value) => value
    .trim()
    .replaceFirst('\ufeff', '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

String normalizeYearLevel(String value) {
  final lower = value.toLowerCase();
  if (lower.contains('1')) return '1st Year';
  if (lower.contains('2')) return '2nd Year';
  if (lower.contains('3')) return '3rd Year';
  if (lower.contains('4')) return '4th Year';
  return value.trim();
}

OfficialNameParts splitOfficialFullName(String value) {
  final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.contains(',')) {
    final parts = clean.split(',');
    final lastName = parts.first.trim();
    final firstName = parts.skip(1).join(',').trim();
    return OfficialNameParts(firstName: firstName, lastName: lastName);
  }
  final parts = clean.split(' ');
  if (parts.length == 1) {
    return OfficialNameParts(firstName: clean, lastName: '');
  }
  return OfficialNameParts(
    firstName: parts.first,
    lastName: parts.skip(1).join(' '),
  );
}

class DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;

  const DashedBorder({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect.deflate(0.7), Radius.circular(radius)),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 6;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
