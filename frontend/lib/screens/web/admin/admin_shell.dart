import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../navigation/app_router.dart';
import '../../../services/academic_period_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../services/dashboard_provider.dart';
import 'academic_periods_screen.dart';
import 'admin_dashboard_content.dart';
import 'audit_compliance_screen.dart';
import 'curriculum_analytics_screen.dart';
import 'defense_board_screen.dart';
import 'defense_scheduler_screen.dart';
import 'defense_stages_screen.dart';
import 'grade_center_screen.dart';
import 'rubric_engine_screen.dart';
import 'student_academic_records_screen.dart';
import 'student_teams_screen.dart';
import 'user_management_screen.dart';
import '../shared/repository_audit_screen.dart';
import 'widgets/defensys_admin_shell.dart';

final activeAdminSectionProvider =
    NotifierProvider<ActiveAdminSectionNotifier, DefensysAdminSection>(
      ActiveAdminSectionNotifier.new,
    );

class ActiveAdminSectionNotifier extends Notifier<DefensysAdminSection> {
  @override
  DefensysAdminSection build() => DefensysAdminSection.overview;

  void setSection(DefensysAdminSection section) {
    state = section;
  }
}

class AdminShell extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  final Widget? routeChild;

  const AdminShell({super.key, this.userData, this.routeChild});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardProvider('admin').notifier).fetchDashboardData();
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(dashboardProvider('admin'));
    final academicState = ref.watch(academicPeriodProvider);
    final routerState = GoRouterState.of(context);
    final location = routerState.uri.path;
    final routeSection = AdminRoutes.sectionForLocation(location);
    final activeSection =
        routeSection ?? DefensysAdminSection.overview;

    if (routeSection != null &&
        routeSection != ref.read(activeAdminSectionProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeAdminSectionProvider.notifier).setSection(routeSection);
      });
    }

    final isDetail = _isAdminDetailRoute(routerState);
    final shellContent = isDetail
        ? (widget.routeChild ?? const SizedBox.shrink())
        : _buildSectionContent(context, activeSection);

    return DefensysAdminShell(
      activeSection: activeSection,
      activeSemesterLabel: _topSemesterLabel(
        academicState.activeSemester,
        dashboardState.data?['active_semester'],
      ),
      scrollContent: false,
      onNavigate: (section) => _goToSection(section),
      onLogout: _logout,
      child: shellContent,
    );
  }

  void _goToSection(DefensysAdminSection section) {
    ref.read(appRouterProvider).go(AdminRoutes.pathForSection(section));
  }

  /// Detail / nested routes use [routeChild] from go_router; top-level sections
  /// are built locally so sidebar navigation works even when shell child is empty.
  bool _isAdminDetailRoute(GoRouterState state) {
    final params = state.pathParameters;
    if (params.containsKey('teamId') ||
        params.containsKey('gradeId') ||
        params.containsKey('groupKey') ||
        params.containsKey('stageId') ||
        params.containsKey('rubricId')) {
      return true;
    }
    return state.uri.path.endsWith('/bulk-import');
  }

  Widget _buildSectionContent(
    BuildContext context,
    DefensysAdminSection section,
  ) {
    switch (section) {
      case DefensysAdminSection.overview:
        return AdminDashboardContent(
          onNavigate: _goToSection,
        );
      case DefensysAdminSection.academicPeriods:
        return const AcademicPeriodsScreen();
      case DefensysAdminSection.userManagement:
        return const UserManagementScreen();
      case DefensysAdminSection.studentTeams:
        return const StudentTeamsScreen(mode: TeamListMode.capstoneAdmin);
      case DefensysAdminSection.studentAcademicRecords:
        return const StudentAcademicRecordsScreen();
      case DefensysAdminSection.gradeCenter:
        return const GradeCenterScreen();
      case DefensysAdminSection.rubricEngine:
        return const RubricEngineScreen();
      case DefensysAdminSection.repositoryAudit:
        return const RepositoryAuditScreen();
      case DefensysAdminSection.curriculumAnalytics:
        return const CurriculumAnalyticsScreen();
      case DefensysAdminSection.auditCompliance:
        return const AuditComplianceScreen();
      case DefensysAdminSection.scheduling:
        return const DefenseSchedulerScreen();
      case DefensysAdminSection.defenseBoard:
        return const DefenseBoardScreen();
      case DefensysAdminSection.defenseStages:
        return const DefenseStagesScreen();
    }
  }

  Future<void> _logout() async {
    final router = GoRouter.of(context);
    if (!await confirmLogout(context)) return;
    await ref.read(authProvider.notifier).logout();
    router.go(AppRoutes.login);
  }

  String _topSemesterLabel(
    Map<String, dynamic>? activePeriod,
    dynamic dashboardLabel,
  ) {
    if (activePeriod != null) {
      return 'Active Sem: ${activePeriod['school_year'] ?? 'Configured'}';
    }

    final label = dashboardLabel?.toString().trim() ?? '';
    if (label.isEmpty || label == 'Not configured' || label == 'Loading...') {
      return 'No Active Semester';
    }

    final schoolYear = RegExp(r'\d{4}-\d{4}').firstMatch(label)?.group(0);
    return 'Active Sem: ${schoolYear ?? label}';
  }
}
