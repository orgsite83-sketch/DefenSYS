import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../navigation/app_router.dart';
import '../../../services/academic_period_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../services/unsaved_changes_provider.dart';
import '../../../utils/unsaved_changes.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/academic/student_academic_records_provider.dart';
import '../../../services/academic/student_teams_provider.dart';
import '../../../services/academic/curriculum_analytics_provider.dart';
import '../../../services/admin/user_management_provider.dart';
import '../../../services/grading/grade_center_provider.dart';
import '../../../services/grading/rubric_engine_provider.dart';
import '../../../services/defense_board_provider.dart';
import '../../../services/defense_stages_provider.dart';
import '../../../services/defense/defense_scheduler_provider.dart';
import '../../../services/system_audit_provider.dart';
import '../../../services/project_archive_provider.dart';
import 'academic_periods_screen.dart';
import 'admin_dashboard_content.dart';
import 'audit_compliance_screen.dart';
import 'curriculum_analytics_screen.dart';
import 'defense_board_screen.dart';
import 'defense_scheduler/defense_scheduler_screen.dart';
import 'defense_stages_screen.dart';
import 'grade_center_screen.dart';
import 'rubric_engine_screen.dart';
import 'student_teams_screen.dart';
import 'user_management_screen.dart';
import '../shared/project_archive/project_archive_screen.dart';
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
  final Set<DefensysAdminSection> _loadedSections = {};
  DefensysAdminSection? _currentSection;

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

    _loadedSections.add(activeSection);

    if (_currentSection != activeSection) {
      final oldSection = _currentSection;
      _currentSection = activeSection;
      if (oldSection != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _refreshSectionData(activeSection);
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(activeAdminSectionProvider) != activeSection) {
        ref.read(activeAdminSectionProvider.notifier).setSection(activeSection);
      }
    });

    final isDetail = _isAdminDetailRoute(routerState);
    final activeIndex = DefensysAdminSection.values.indexOf(activeSection);

    final shellContent = Stack(
      children: [
        IndexedStack(
          index: activeIndex >= 0 ? activeIndex : 0,
          children: DefensysAdminSection.values.map((section) {
            if (_loadedSections.contains(section)) {
              return _buildSectionWidget(section);
            }
            return const SizedBox.shrink();
          }).toList(),
        ),
        if (widget.routeChild != null)
          Positioned.fill(
            child: Offstage(
              offstage: !isDetail,
              child: ColoredBox(
                color: DefensysUi.bgLight,
                child: widget.routeChild!,
              ),
            ),
          ),
      ],
    );

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

  void _goToSection(DefensysAdminSection section) async {
    final hasUnsaved = ref.read(unsavedChangesProvider);
    if (hasUnsaved) {
      final saveDraftCallback = ref.read(unsavedChangesSaveDraftProvider);
      final action = await showDiscardUnsavedChangesDialog(context, onSaveDraft: saveDraftCallback);
      if (action == UnsavedChangesAction.cancel || !mounted) return;
      if (action == UnsavedChangesAction.saveDraft && saveDraftCallback != null) {
        final ok = await saveDraftCallback();
        if (!ok || !mounted) return;
      }
    }
    ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    ref.read(unsavedChangesProvider.notifier).setDirty(false);
    if (section == _currentSection) {
      _refreshSectionData(section);
    }
    ref.read(activeAdminSectionProvider.notifier).setSection(section);
    ref.read(appRouterProvider).go(AdminRoutes.pathForSection(section));
  }

  void _refreshSectionData(DefensysAdminSection section) {
    switch (section) {
      case DefensysAdminSection.overview:
        ref.read(dashboardProvider('admin').notifier).fetchDashboardData(silent: true);
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.academicPeriods:
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.userManagement:
      case DefensysAdminSection.studentAcademicRecords:
        ref.read(userManagementProvider.notifier).fetchUsers();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
        break;
      case DefensysAdminSection.studentTeams:
        ref.read(studentTeamsProvider.notifier).fetchTeams(level: 'Capstone');
        ref.read(userManagementProvider.notifier).fetchUsers();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.gradeCenter:
        ref.read(gradeCenterProvider.notifier).fetchGrades();
        ref.read(defenseStagesProvider.notifier).fetchStages();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.rubrics:
        ref.read(rubricEngineProvider.notifier).fetchRubrics(status: '');
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.defenseBoard:
        ref.read(defenseBoardProvider.notifier).fetchBoard();
        ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.scheduling:
        ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.defenseStages:
        ref.read(defenseStagesProvider.notifier).fetchStages();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.curriculumAnalytics:
        ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.auditCompliance:
        ref.read(systemAuditProvider.notifier).fetch();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.repositoryAudit:
        ref.read(repositoryAuditProvider.notifier).fetchEntries();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
    }
  }

  /// Detail / nested routes use [routeChild] from go_router; top-level sections
  /// are built locally so sidebar navigation works even when shell child is empty.
  bool _isAdminDetailRoute(GoRouterState state) {
    if (state.uri.path == '/admin/profile') return true;
    final params = state.pathParameters;
    return params.containsKey('teamId') ||
        params.containsKey('gradeId') ||
        params.containsKey('groupKey') ||
        params.containsKey('stageId') ||
        params.containsKey('rubricId');
  }

  Widget _buildSectionWidget(DefensysAdminSection section) {
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
        return const UserManagementScreen(initialUserTab: UserManagementTab.students);
      case DefensysAdminSection.gradeCenter:
        return const GradeCenterScreen();
      case DefensysAdminSection.rubrics:
        return const RubricEngineScreen();
      case DefensysAdminSection.repositoryAudit:
        return const ProjectArchiveScreen();
      case DefensysAdminSection.curriculumAnalytics:
        return const CurriculumAnalyticsScreen();
      case DefensysAdminSection.auditCompliance:
        return const AuditComplianceScreen();
      case DefensysAdminSection.scheduling:
        return DefenseSchedulerScreen(
          onBack: () => _goToSection(DefensysAdminSection.defenseBoard),
        );
      case DefensysAdminSection.defenseBoard:
        final isImport =
            GoRouterState.of(context).uri.path == AdminRoutes.defenseScheduleBulkImport;
        return DefenseBoardScreen(initialBulkImport: isImport);
      case DefensysAdminSection.defenseStages:
        return const DefenseStagesScreen();
    }
  }

  Future<void> _logout() async {
    final router = GoRouter.of(context);
    final hasUnsaved = ref.read(unsavedChangesProvider);
    if (hasUnsaved) {
      final saveDraftCallback = ref.read(unsavedChangesSaveDraftProvider);
      final action = await showDiscardUnsavedChangesDialog(context, onSaveDraft: saveDraftCallback);
      if (action == UnsavedChangesAction.cancel || !mounted) return;
      if (action == UnsavedChangesAction.saveDraft && saveDraftCallback != null) {
        final ok = await saveDraftCallback();
        if (!ok || !mounted) return;
      }
    }
    if (!await confirmLogout(context)) return;
    ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    ref.read(unsavedChangesProvider.notifier).setDirty(false);
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
