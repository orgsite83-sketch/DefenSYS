/// Assignment-derived sample data shared by the download and its blueprint.
class ClassListTemplate {
  const ClassListTemplate({
    required this.level,
    required this.section,
    required this.term,
    required this.instructor,
  });

  final String level, section, term, instructor;

  int get year =>
      int.tryParse(RegExp(r'[1-4]').firstMatch(level)?.group(0) ?? '') ?? 1;
  String get ordinal => const {1: '1st', 2: '2nd', 3: '3rd', 4: '4th'}[year]!;
  String get yearLevel => '$ordinal Year';
  String get studentLevel => '$ordinal Yr.';
  String get classSection =>
      section.trim().isNotEmpty ? section.trim() : 'BSIT-${year}A';
  String get subjectCode => '${level.contains('PIT') ? 'PIT' : 'CAP'}${year}01';
  String get subjectTitle =>
      level.contains('PIT') ? 'PIT Project' : 'Capstone Project';
  String get filename => importTemplateFilename(
    kind: 'class-list',
    section: classSection,
    level: yearLevel,
    extension: 'csv',
  );

  String get csv {
    final program =
        RegExp(
          r'^[A-Za-z]+',
        ).firstMatch(classSection)?.group(0)?.toUpperCase() ??
        'BSIT';
    final rows = <List<String>>[
      ['OFFICIAL LIST OF ENROLLED STUDENTS'],
      ['Academic Term', term],
      ['Subject Code', subjectCode, 'Subject Title', subjectTitle],
      ['Academic Units', '3 (Lab Units: 1)', 'Mode', 'Lecture and Laboratory'],
      ['Instructor', instructor],
      ['Class Section', classSection],
      ['Year Level', yearLevel],
      ['Schedule(s)', 'M 1:00 PM - 3:00 PM'],
      [],
      [
        '#',
        'Student Number',
        'Full Name',
        'Program',
        'Gender',
        'Level',
        'Email',
        'Contact',
      ],
    ];
    const names = [
      'DELA CRUZ, Juan',
      'SANTOS, Maria',
      'REYES, Mark',
      'GARCIA, Anna',
    ];
    for (var i = 0; i < names.length; i++) {
      rows.add([
        '${i + 1}',
        '2024-0000${i + 1}',
        names[i],
        program,
        i.isEven ? 'M' : 'F',
        studentLevel,
        '20240000${i + 1}@university.edu.ph',
        '0917000000${i + 1}',
      ]);
    }
    return '${rows.map((row) => row.map(_csvCell).join(',')).join('\n')}\n';
  }
}

String _csvCell(String value) => RegExp('[,"\r\n]').hasMatch(value)
    ? '"${value.replaceAll('"', '""')}"'
    : value;

String importTemplateFilename({
  required String kind,
  String? section,
  String? level,
  required String extension,
}) {
  String slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final parts = [
    'defensys',
    kind,
    if (section?.trim().isNotEmpty == true) section!,
    if (level?.trim().isNotEmpty == true) level!,
  ];
  return '${parts.map(slug).where((part) => part.isNotEmpty).join('-')}.$extension';
}

String templateInstructorName(Map<String, dynamic>? user) {
  final fullName = user?['full_name']?.toString().trim() ?? '';
  if (fullName.isNotEmpty) return fullName;
  final parts = [user?['first_name'], user?['last_name']]
      .map((value) => value?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .join(' ');
  return parts.isNotEmpty
      ? parts
      : user?['username']?.toString() ?? 'Sample Instructor';
}

String templateTermLabel(Map<String, dynamic>? semester) {
  final display = semester?['display_name']?.toString().trim() ?? '';
  if (display.isNotEmpty) return display;
  final year = semester?['school_year']?.toString().trim() ?? '';
  final term =
      (semester?['label'] ?? semester?['semester'])?.toString().trim() ?? '';
  return [
        year,
        term,
      ].where((value) => value.isNotEmpty).join(' ').trim().isNotEmpty
      ? [year, term].where((value) => value.isNotEmpty).join(' ')
      : 'Active Semester';
}
