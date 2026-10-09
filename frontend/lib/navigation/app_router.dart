import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/app/panelist_dashboard.dart';
import '../screens/app/documenter_dashboard.dart';
import '../screens/web/faculty/documenter/minutes_form_screen.dart';
import '../screens/app/student_dashboard.dart';
import '../screens/app/app_settings_screen.dart';
import '../screens/app/web_workspace_only_screen.dart';
import '../screens/login_screen.dart';
import '../screens/guest/guest_evaluation_entry.dart';
import '../screens/password_reset_confirm_screen.dart';
import '../screens/app/student/profile_edit_screen.dart';
import '../screens/terms_agreement_screen.dart';
import '../screens/web/admin/admin_shell.dart';
import '../screens/web/faculty/faculty_dashboard.dart';
import '../services/app_navigator.dart';
import '../services/auth_provider.dart';
import 'admin_route_paths.dart';
import 'route_pages.dart';
import 'workspace_access.dart';
import 'workspace_preference.dart';

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(this._ref) {
    _ref.listen(authProvider, (_, __) => notifyListeners());
    _ref.listen(workspacePreferenceProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}

final routerRefreshProvider = Provider<RouterRefreshNotifier>((ref) {
  final notifier = RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  if (kIsWeb) {
    GoRouter.optionURLReflectsImperativeAPIs = true;
  }
  final refresh = ref.watch(routerRefreshProvider);

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = ref.read(authProvider);
    if (auth.isRestoring) return null;

    final location = state.uri.path;
    final onLogin = location == AppRoutes.login;
    final isPasswordReset = location.startsWith('/password-reset/confirm');
    final onGuestEntry = location == AppRoutes.guestEntry;
    if (auth.token == null || auth.user == null) {
      if (location.startsWith('/guest/')) {
        return onGuestEntry ? null : AppRoutes.guestEntry;
      }
      return (onLogin || isPasswordReset) ? null : AppRoutes.login;
    }

    if (auth.requiresTerms &&
        auth.user!['role'] != 'guest_panelist' &&
        location != AppRoutes.terms &&
        !onGuestEntry) {
      return AppRoutes.terms;
    }
    // An invitation link must open its own code even when this browser already
    // has a guest session for another stage/event. Other guest routes remain
    // confined to the evaluation workspace.
    if (onGuestEntry &&
        (state.uri.queryParameters['code']?.trim().isNotEmpty ?? false)) {
      return null;
    }
    if ((location == AppRoutes.login || location == '/') &&
        WorkspaceAccess.canDocument(auth.user!) &&
        ref.read(workspacePreferenceProvider).isLoading) {
      return null;
    }
    return WorkspaceAccess.redirect(
      auth.user!,
      location,
      preferredWorkspace: ref.read(workspacePreferenceProvider).value,
    );
  }

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: refresh,
    redirect: redirect,
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(
        path: AppRoutes.guestEntry,
        builder: (context, state) => GuestEvaluationEntry(
          initialCode: state.uri.queryParameters['code'],
        ),
      ),
      GoRoute(
        path: AppRoutes.guestDefenses,
        builder: (_, __) => Consumer(
          builder: (context, ref, child) {
            final auth = ref.watch(authProvider);
            if (auth.isRestoring) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (auth.user?['role'] != 'guest_panelist' || auth.token == null) {
              return const SizedBox.shrink();
            }
            return PanelistDashboard(userData: auth.user);
          },
        ),
      ),
      GoRoute(
        path: '/',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (auth.isRestoring) return null;
          if (auth.token == null || auth.user == null) {
            return AppRoutes.login;
          }
          return WorkspaceAccess.home(
            auth.user!,
            preferredWorkspace: ref.read(workspacePreferenceProvider).value,
          );
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
        path: AppRoutes.passwordResetConfirm,
        builder: (context, state) {
          final uid = state.pathParameters['uid']!;
          final token = state.pathParameters['token']!;
          return ConfirmPasswordResetScreen(uid: uid, token: token);
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
          return Consumer(
            builder: (context, ref, child) {
              final auth = ref.watch(authProvider);
              if (auth.isRestoring) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (auth.user?['role'] != 'student' || auth.token == null) {
                return const SizedBox.shrink();
              }
              return StudentDashboard(userData: auth.user);
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.panelist,
        builder: (context, state) {
          return Consumer(
            builder: (context, ref, child) {
              final auth = ref.watch(authProvider);
              if (auth.isRestoring) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (auth.user == null ||
                  auth.token == null ||
                  !WorkspaceAccess.canEvaluate(auth.user!)) {
                return const SizedBox.shrink();
              }
              return PanelistDashboard(userData: auth.user);
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const AppSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.documenter,
        builder: (_, __) => const DocumenterDashboard(),
        routes: [
          GoRoute(
            path: 'minutes/:scheduleId',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['scheduleId'] ?? '');
              if (id == null) {
                return const Scaffold(
                  body: Center(child: Text('Invalid defense.')),
                );
              }
              return MinutesFormScreen(
                scheduleId: id,
                onBack: () => context.go(AppRoutes.documenter),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.webWorkspaceOnly,
        builder: (_, __) => const WebWorkspaceOnlyScreen(),
      ),
      ..._adminRoutes(),
      ..._facultyRoutes(),
    ],
  );

  router.routerDelegate.addListener(() {
    final location = router.routerDelegate.currentConfiguration.uri.path;
    final routeSection = AdminRoutes.sectionForLocation(location);
    if (routeSection != null) {
      final current = ref.read(activeAdminSectionProvider);
      if (routeSection != current) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentNow = ref.read(activeAdminSectionProvider);
          if (routeSection != currentNow) {
            ref
                .read(activeAdminSectionProvider.notifier)
                .setSection(routeSection);
          }
        });
      }
    }
  });

  return router;
});

String homeRouteForUser(Map<String, dynamic> user) =>
    WorkspaceAccess.home(user);

/// Mobile/web post-auth navigation via go_router.
Future<void> navigateToHomeAfterAuthWithRouter(
  BuildContext context, {
  required String role,
  required Map<String, dynamic> userData,
}) async {
  // Terms gate handled by caller; this only routes to home.
  if (!context.mounted) return;
  context.go(homeRouteForUser(userData));
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
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              AdminShell(userData: _routeUser(context), navigationShell: shell),
          branches: _adminSectionRoutes()
              .map(
                (route) => StatefulShellBranch(
                  initialLocation: '/admin/${route.path}',
                  routes: [
                    route,
                    if (route.path == 'defense-board')
                      GoRoute(
                        path: 'defense-board/import',
                        pageBuilder: _adminSectionPage,
                      ),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    ),
  ];
}

Map<String, dynamic>? _routeUser(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(authProvider).user;

List<GoRoute> _adminSectionRoutes() {
  return [
    GoRoute(path: 'overview', pageBuilder: _adminSectionPage),
    GoRoute(
      path: 'profile',
      pageBuilder: (_, __) => const NoTransitionPage(child: ProfileScreen()),
    ),
    GoRoute(
      path: 'academic-periods',
      pageBuilder: _adminSectionPage,
      routes: [
        GoRoute(
          path: ':semesterId',
          builder: (_, state) {
            final id = int.tryParse(state.pathParameters['semesterId'] ?? '');
            return AdminSemesterDetailRoute(semesterId: id);
          },
        ),
      ],
    ),
    GoRoute(path: 'users', pageBuilder: _adminSectionPage),
    GoRoute(
      path: 'student-teams',
      pageBuilder: _adminSectionPage,
      routes: [
        GoRoute(
          path: ':teamId',
          builder: (_, state) {
            final id = int.parse(state.pathParameters['teamId']!);
            return AdminTeamDetailRoute(teamId: id);
          },
        ),
      ],
    ),
    GoRoute(path: 'student-records', pageBuilder: _adminSectionPage),
    GoRoute(
      path: 'grade-center',
      pageBuilder: _adminSectionPage,
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
      pageBuilder: _adminSectionPage,
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
    GoRoute(path: 'project-archive', pageBuilder: _adminSectionPage),
    GoRoute(path: 'repository-audit', pageBuilder: _adminSectionPage),
    GoRoute(path: 'curriculum-analytics', pageBuilder: _adminSectionPage),
    GoRoute(path: 'audit-compliance', pageBuilder: _adminSectionPage),
    GoRoute(path: 'defense-scheduler', pageBuilder: _adminSectionPage),
    GoRoute(path: 'defense-board', pageBuilder: _adminSectionPage),
    GoRoute(
      path: 'defense-stages',
      pageBuilder: _adminSectionPage,
      routes: [
        GoRoute(
          path: ':stageId/edit',
          builder: (_, state) {
            final id = int.parse(state.pathParameters['stageId']!);
            final tab =
                int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
            return AdminDefenseStageEditorRoute(stageId: id, initialTab: tab);
          },
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
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => FacultyDashboard(
            userData: _routeUser(context),
            navigationShell: shell,
          ),
          branches: _facultySectionRoutes()
              .map(
                (route) => StatefulShellBranch(
                  initialLocation: '/faculty/${route.path}',
                  routes: [
                    route,
                    if (route.path == 'defense-board')
                      GoRoute(
                        path: 'defense-board/import',
                        pageBuilder: _facultySectionPage,
                      ),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    ),
  ];
}

List<GoRoute> _facultySectionRoutes() {
  return [
    GoRoute(path: 'dashboard', pageBuilder: _facultySectionPage),
    GoRoute(
      path: 'cohort',
      pageBuilder: _facultySectionPage,
      routes: [
        GoRoute(
          path: ':sectionName',
          builder: (_, state) {
            final sectionName = state.pathParameters['sectionName']!;
            return PitLeadCohortSectionDetailRoute(sectionName: sectionName);
          },
        ),
      ],
    ),
    GoRoute(path: 'pit-student-import', pageBuilder: _facultySectionPage),
    GoRoute(
      path: 'student-teams',
      pageBuilder: _facultySectionPage,
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
    GoRoute(path: 'pit-instructors', pageBuilder: _facultySectionPage),
    GoRoute(path: 'defense-scheduler', pageBuilder: _facultySectionPage),
    GoRoute(path: 'defense-board', pageBuilder: _facultySectionPage),
    GoRoute(
      path: 'grade-center',
      pageBuilder: _facultySectionPage,
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
    GoRoute(path: 'rubrics', pageBuilder: _facultySectionPage),
    GoRoute(path: 'project-archive', pageBuilder: _facultySectionPage),
    GoRoute(path: 'repository-audit', pageBuilder: _facultySectionPage),
    GoRoute(path: 'audit-compliance', pageBuilder: _facultySectionPage),
    GoRoute(path: 'deliverables', pageBuilder: _facultySectionPage),
    GoRoute(path: 'weekly-reports', pageBuilder: _facultySectionPage),
    GoRoute(path: 'adviser-grading', pageBuilder: _facultySectionPage),
    GoRoute(path: 'uploader', pageBuilder: _facultySectionPage),
    GoRoute(path: 'pit-events', pageBuilder: _facultySectionPage),
  ];
}

Page<void> _adminSectionPage(
  BuildContext context,
  GoRouterState state,
) => NoTransitionPage(
  // Board/import are two URLs for the same workspace, not two mounted boards.
  key: state.uri.path.startsWith(AdminRoutes.defenseBoard)
      ? const ValueKey('admin-defense-board')
      : state.pageKey,
  child: AdminSectionContent(
    section: AdminRoutes.sectionForLocation(state.uri.path)!,
    isImport: state.uri.path == AdminRoutes.defenseScheduleBulkImport,
  ),
);

Page<void> _facultySectionPage(BuildContext context, GoRouterState state) =>
    NoTransitionPage(
      key: FacultyRoutes.sectionForLocation(state.uri.path) == 'defense_board'
          ? const ValueKey('faculty-defense-board')
          : state.pageKey,
      child: FacultySectionContent(
        section: FacultyRoutes.sectionForLocation(state.uri.path)!,
      ),
    );
