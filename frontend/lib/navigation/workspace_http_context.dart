import 'package:go_router/go_router.dart';
import '../services/app/app_navigator.dart';

bool isAdminWorkspace(Map<String, dynamic>? user) {
  if (user?['role'] != 'admin' && user?['is_superuser'] != true) return false;
  final context = rootNavigatorKey.currentContext;
  final route = context == null
      ? null
      : GoRouter.maybeOf(context)?.routeInformationProvider.value.uri;
  return route == null || !route.path.startsWith('/faculty');
}

/// Capture the route before starting a request, so a later switch cannot retag it.
Map<String, String> currentWorkspaceHeaders(Uri uri) {
  if (!uri.path.startsWith('/api/')) return const {};
  final context = rootNavigatorKey.currentContext;
  if (context == null) return const {};
  final route = GoRouter.of(context).routeInformationProvider.value.uri;
  return workspaceHeadersForRoute(route, uri);
}

Map<String, String> workspaceHeadersForRoute(Uri route, Uri api) {
  if (!route.path.startsWith('/faculty') || !api.path.startsWith('/api/')) {
    return const {};
  }
  // Account, notification and public repository operations keep their own scopes.
  if (!const [
    '/api/teams',
    '/api/defense',
    '/api/grading',
    '/api/repository/deliverables',
    '/api/dashboards/faculty',
    '/api/curriculum-analytics',
    '/api/media',
    '/api/users/academic-records',
    '/api/reports',
  ].any(api.path.startsWith)) {
    return const {};
  }
  final key = route.queryParameters['workspace'];
  if (!const {'adviser', 'pit_lead', 'instructor'}.contains(key)) {
    return const {};
  }
  return {
    'X-Defensys-Workspace': key!,
    if (route.queryParameters['workspaceYear'] case final String year)
      'X-Defensys-Year': year,
    if (route.queryParameters['workspaceSection'] case final String section)
      'X-Defensys-Section': section,
  };
}

Uri workspaceRequestUri(Uri uri, Map<String, String> headers) {
  final key = headers['X-Defensys-Workspace'];
  if (key == null) return uri;
  // Analytics already uses workspace=true for response shape; narrowing also
  // travels in the header and must not overwrite that endpoint's parameter.
  if (uri.path.startsWith('/api/curriculum-analytics')) return uri;
  return uri.replace(
    queryParameters: {...uri.queryParameters, 'workspace': key},
  );
}
