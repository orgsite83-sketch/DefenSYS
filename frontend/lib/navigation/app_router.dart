import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/app/panelist_dashboard.dart';
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
    return WorkspaceAccess.redirect(auth.user!, location);
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
          return homeRouteForUser(auth.user!);
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
        path: AppRoutes.webWorkspaceOnly,
        builder: (_, __) => const WebWorkspaceOnlyScreen(),
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
        GoRoute(
          path: 'overview',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'profile',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: ProfileScreen()),
        ),
        GoRoute(
          path: 'academic-periods',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
          routes: [
            GoRoute(
              path: ':semesterId',
              builder: (_, state) {
                final id = int.tryParse(
                  state.pathParameters['semesterId'] ?? '',
                );
                return AdminSemesterDetailRoute(semesterId: id);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'users',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'student-teams',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
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
        GoRoute(
          path: 'student-records',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'grade-center',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
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
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
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
          path: 'project-archive',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'repository-audit',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'curriculum-analytics',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'audit-compliance',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'defense-scheduler',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
        ),
        GoRoute(
          path: 'defense-board',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
          routes: [
            GoRoute(
              path: 'import',
              pageBuilder: (_, __) =>
                  const NoTransitionPage(child: SizedBox.shrink()),
            ),
          ],
        ),
        GoRoute(
          path: 'defense-stages',
          pageBuilder: (_, __) =>
              const NoTransitionPage(child: SizedBox.shrink()),
          routes: [
            GoRoute(
              path: ':stageId/edit',
              builder: (_, state) {
                final id = int.parse(state.pathParameters['stageId']!);
                final tab =
                    int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
                return AdminDefenseStageEditorRoute(
                  stageId: id,
                  initialTab: tab,
                );
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
        GoRoute(path: 'dashboard', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: 'cohort',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: ':sectionName',
              builder: (_, state) {
                final sectionName = state.pathParameters['sectionName']!;
                return PitLeadCohortSectionDetailRoute(
                  sectionName: sectionName,
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: 'pit-student-import',
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
          path: 'pit-instructors',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'defense-scheduler',
          builder: (_, __) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: 'defense-board',
          builder: (_, __) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'import',
              builder: (_, __) => const SizedBox.shrink(),
            ),
          ],
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
        GoRoute(path: 'rubrics', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: 'project-archive',
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
        GoRoute(path: 'uploader', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: 'pit-events',
          builder: (_, __) => const SizedBox.shrink(),
        ),
      ],
    ),
  ];
}
