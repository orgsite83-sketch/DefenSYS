import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../navigation/app_router.dart';
import '../../../navigation/web_section_navigation.dart';
import '../../../services/academic_period_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../services/unsaved_changes_provider.dart';
import '../../../utils/unsaved_changes.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../services/academic/student_teams_provider.dart';
import '../../../services/academic/curriculum_analytics_provider.dart';
import '../../../services/admin/user_management_provider.dart';
import '../../../services/academic/student_academic_records_provider.dart';
import '../../../services/grading/grade_center_provider.dart';
import '../../../services/grading/rubric_engine_provider.dart';
import '../../../services/defense_board_provider.dart';
import '../../../services/defense_stages_provider.dart';
import '../../../services/defense/defense_scheduler_provider.dart';
import '../../../services/system_audit_provider.dart';
import '../../../services/project_archive_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/app/data_refresh_provider.dart';
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
  final StatefulNavigationShell? navigationShell;

  const AdminShell({
    super.key,
    this.userData,
    this.routeChild,
    this.navigationShell,
  });

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  final _refreshGate = WebSectionRefreshGate();
  final _sectionState = WebSectionState();
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
  void dispose() {
    _sectionState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Selectively watch only the active semester info so changes elsewhere in
    // academicPeriodProvider or dashboardProvider do not cause full-shell rebuild cascades.
    final activeSemester = ref.watch(
      academicPeriodProvider.select((s) => s.activeSemester),
    );
    final dashboardActiveSemester = ref.watch(
      dashboardProvider('admin').select((s) => s.data?['active_semester']),
    );

    final routerState = GoRouterState.of(context);
    final location = routerState.uri.path;
    final routeSection = AdminRoutes.sectionForLocation(location);
    final isProfile = location == '/admin/profile';

    final activeSection =
        routeSection ?? (isProfile ? null : DefensysAdminSection.overview);

    if (activeSection != null &&
        ref.read(activeAdminSectionProvider) != activeSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(activeAdminSectionProvider) != activeSection) {
          ref
              .read(activeAdminSectionProvider.notifier)
              .setSection(activeSection);
        }
      });
    }

    if (activeSection != null && activeSection != _currentSection) {
      _currentSection = activeSection;
      final area = _dataAreaForSection(activeSection);
      final revision = ref.read(dataRefreshProvider)[area] ?? 0;
      if (_refreshGate.activate(
        AdminRoutes.pathForSection(activeSection),
        revision: revision,
        // Scheduling also depends on changes made by other users or sessions.
        alwaysRefresh: activeSection == DefensysAdminSection.scheduling,
      )) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _currentSection == activeSection) {
            _refreshSectionData(activeSection);
          }
        });
      }
    }

    final shellContent =
        widget.navigationShell ??
        widget.routeChild ??
        _buildSectionWidget(activeSection ?? DefensysAdminSection.overview);

    return DefensysAdminShell(
      activeSection: activeSection,
      isProfileActive: isProfile,
      activeSemesterLabel: _topSemesterLabel(
        activeSemester,
        dashboardActiveSemester,
      ),
      scrollContent: false,
      onNavigate: (section) => _goToSection(section),
      onLogout: _logout,
      child: WebSectionStateScope(notifier: _sectionState, child: shellContent),
    );
  }

  void _goToSection(DefensysAdminSection section) async {
    final hasUnsaved = ref.read(unsavedChangesProvider);
    if (hasUnsaved) {
      final saveDraftCallback = ref.read(unsavedChangesSaveDraftProvider);
      final action = await showDiscardUnsavedChangesDialog(
        context,
        onSaveDraft: saveDraftCallback,
      );
      if (action == UnsavedChangesAction.cancel || !mounted) return;
      if (action == UnsavedChangesAction.saveDraft &&
          saveDraftCallback != null) {
        final ok = await saveDraftCallback();
        if (!ok || !mounted) return;
      }
    }
    ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    ref.read(unsavedChangesProvider.notifier).setDirty(false);
    if (hasUnsaved && _currentSection != null) {
      final sourcePath = AdminRoutes.pathForSection(_currentSection!);
      _sectionState.reset(sourcePath);
      GoRouter.of(context).go(sourcePath);
      // Let the source branch record its clean root before restoring the target.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (!resumeWebSection(
      widget.navigationShell,
      AdminRoutes.pathForSection(section),
    )) {
      ref.read(appRouterProvider).go(AdminRoutes.pathForSection(section));
    }
  }

  DataArea _dataAreaForSection(DefensysAdminSection section) =>
      switch (section) {
        DefensysAdminSection.overview => DataArea.dashboard,
        DefensysAdminSection.academicPeriods => DataArea.academicPeriods,
        DefensysAdminSection.userManagement => DataArea.users,
        DefensysAdminSection.studentAcademicRecords => DataArea.academicRecords,
        DefensysAdminSection.studentTeams => DataArea.teams,
        DefensysAdminSection.gradeCenter => DataArea.grades,
        DefensysAdminSection.rubrics => DataArea.rubrics,
        DefensysAdminSection.defenseBoard => DataArea.defenseBoard,
        DefensysAdminSection.scheduling => DataArea.scheduler,
        DefensysAdminSection.defenseStages => DataArea.defenseStages,
        DefensysAdminSection.curriculumAnalytics => DataArea.analytics,
        DefensysAdminSection.auditCompliance => DataArea.audit,
        DefensysAdminSection.repositoryAudit => DataArea.repository,
      };

  // Root screens perform their first load. Revisit refreshes are centralized,
  // throttled, and retain provider filters instead of resetting their defaults.
  void _refreshSectionData(DefensysAdminSection section) {
    switch (section) {
      case DefensysAdminSection.overview:
        ref
            .read(dashboardProvider('admin').notifier)
            .fetchDashboardData(silent: true);
      case DefensysAdminSection.academicPeriods:
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
      case DefensysAdminSection.userManagement:
      case DefensysAdminSection.studentAcademicRecords:
        ref.read(userManagementProvider.notifier).fetchUsers();
        ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
      case DefensysAdminSection.studentTeams:
        ref.read(studentTeamsProvider.notifier).fetchTeams();
      case DefensysAdminSection.gradeCenter:
        ref.read(gradeCenterProvider.notifier).fetchGrades();
      case DefensysAdminSection.rubrics:
        ref.read(rubricEngineProvider.notifier).fetchRubrics();
      case DefensysAdminSection.defenseBoard:
        ref.read(defenseBoardProvider.notifier).fetchBoard();
        ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
      case DefensysAdminSection.scheduling:
        ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
      case DefensysAdminSection.defenseStages:
        ref.read(defenseStagesProvider.notifier).fetchStages();
      case DefensysAdminSection.curriculumAnalytics:
        ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics();
      case DefensysAdminSection.auditCompliance:
        ref.read(systemAuditProvider.notifier).fetch();
      case DefensysAdminSection.repositoryAudit:
        ref.read(repositoryAuditProvider.notifier).fetchEntries();
    }
  }

  Widget _buildSectionWidget(
    DefensysAdminSection section, {
    bool isImport = false,
  }) {
    switch (section) {
      case DefensysAdminSection.overview:
        return AdminDashboardContent(onNavigate: _goToSection);
      case DefensysAdminSection.academicPeriods:
        return const AcademicPeriodsScreen();
      case DefensysAdminSection.userManagement:
        return const UserManagementScreen();
      case DefensysAdminSection.studentTeams:
        return const StudentTeamsScreen(mode: TeamListMode.capstoneAdmin);
      case DefensysAdminSection.studentAcademicRecords:
        return const UserManagementScreen(
          initialUserTab: UserManagementTab.students,
        );
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
      final action = await showDiscardUnsavedChangesDialog(
        context,
        onSaveDraft: saveDraftCallback,
      );
      if (action == UnsavedChangesAction.cancel || !mounted) return;
      if (action == UnsavedChangesAction.saveDraft &&
          saveDraftCallback != null) {
        final ok = await saveDraftCallback();
        if (!ok || !mounted) return;
      }
    }
    if (!await confirmLogout(context)) return;
    if (!mounted) return;

    ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    ref.read(unsavedChangesProvider.notifier).setDirty(false);

    // Defensively pop any lingering modal or popup routes on root navigator
    // so no orphaned ModalBarrier is left covering the screen on the login page:
    final rootNav = Navigator.of(context, rootNavigator: true);
    while (rootNav.canPop()) {
      rootNav.pop();
    }

    FocusManager.instance.primaryFocus?.unfocus();

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

/// Root screens live in the section Navigator, alongside their detail routes.
/// Switching sidebar sections keeps both the root and its navigation stack.
class AdminSectionContent extends StatelessWidget {
  const AdminSectionContent({
    super.key,
    required this.section,
    this.isImport = false,
  });

  final DefensysAdminSection section;
  final bool isImport;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey(
      WebSectionStateScope.generationOf(
        context,
        AdminRoutes.pathForSection(section),
      ),
    ),
    child: context
        .findAncestorStateOfType<_AdminShellState>()!
        ._buildSectionWidget(section, isImport: isImport),
  );
}
