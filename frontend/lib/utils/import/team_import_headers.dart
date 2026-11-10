/// Normalize labels only; roster cell values and internal field names stay intact.
String normalizeTeamImportHeader(String value) {
  final label = value
      .replaceAll('\ufeff', '')
      .replaceAll('*', '')
      .replaceAll(':', '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  return const {'team', 'group', 'group name', 'group_name'}.contains(label)
      ? 'team name'
      : label;
}

bool isTeamImportNameHeader(String value) =>
    const {'team name', 'team_name'}.contains(normalizeTeamImportHeader(value));

bool isTeamImportMemberHeader(String value) => const {
  'team members',
  'team_members',
  'members',
  'names',
  'student name',
  'student_name',
  'student names',
  'student',
  'students',
  'member_ids',
}.contains(normalizeTeamImportHeader(value));
