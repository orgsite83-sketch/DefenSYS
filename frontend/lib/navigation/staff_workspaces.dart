import 'admin_route_paths.dart';

/// A URL-addressable duty, independent of the account's primary role.
class StaffWorkspace {
  const StaffWorkspace(this.key, this.label, {this.year, this.section});
  final String key;
  final String label;
  final String? year;
  final String? section;

  String get location => switch (key) {
    'admin' => AdminRoutes.overview,
    'panelist' => AppRoutes.panelist,
    'documenter' => AppRoutes.documenter,
    'faculty' => FacultyRoutes.dashboard,
    _ => at(FacultyRoutes.dashboard),
  };

  String at(String path, {Map<String, String> parameters = const {}}) => Uri(
    path: path,
    queryParameters: {
      ...parameters,
      'workspace': key,
      if (year != null) 'workspaceYear': year!,
      if (section != null) 'workspaceSection': section!,
    },
  ).toString();

  bool matches(Uri uri) => switch (key) {
    'admin' => uri.path.startsWith('/admin'),
    'panelist' => uri.path == AppRoutes.panelist,
    'documenter' => uri.path.startsWith('/documenter'),
    _ =>
      uri.path.startsWith('/faculty') &&
          uri.queryParameters['workspace'] == key &&
          (year == null || uri.queryParameters['workspaceYear'] == year) &&
          (section == null ||
              uri.queryParameters['workspaceSection'] == section),
  };

  static List<StaffWorkspace> available(Map<String, dynamic> user) {
    if (!const {'faculty', 'admin'}.contains(user['role'])) return const [];
    final roles = (user['staff_workspaces'] as Map?) ?? const {};
    final options = <StaffWorkspace>[
      if (user['role'] == 'admin') const StaffWorkspace('admin', 'Admin'),
      if (user['is_adviser'] == true)
        const StaffWorkspace('adviser', 'Project Adviser'),
      if (user['is_pit_lead'] == true &&
          const {
            '1st Year',
            '2nd Year',
            '3rd Year',
          }.contains(user['pit_lead_year']))
        StaffWorkspace(
          'pit_lead',
          'PIT Lead · ${user['pit_lead_year']}',
          year: user['pit_lead_year'] as String,
        ),
      for (final item
          in (roles['pit_instructor_sections'] as List? ?? const []))
        if (item is Map)
          StaffWorkspace(
            'instructor',
            'PIT Instructor · ${item['year_level']} (${item['section']})',
            year: item['year_level']?.toString(),
            section: item['section']?.toString(),
          ),
      if (user['is_panelist'] == true)
        const StaffWorkspace('panelist', 'Panelist'),
      if (user['is_documenter'] == true)
        const StaffWorkspace('documenter', 'Documenter'),
    ];
    if (user['role'] == 'faculty' &&
        !options.any(
          (option) =>
              const {'adviser', 'pit_lead', 'instructor'}.contains(option.key),
        ) &&
        user['has_staff_workspace'] != false) {
      options.add(const StaffWorkspace('faculty', 'Staff web workspace'));
    }
    return options;
  }

  static StaffWorkspace? resolve(Map<String, dynamic> user, String location) {
    final uri = Uri.tryParse(location);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    for (final option in available(user)) {
      if (option.matches(uri)) return option;
    }
    return null;
  }
}
