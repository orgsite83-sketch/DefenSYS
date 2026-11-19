import 'admin_route_paths.dart';

/// Explicit task context is distinct from ordinary, retained module filters.
class AdminAttentionContext {
  const AdminAttentionContext({
    required this.kind,
    required this.year,
    required this.semesterId,
    this.fromOverview = false,
  });
  final String kind, year;
  final int? semesterId;
  final bool fromOverview;
  static const years = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

  static AdminAttentionContext? fromQuery(Map<String, String> query) {
    if (!query.containsKey('attention')) return null;
    return AdminAttentionContext(
      kind: query['attention'] ?? '',
      year: query['year_level'] ?? '',
      semesterId: int.tryParse(query['semester_id'] ?? ''),
      fromOverview: query['fromOverview'] == '1',
    );
  }

  bool get valid =>
      (semesterId ?? 0) > 0 &&
      (kind == 'enrollment' || kind == 'team_assignment') &&
      (years.contains(year) ||
          (kind == 'enrollment' && year == 'unclassified'));

  Map<String, String> get query => {
    'attention': kind,
    'year_level': year,
    'semester_id': '$semesterId',
    if (fromOverview) 'fromOverview': '1',
  };

  String get location => kind == 'team_assignment'
      ? Uri(
          path: '${AdminRoutes.studentTeams}/creation',
          queryParameters: {
            ...query,
            'tab': 'import',
            'level': '$year Capstone',
          },
        ).toString()
      : Uri(
          path: AdminRoutes.users,
          queryParameters: {...query, 'tab': 'students', 'view': 'enrollment'},
        ).toString();

  String get identity => '$kind:$semesterId:$year';
}
