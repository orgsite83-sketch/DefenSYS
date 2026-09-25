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

  final schoolYearRegex = RegExp(r'(?:s\.?y\.?\s*)?(\d{4}\s*-\s*\d{4})', caseSensitive: false);
  final semesterRegex = RegExp(r'(\d(?:st|nd|rd)?\s*sem(?:ester)?|summer)', caseSensitive: false);

  for (final row in rows) {
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
    }
    if (csvSchoolYear != null && csvSemester != null) break;
  }

  final metadata = <String, dynamic>{
    if (csvSchoolYear != null) 'school_year': csvSchoolYear,
    if (csvSemester != null) 'semester': csvSemester,
  };
  var headerIndex = -1;

  for (var i = 0; i < rows.length; i++) {
    final normalized = rows[i].map(normalizeHeader).toList();

    // Check if this row is the student table header
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
    if (hasStudentNumber && hasFullName) {
      headerIndex = i;
      break;
    }

    // Only read key-value preamble metadata from lines before table headers,
    // and ignore rows that look like standard tabular headers (with id/name/email/role columns)
    final isTabularHeader = normalized.contains('id number') ||
        normalized.contains('first name') ||
        normalized.contains('last name') ||
        (normalized.contains('email') && normalized.contains('role'));

    if (!isTabularHeader) {
      void readMeta(String key, List<String> labels) {
        if (metadata[key]?.toString().trim().isNotEmpty == true) return;
        for (final label in labels) {
          final index = normalized.indexWhere((cell) => cell == label);
          if (index == -1) continue;
          final value = nextCell(rows[i], index);
          if (value.isNotEmpty) metadata[key] = value;
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
  if (headerIndex == -1) {
    return const AdminOfficialClassListParseResult(
      metadata: {},
      students: [],
    );
  }

  final headers = rows[headerIndex].map(normalizeHeader).toList();
  int findHeader(bool Function(String value) matches) =>
      headers.indexWhere(matches);
  final idIndex = findHeader(
    (value) =>
        value == 'id' ||
        value == 'id number' ||
        value == 'student id' ||
        (value.contains('student') &&
            (value.contains('number') ||
                value.contains('no') ||
                value.contains('id') ||
                value == 'student n')),
  );
  final nameIndex = findHeader(
    (value) =>
        value == 'full name' ||
        value == 'student name' ||
        value == 'name' ||
        value == 'students',
  );
  final levelIndex = findHeader((value) => value == 'level' || value == 'year level' || value == 'year');
  final sectionIndex = findHeader((value) => value == 'section' || value == 'class section');
  final emailIndex = findHeader((value) => value == 'email' || value == 'email address' || value.contains('email'));
  final contactIndex = findHeader(
    (value) =>
        value == 'contact' ||
        value == 'contact no' ||
        value == 'contact no.' ||
        value == 'contact number' ||
        value == 'phone' ||
        value == 'phone no' ||
        value == 'phone no.' ||
        value == 'phone number' ||
        value == 'mobile' ||
        value == 'mobile no' ||
        value == 'mobile no.' ||
        value == 'mobile number' ||
        value == 'cellphone',
  );
  final section = metadata['section']?.toString() ?? '';
  final yearLevel = metadata['year_level']?.toString() ?? '';
  final students = <Map<String, dynamic>>[];

  for (final row in rows.skip(headerIndex + 1)) {
    String read(int index) =>
        index >= 0 && index < row.length ? row[index].trim() : '';
    final id = read(idIndex);
    final name = read(nameIndex);
    if (id.isEmpty || name.isEmpty) continue;
    final splitName = splitOfficialFullName(name);
    final rowYear = levelIndex != -1
        ? normalizeYearLevel(read(levelIndex))
        : yearLevel;
    final rowSection = sectionIndex != -1 ? read(sectionIndex) : section;
    final contact = contactIndex == -1 ? '' : read(contactIndex);
    students.add({
      'id_number': id,
      'first_name': splitName.firstName,
      'last_name': splitName.lastName,
      'email': emailIndex == -1 ? '' : read(emailIndex),
      if (contact.isNotEmpty) 'phone_number': contact,
      if (contact.isNotEmpty) 'contact': contact,
      'role': 'student',
      if (rowYear.isNotEmpty) 'year_level': rowYear,
      'section': rowSection,
      if (metadata['faculty'] != null) 'faculty': metadata['faculty'],
      '_fileMetadata': metadata,
    });
  }

  return AdminOfficialClassListParseResult(
    metadata: metadata,
    students: students,
  );
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
