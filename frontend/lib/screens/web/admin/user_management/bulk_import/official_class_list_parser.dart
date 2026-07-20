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
  String? csvSchoolYear;
  String? csvSemester;

  final schoolYearRegex = RegExp(r's\.?y\.?\s*(\d{4}\s*-\s*\d{4})', caseSensitive: false);
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

    readMeta('faculty', ['faculty', 'instructor']);
    readMeta('section', ['class section', 'section']);
    readMeta('year_level', ['year level', 'level']);

    final hasStudentNumber = normalized.any(
      (cell) =>
          cell.contains('student') &&
          (cell.contains('number') ||
              cell.contains('no') ||
              cell == 'student n'),
    );
    final hasFullName = normalized.contains('full name') || normalized.contains('name');
    if (hasStudentNumber && hasFullName) {
      headerIndex = i;
      break;
    }
  }

  if (metadata['year_level'] != null) {
    metadata['year_level'] = normalizeYearLevel(
      metadata['year_level'].toString(),
    );
  }
  if (headerIndex == -1) {
    return AdminOfficialClassListParseResult(
      metadata: metadata,
      students: const [],
    );
  }

  final headers = rows[headerIndex].map(normalizeHeader).toList();
  int findHeader(bool Function(String value) matches) =>
      headers.indexWhere(matches);
  final idIndex = findHeader(
    (value) =>
        value.contains('student') &&
        (value.contains('number') ||
            value.contains('no') ||
            value == 'student n'),
  );
  final nameIndex = findHeader((value) => value == 'full name' || value == 'name');
  final levelIndex = findHeader((value) => value == 'level');
  final emailIndex = findHeader((value) => value == 'email');
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
    students.add({
      'id_number': id,
      'first_name': splitName.firstName,
      'last_name': splitName.lastName,
      'email': emailIndex == -1 ? '' : read(emailIndex),
      'role': 'student',
      if (rowYear.isNotEmpty) 'year_level': rowYear,
      if (section.isNotEmpty) 'section': section,
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
