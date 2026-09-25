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
  final Map<DefensysAdminSection, Widget> _cachedSectionWidgets = {};
  final Map<DefensysAdminSection, DateTime> _lastFetchedAt = {};
  static const _refreshCooldown = Duration(seconds: 45);

  DefensysAdminSection? _currentSection;
  DefensysAdminSection? _optimisticSection;

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

    if (_optimisticSection != null && routeSection == _optimisticSection) {
      _optimisticSection = null;
    }

    final activeSection = _optimisticSection ??
        routeSection ??
        (isProfile ? null : DefensysAdminSection.overview);

    if (activeSection != null) {
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

      if (ref.read(activeAdminSectionProvider) != activeSection) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(activeAdminSectionProvider) != activeSection) {
            ref.read(activeAdminSectionProvider.notifier).setSection(activeSection);
          }
        });
      }
    }

    final isDetail = _isAdminDetailRoute(routerState);
    final activeIndex = activeSection != null
        ? DefensysAdminSection.values.indexOf(activeSection)
        : (_currentSection != null ? DefensysAdminSection.values.indexOf(_currentSection!) : 0);
    final isImport = location == AdminRoutes.defenseScheduleBulkImport;

    final shellContent = RepaintBoundary(
      child: Stack(
        children: [
          IndexedStack(
            index: activeIndex >= 0 ? activeIndex : 0,
            children: DefensysAdminSection.values.map((section) {
              if (!_loadedSections.contains(section)) {
                return const SizedBox.shrink();
              }
              if (section == DefensysAdminSection.defenseBoard && isImport) {
                return _buildSectionWidget(section);
              }
              return _cachedSectionWidgets.putIfAbsent(
                section,
                () => _buildSectionWidget(section),
              );
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
      ),
    );

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
      _refreshSectionData(section, force: true);
    }
    setState(() {
      _optimisticSection = section;
    });
    ref.read(activeAdminSectionProvider.notifier).setSection(section);
    ref.read(appRouterProvider).go(AdminRoutes.pathForSection(section));
  }

  void _refreshSectionData(DefensysAdminSection section, {bool force = false}) {
    final now = DateTime.now();
    final last = _lastFetchedAt[section];
    if (!force && last != null && now.difference(last) < _refreshCooldown) {
      return;
    }
    _lastFetchedAt[section] = now;

    switch (section) {
      case DefensysAdminSection.overview:
        ref.read(dashboardProvider('admin').notifier).fetchDashboardData(silent: true);
        break;
      case DefensysAdminSection.academicPeriods:
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
        break;
      case DefensysAdminSection.userManagement:
      case DefensysAdminSection.studentAcademicRecords:
        ref.read(userManagementProvider.notifier).fetchUsers();
        break;
      case DefensysAdminSection.studentTeams:
        ref.read(studentTeamsProvider.notifier).fetchTeams(level: 'Capstone');
        break;
      case DefensysAdminSection.gradeCenter:
        ref.read(gradeCenterProvider.notifier).fetchGrades();
        break;
      case DefensysAdminSection.rubrics:
        ref.read(rubricEngineProvider.notifier).fetchRubrics(status: '');
        break;
      case DefensysAdminSection.defenseBoard:
        ref.read(defenseBoardProvider.notifier).fetchBoard();
        break;
      case DefensysAdminSection.scheduling:
        ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        break;
      case DefensysAdminSection.defenseStages:
        ref.read(defenseStagesProvider.notifier).fetchStages();
        break;
      case DefensysAdminSection.curriculumAnalytics:
        ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics();
        break;
      case DefensysAdminSection.auditCompliance:
        ref.read(systemAuditProvider.notifier).fetch();
        break;
      case DefensysAdminSection.repositoryAudit:
        ref.read(repositoryAuditProvider.notifier).fetchEntries();
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
