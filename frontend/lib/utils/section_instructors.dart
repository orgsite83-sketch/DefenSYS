List<Map<String, dynamic>> sectionInstructorsForTeam(
  Map<String, dynamic> team,
) {
  final instructors = (team['instructors'] as List? ?? [])
      .whereType<Map>()
      .map((i) => Map<String, dynamic>.from(i))
      .toList();
  if (instructors.isNotEmpty) return instructors;
  final name = team['instructor_name']?.toString().trim() ?? '';
  return name.isEmpty
      ? []
      : [
          {'faculty_name': name},
        ];
}
