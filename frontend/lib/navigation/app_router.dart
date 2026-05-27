import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/app/panelist_dashboard.dart';
import '../screens/app/student_dashboard.dart';
import '../screens/login_screen.dart';
import '../screens/terms_agreement_screen.dart';
import '../screens/web/admin/admin_shell.dart';
import '../screens/web/admin/user_management_screen.dart';
import '../screens/web/faculty/faculty_dashboard.dart';
import '../services/app_navigator.dart';
import '../services/auth_provider.dart';
import 'admin_route_paths.dart';
import 'route_pages.dart';

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(this._ref) {
    _ref.listen(authProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}

final routerRefreshProvider = Provider<RouterRefreshNotifier>((ref) {
  final notifier = RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshProvider);

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = ref.read(authProvider);
    if (auth.isRestoring) return null;

    final location = state.uri.path;
    final onLogin = location == AppRoutes.login;

    if (auth.token == null || auth.user == null) {
      return onLogin ? null : AppRoutes.login;
    }

    final user = auth.user!;
    final role = user['role']?.toString();

    if (onLogin) {
      return _defaultHomeForUser(user);
    }

    if (kIsWeb) {
      if (role == 'admin') {
        if (!location.startsWith('/admin')) {
          return AdminRoutes.overview;
        }
      } else if (role == 'faculty') {
        if (!location.startsWith('/faculty')) {
          return FacultyRoutes.dashboard;
        }
      } else {
        return AppRoutes.login;
      }
    } else {
      if (location.startsWith('/admin') || location.startsWith('/faculty')) {
        return _defaultHomeForUser(user);
      }
    }

    return null;
  }

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: refresh,
    redirect: redirect,
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (auth.isRestoring) return null;
          if (auth.token == null || auth.user == null) {
            return AppRoutes.login;
          }
          return _defaultHomeForUser(auth.user!);
        },
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) {
          final auth = ref.read(authProvider);
          return LoginScreen(sessionMessage: auth.sessionExpiredMessage);
        },
      ),
      GoRoute(
        path: AppRoutes.terms,
        builder: (context, state) {
          final extra = state.extra;
          var role = 'Student';
          Map<String, dynamic>? userData;
          if (extra is Map) {
            role = extra['role']?.toString() ?? role;
            final rawUser = extra['userData'];
            if (rawUser is Map<String, dynamic>) {
              userData = rawUser;
            } else if (rawUser is Map) {
              userData = Map<String, dynamic>.from(rawUser);
            }
          }
          userData ??= ref.read(authProvider).user;
          return TermsAgreementScreen(role: role, userData: userData);
        },
      ),
      GoRoute(
        path: AppRoutes.student,
        builder: (context, state) {
          final user = ref.read(authProvider).user;
          return StudentDashboard(userData: user);
        },
      ),
      GoRoute(
        path: AppRoutes.panelist,
        builder: (context, state) {
          final user = ref.read(authProvider).user;
          return PanelistDashboard(userData: user);
        },
      ),
      ShellRoute(
        builder: (context, state, child) {
          final user = ref.read(authProvider).user;
          return AdminShell(userData: user, routeChild: child);
        },
        routes: _adminRoutes(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final user = ref.read(authProvider).user;
          return FacultyDashboard(userData: user, routeChild: child);
        },
        routes: _facultyRoutes(),
      ),
    ],
  );
});

String _defaultHomeForUser(Map<String, dynamic> user) {
  final role = user['role']?.toString();
  if (kIsWeb) {
    if (role == 'admin') return AdminRoutes.overview;
    if (role == 'faculty') return FacultyRoutes.dashboard;
    return AppRoutes.login;
  }
  if (user['is_panelist'] == true || role == 'guest_panelist') {
    return AppRoutes.panelist;
  }
  if (role == 'faculty') return AppRoutes.panelist;
  return AppRoutes.student;
}

String homeRouteForRoleLabel(String role) => _mobileRouteForRoleLabel(role);

String _mobileRouteForRoleLabel(String role) {
  switch (role) {
    case 'Admin':
      return kIsWeb ? AdminRoutes.overview : AppRoutes.student;
    case 'Faculty':
      return kIsWeb ? FacultyRoutes.dashboard : AppRoutes.panelist;
    case 'Panelist':
      return AppRoutes.panelist;
    default:
      return AppRoutes.student;
  }
}

/// Mobile/web post-auth navigation via go_router.
Future<void> navigateToHomeAfterAuthWithRouter(
  BuildContext context, {
  required String role,
  required Map<String, dynamic> userData,
}) async {
  // Terms gate handled by caller; this only routes to home.
  if (!context.mounted) return;
  context.go(_mobileRouteForRoleLabel(role));
}

String? _redirectAdminParentOnly(GoRouterState state) {
  final path = state.uri.path;
  if (path == '/admin' || path == '/admin/') {
    return AdminRoutes.overview;
  }
  return null;
}

String? _redirectFacultyParentOnly(GoRouterState state) {
  final path = state.uri.path;
  if (path == '/faculty' || path == '/faculty/') {
    return FacultyRoutes.dashboard;
  }
  return null;
}

List<RouteBase> _adminRoutes() {
  return [
    GoRoute(
      path: '/admin',
      redirect: (_, state) => _redirectAdminParentOnly(state),
      routes: [
        GoRoute(
          path: 'overview',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'academic-periods',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'users',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'bulk-import',
              builder: (_, __) =>
                  const UserManagementScreen(initialBulkImport: true),
            ),
          ],
        ),
        GoRoute(
          path: 'student-teams',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'bulk-import',
              builder: (_, __) => const StudentTeamsBulkImportRoute(),
            ),
            GoRoute(
              path: ':teamId',
              builder: (_, state) {
                final id = int.parse(state.pathParameters['teamId']!);
                return AdminTeamDetailRoute(teamId: id);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'student-records',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'grade-center',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'grades/:gradeId',
              builder: (_, state) {
                final id = int.parse(state.pathParameters['gradeId']!);
                return AdminGradeTeamDetailRoute(gradeId: id);
              },
            ),
            GoRoute(
              path: 'events/:groupKey',
              builder: (_, state) {
                final key = state.pathParameters['groupKey']!;
                return AdminGradeEventTeamsRoute(groupKey: key);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'rubrics',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: ':rubricId/edit',
              builder: (_, state) {
                final id = state.pathParameters['rubricId']!;
                return AdminRubricEditorRoute(rubricIdParam: id);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'repository-audit',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'curriculum-analytics',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'audit-compliance',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'defense-scheduler',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'defense-board',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'defense-stages',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: ':stageId/edit',
              builder: (_, state) {
                final id = int.parse(state.pathParameters['stageId']!);
                return AdminDefenseStageEditorRoute(stageId: id);
              },
            ),
          ],
        ),
      ],
    ),
  ];
}

List<RouteBase> _facultyRoutes() {
  return [
    GoRoute(
      path: '/faculty',
      redirect: (_, state) => _redirectFacultyParentOnly(state),
      routes: [
        GoRoute(
          path: 'dashboard',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'cohort',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'student-teams',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: ':teamId',
              builder: (_, state) {
                final id = int.parse(state.pathParameters['teamId']!);
                return AdminTeamDetailRoute(teamId: id, pitLeadMode: true);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'defense-scheduler',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'defense-board',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'grade-center',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'rubrics',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'repository-audit',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'audit-compliance',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'deliverables',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'weekly-reports',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'adviser-grading',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'uploader',
          builder: (_, __) => const SizedBox.shrink(),
        ),
      ],
    ),
  ];
}
