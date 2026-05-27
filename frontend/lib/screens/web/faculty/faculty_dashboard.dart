import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../navigation/admin_route_paths.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/offline_banner.dart';
import '../../../widgets/confirm_dialog.dart';
import '../shared/capstone_deliverables_screen.dart';
import '../shared/repository_audit_screen.dart';
import '../admin/audit_compliance_screen.dart';
import '../admin/defense_scheduler_screen.dart';
import '../admin/defense_board_screen.dart';
import '../admin/grade_center_screen.dart';
import '../admin/rubric_engine_screen.dart';
import '../admin/student_teams_screen.dart';
import '../uploader/uploader_dashboard.dart';
import 'adviser_grading_screen.dart';
import 'weekly_progress_reports_screen.dart';
import 'pit_lead_dashboard_content.dart';
import 'pit_lead_cohort_screen.dart';
import 'adviser_dashboard_content.dart';

enum FacultyWorkspace { pitLead, adviser, repoAssistant }

class FacultyDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  final Widget? routeChild;

  const FacultyDashboard({super.key, this.userData, this.routeChild});

  @override
  ConsumerState<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends ConsumerState<FacultyDashboard> {
  String _activeSection = 'dashboard';
  bool _schedulingExpanded = false;
  FacultyWorkspace? _activeWorkspace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardProvider('faculty').notifier).fetchDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(dashboardProvider('faculty'));
    final roles =
        (dashState.data?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
    // Check if user is ONLY an uploader (no other roles)
    final isOnlyUploader = roles['uploader'] == true &&
                           roles['adviser'] != true &&
                           roles['pit_lead'] != true &&
                           roles['repo_assistant'] != true;

    // Show sidebar if user has any faculty role
    final showSidebar = roles['adviser'] == true || 
                        roles['pit_lead'] == true || 
                        roles['repo_assistant'] == true ||
                        roles['uploader'] == true;

    // If user is only uploader, show uploader dashboard directly
    if (isOnlyUploader) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const UploaderDashboard(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= DefensysTokens.minDesktopWidth;
        final sidebar = showSidebar
            ? _buildPermanentSidebar(roles, isWide: isWide)
            : null;

        final mainColumn = Column(
          children: [
            _buildTopBar(showMenuButton: showSidebar && !isWide),
            Expanded(
              child: OfflineBanner(
                child: dashState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : dashState.error != null
                        ? Center(
                            child: Text(
                              dashState.error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        : _buildActiveContent(dashState, roles),
              ),
            ),
          ],
        );

        if (isWide) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Row(
              children: [
                if (sidebar != null) sidebar,
                Expanded(child: mainColumn),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: sidebar != null
              ? Drawer(
                  width: DefensysTokens.sidebarWidth,
                  child: sidebar,
                )
              : null,
          body: mainColumn,
        );
      },
    );
  }

  List<FacultyWorkspace> _availableWorkspaces(Map<String, dynamic> roles) {
    final workspaces = <FacultyWorkspace>[];
    if (roles['pit_lead'] == true) {
      workspaces.add(FacultyWorkspace.pitLead);
    }
    if (roles['adviser'] == true) {
      workspaces.add(FacultyWorkspace.adviser);
    }
    if (roles['repo_assistant'] == true && roles['pit_lead'] != true) {
      workspaces.add(FacultyWorkspace.repoAssistant);
    }
    return workspaces;
  }

  FacultyWorkspace _resolvedWorkspace(Map<String, dynamic> roles) {
    final available = _availableWorkspaces(roles);
    if (available.isEmpty) {
      return FacultyWorkspace.adviser;
    }
    if (_activeWorkspace != null && available.contains(_activeWorkspace)) {
      return _activeWorkspace!;
    }
    return available.first;
  }

  String _workspaceLabel(FacultyWorkspace workspace, Map<String, dynamic> roles) {
    switch (workspace) {
      case FacultyWorkspace.pitLead:
        final year = roles['pit_lead_year'] ?? 'Unscoped';
        return 'PIT Lead · $year';
      case FacultyWorkspace.adviser:
        return 'Project Adviser';
      case FacultyWorkspace.repoAssistant:
        return 'Repository Assistant';
    }
  }

  void _switchWorkspace(FacultyWorkspace workspace) {
    setState(() {
      _activeWorkspace = workspace;
      _activeSection = 'dashboard';
      _schedulingExpanded = false;
    });
  }

  void _goToSection(String section) {
    context.go(FacultyRoutes.pathForSection(section));
  }

  void _afterSidebarAction(bool isWide, VoidCallback action) {
    action();
    if (!isWide && mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildTopBar({required bool showMenuButton}) {
    return Container(
      height: DefensysTokens.topNavHeight,
      padding: EdgeInsets.symmetric(horizontal: showMenuButton ? 8 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Open menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPermanentSidebar(
    Map<String, dynamic> roles, {
    required bool isWide,
  }) {
    final workspace = _resolvedWorkspace(roles);
    final available = _availableWorkspaces(roles);
    if (_activeWorkspace != workspace) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _activeWorkspace = workspace);
        }
      });
    }

    return Container(
      width: DefensysTokens.sidebarWidth,
      color: DefensysTokens.maroon,
      child: Column(
        children: [
          Container(
            height: 92,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    color: Colors.white,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.shield_rounded,
                        color: DefensysTokens.maroon,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  'DefenSYS',
                  style: TextStyle(
                    color: DefensysTokens.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (available.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<FacultyWorkspace>(
                    isExpanded: true,
                    value: workspace,
                    dropdownColor: const Color(0xFF5E0D08),
                    iconEnabledColor: DefensysTokens.gold,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    items: available
                        .map(
                          (ws) => DropdownMenuItem(
                            value: ws,
                            child: Text(_workspaceLabel(ws, roles)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _afterSidebarAction(
                          isWide,
                          () => _switchWorkspace(value),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 20),
              children: [
                _buildSidebarItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  onTap: () => _afterSidebarAction(
                    isWide,
                    () => _goToSection('dashboard'),
                  ),
                  isActive: _activeSection == 'dashboard',
                ),
                const SizedBox(height: 8),
                ..._sidebarItemsForWorkspace(workspace, roles, isWide: isWide),
                if (roles['uploader'] == true) ...[
                  _buildSidebarItem(
                    icon: Icons.upload_file,
                    label: 'Upload Documents',
                    onTap: () => _afterSidebarAction(
                      isWide,
                      () => _goToSection('uploader'),
                    ),
                    isActive: _activeSection == 'uploader',
                  ),
                ],
              ],
            ),
          ),
          
          // Footer
          Container(height: 1, color: Colors.white.withValues(alpha: 0.09)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                if (!isWide) {
                  Navigator.of(context).pop();
                }
                if (await confirmLogout(context)) {
                  await ref.read(authProvider.notifier).logout();
                }
              },
              hoverColor: Colors.white.withValues(alpha: 0.05),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFD1D5DB),
                      size: 18,
                    ),
                    SizedBox(width: 14),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _sidebarItemsForWorkspace(
    FacultyWorkspace workspace,
    Map<String, dynamic> roles, {
    required bool isWide,
  }) {
    switch (workspace) {
      case FacultyWorkspace.pitLead:
        return [
          _buildSidebarItem(
            icon: Icons.school_outlined,
            label: 'Cohort',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('cohort'),
            ),
            isActive: _activeSection == 'cohort',
          ),
          _buildSidebarItem(
            icon: Icons.groups_outlined,
            label: 'Student Teams',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('student_teams'),
            ),
            isActive: _activeSection == 'student_teams',
          ),
          _buildExpandableSidebarItem(
            icon: Icons.calendar_month_outlined,
            label: 'Scheduling',
            isExpanded: _schedulingExpanded,
            onTap: () => _afterSidebarAction(
              isWide,
              () => setState(() => _schedulingExpanded = !_schedulingExpanded),
            ),
          ),
          if (_schedulingExpanded) ...[
            _buildSubSidebarItem(
              icon: Icons.event_outlined,
              label: 'Defense Scheduler',
              onTap: () => _afterSidebarAction(
                isWide,
                () => _goToSection('defense_scheduler'),
              ),
              isActive: _activeSection == 'defense_scheduler',
            ),
            _buildSubSidebarItem(
              icon: Icons.view_list_outlined,
              label: 'Defense Board',
              onTap: () => _afterSidebarAction(
                isWide,
                () => _goToSection('defense_board'),
              ),
              isActive: _activeSection == 'defense_board',
            ),
          ],
          _buildSidebarItem(
            icon: Icons.grading_outlined,
            label: 'Grade Center',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('grade_center'),
            ),
            isActive: _activeSection == 'grade_center',
          ),
          _buildSidebarItem(
            icon: Icons.rule_outlined,
            label: 'Rubric Engine',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('rubric_engine'),
            ),
            isActive: _activeSection == 'rubric_engine',
          ),
          _buildSidebarItem(
            icon: Icons.manage_search,
            label: 'Repository Vault',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('repository_audit'),
            ),
            isActive: _activeSection == 'repository_audit',
          ),
          _buildSidebarItem(
            icon: Icons.verified_user_outlined,
            label: 'Audit Trail',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('audit_compliance'),
            ),
            isActive: _activeSection == 'audit_compliance',
          ),
        ];
      case FacultyWorkspace.adviser:
        return [
          _buildSidebarItem(
            icon: Icons.folder_open_outlined,
            label: 'Capstone Deliverables',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('deliverables'),
            ),
            isActive: _activeSection == 'deliverables',
          ),
          _buildSidebarItem(
            icon: Icons.assignment_outlined,
            label: 'Weekly Progress Reports',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('weekly_reports'),
            ),
            isActive: _activeSection == 'weekly_reports',
          ),
          _buildSidebarItem(
            icon: Icons.rate_review_rounded,
            label: 'Grade Students',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('adviser_grading'),
            ),
            isActive: _activeSection == 'adviser_grading',
          ),
        ];
      case FacultyWorkspace.repoAssistant:
        return [
          _buildSidebarItem(
            icon: Icons.manage_search,
            label: 'Repository Vault',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('repository_audit'),
            ),
            isActive: _activeSection == 'repository_audit',
          ),
        ];
    }
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final color = isActive ? DefensysTokens.gold : const Color(0xFFD1D5DB);
    
    return Material(
      color: isActive ? const Color(0xFF5E0D08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: isActive
                ? const Border(
                    left: BorderSide(color: DefensysTokens.gold, width: 4),
                  )
                : null,
          ),
          padding: EdgeInsets.only(left: isActive ? 23 : 27, right: 24),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableSidebarItem({
    required IconData icon,
    required String label,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    final color = const Color(0xFFD1D5DB);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          height: 52,
          padding: const EdgeInsets.only(left: 27, right: 24),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubSidebarItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final color = isActive ? DefensysTokens.gold : const Color(0xFFD1D5DB);
    
    return Material(
      color: isActive ? const Color(0xFF5E0D08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: isActive
                ? const Border(
                    left: BorderSide(color: DefensysTokens.gold, width: 4),
                  )
                : null,
          ),
          padding: EdgeInsets.only(left: isActive ? 43 : 47, right: 24),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveContent(DashboardState dashState, Map<String, dynamic> roles) {
    final routerState = GoRouterState.of(context);
    if (routerState.pathParameters.containsKey('teamId') &&
        widget.routeChild != null) {
      return Container(
        color: Colors.white,
        child: widget.routeChild!,
      );
    }

    final sectionFromRoute =
        FacultyRoutes.sectionForLocation(routerState.uri.path);
    final activeSection = sectionFromRoute ?? _activeSection;

    final workspace = _resolvedWorkspace(roles);
    final facultyName =
        widget.userData?['name']?.toString() ??
        dashState.data?['faculty']?['name']?.toString() ??
        'Faculty';

    switch (activeSection) {
      case 'deliverables':
        return Container(
          color: Colors.white,
          child: const CapstoneDeliverablesScreen(),
        );
      case 'weekly_reports':
        return Container(
          color: Colors.white,
          child: const WeeklyProgressReportsScreen(),
        );
      case 'adviser_grading':
        return const AdviserGradingScreen();
      case 'cohort':
        return Container(
          color: Colors.white,
          child: PitLeadCohortScreen(
            onCreateTeam: () => _goToSection('student_teams'),
          ),
        );
      case 'student_teams':
        return Container(
          color: Colors.white,
          child: const StudentTeamsScreen(mode: TeamListMode.pitLead),
        );
      case 'repository_audit':
        return Container(
          color: Colors.white,
          child: const RepositoryAuditScreen(),
        );
      case 'audit_compliance':
        if (roles['pit_lead'] != true) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildWorkspaceDashboard(
              workspace: workspace,
              dashState: dashState,
              facultyName: facultyName,
            ),
          );
        }
        return Container(
          color: Colors.white,
          child: const AuditComplianceScreen(),
        );
      case 'uploader':
        return Container(
          color: Colors.white,
          child: const UploaderDashboard(),
        );
      case 'defense_scheduler':
        return Container(
          color: Colors.white,
          child: const DefenseSchedulerScreen(),
        );
      case 'defense_board':
        return Container(
          color: Colors.white,
          child: const DefenseBoardScreen(),
        );
      case 'grade_center':
        return Container(
          color: Colors.white,
          child: const GradeCenterScreen(),
        );
      case 'rubric_engine':
        return Container(
          color: Colors.white,
          child: const RubricEngineScreen(),
        );
      case 'dashboard':
      default:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _buildWorkspaceDashboard(
            workspace: workspace,
            dashState: dashState,
            facultyName: facultyName,
          ),
        );
    }
  }

  Widget _buildWorkspaceDashboard({
    required FacultyWorkspace workspace,
    required DashboardState dashState,
    required String facultyName,
  }) {
    switch (workspace) {
      case FacultyWorkspace.pitLead:
        return PitLeadDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          onOpenStudentTeams: () => _goToSection('student_teams'),
          onOpenCohort: () => _goToSection('cohort'),
          onOpenScheduler: () {
            setState(() {
              _schedulingExpanded = true;
              _activeSection = 'defense_scheduler';
            });
          },
          onOpenGradeCenter: () => _goToSection('grade_center'),
          onOpenRubrics: () => _goToSection('rubric_engine'),
        );
      case FacultyWorkspace.adviser:
        return AdviserDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          onOpenDeliverables: () => _goToSection('deliverables'),
          onOpenWeeklyReports: () => _goToSection('weekly_reports'),
          onOpenGrading: () => _goToSection('adviser_grading'),
        );
      case FacultyWorkspace.repoAssistant:
        final repoYear =
            dashState.data?['repo_assistant_year']?.toString() ??
            (dashState.data?['roles'] as Map?)?['repo_assistant_year']?.toString() ??
            '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, $facultyName',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              repoYear.isNotEmpty
                  ? 'Repository Assistant for $repoYear — open Repository Vault to upload passed PIT project files after the PIT lead marks the event officially complete in Grade Center.'
                  : 'Repository Assistant workspace — open Repository Vault once your PIT lead assigns your year level.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        );
    }
  }
}
