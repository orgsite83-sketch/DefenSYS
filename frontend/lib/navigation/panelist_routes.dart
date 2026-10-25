import 'admin_route_paths.dart';

/// Shared destinations for nominations, imports, and notification links.
abstract final class PanelistRoutes {
  static String? importReturn(String? value) =>
      const {
        FacultyRoutes.defenseScheduleBulkImport,
        AdminRoutes.defenseScheduleBulkImport,
      }.contains(value)
      ? value
      : null;

  static String directory({
    required bool admin,
    String section = 'faculty',
    int? requestId,
    Iterable<int> facultyIds = const [],
    String? returnTo,
  }) => Uri(
    path: admin ? AdminRoutes.users : FacultyRoutes.cohort,
    queryParameters: {
      'tab': admin ? 'faculty' : 'panelists',
      if (admin) 'view': 'panelists',
      if (section != 'faculty' || requestId != null)
        'section': requestId != null && section == 'faculty'
            ? 'requests'
            : section,
      if (requestId != null) 'request': '$requestId',
      if (facultyIds.isNotEmpty) 'faculty': facultyIds.toSet().join(','),
      if (importReturn(returnTo) != null) 'returnTo': returnTo!,
    },
  ).toString();

  static Set<int> facultyIds(String? value) => (value ?? '')
      .split(',')
      .map(int.tryParse)
      .whereType<int>()
      .where((id) => id > 0)
      .toSet();
}
