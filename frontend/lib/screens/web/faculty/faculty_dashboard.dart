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
import '../../../services/notifications_provider.dart';
import '../../../widgets/notifications_modal.dart';
import '../shared/team_deliverables_screen.dart';
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
import 'pit_student_import_screen.dart';
import 'pit_instructor_assignment_screen.dart';
import 'adviser_dashboard_content.dart';
import 'pit_events_management_screen.dart';
import 'pit_instructor_dashboard_content.dart';
import 'e_signature_upload_dialog.dart';
import 'documenter_dashboard_content.dart';
import 'minutes_form_screen.dart';

enum FacultyWorkspace { pitLead, adviser, pitInstructor, documenter }

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
  bool _userManagementExpanded = true;
  FacultyWorkspace? _activeWorkspace;
  int? _selectedMinutesScheduleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardProvider('faculty').notifier).fetchDashboardData();
      ref.read(notificationsProvider.notifier).fetchNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(dashboardProvider('faculty'));
    final roles =
        (dashState.data?['roles'] as Map?)?.cast<String, dynamic>() ?? {};

    final routerState = GoRouterState.of(context);
    final sectionFromRoute = FacultyRoutes.sectionForLocation(
      routerState.uri.path,
    );
    if (sectionFromRoute != null && sectionFromRoute != _activeSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _activeSection = sectionFromRoute;
            final workspace = _resolvedWorkspace(roles);
            final isUserMgmt = sectionFromRoute == 'cohort' ||
                sectionFromRoute == 'student_teams' ||
                sectionFromRoute == 'pit_student_import' ||
                sectionFromRoute == 'pit_instructors' ||
                (sectionFromRoute == 'deliverables' && workspace == FacultyWorkspace.pitLead);
            final isSched = sectionFromRoute == 'defense_scheduler' ||
                sectionFromRoute == 'defense_board';
            if (isUserMgmt) {
              _userManagementExpanded = true;
              _schedulingExpanded = false;
            } else if (isSched) {
              _schedulingExpanded = true;
              _userManagementExpanded = false;
            }
          });
        }
      });
    }
    // Check if user is ONLY an uploader (no other roles)
    final isOnlyUploader =
        roles['uploader'] == true &&
        roles['adviser'] != true &&
        roles['pit_lead'] != true &&
        roles['documenter'] != true &&
        roles['pit_instructor'] != true;

    // Show sidebar if user has any faculty role
    final showSidebar =
        roles['adviser'] == true ||
        roles['pit_lead'] == true ||
        roles['documenter'] == true ||
        roles['uploader'] == true ||
        roles['pit_instructor'] == true;

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
              ? Drawer(width: DefensysTokens.sidebarWidth, child: sidebar)
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
    if (roles['pit_instructor'] == true) {
      workspaces.add(FacultyWorkspace.pitInstructor);
    }
    if (roles['documenter'] == true) {
      workspaces.add(FacultyWorkspace.documenter);
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

  String _workspaceLabel(
    FacultyWorkspace workspace,
    Map<String, dynamic> roles,
  ) {
    switch (workspace) {
      case FacultyWorkspace.pitLead:
        final year = roles['pit_lead_year'] ?? 'Unscoped';
        return 'PIT Lead · $year';
      case FacultyWorkspace.adviser:
        return 'Project Adviser';
      case FacultyWorkspace.pitInstructor:
        return 'PIT Instructor';
      case FacultyWorkspace.documenter:
        return 'Minutes Documenter';
    }
  }

  void _switchWorkspace(FacultyWorkspace workspace) {
    setState(() {
      _activeWorkspace = workspace;
      _activeSection = 'dashboard';
      _schedulingExpanded = false;
      _userManagementExpanded = true;
    });
    context.go(FacultyRoutes.dashboard);
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
          Consumer(
            builder: (context, ref, child) {
              final state = ref.watch(notificationsProvider);
              return Badge(
                isLabelVisible: state.unreadCount > 0,
                label: Text(
                  state.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: DefensysTokens.maroon,
                child: IconButton(
                  icon: Icon(
                    Icons.notifications_outlined,
                    color: Colors.grey.shade600,
                    size: 23,
                  ),
                  tooltip: 'Notifications',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => const NotificationsModal(),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 16),
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

    final facultyName = widget.userData?['name']?.toString() ??
        ref.read(dashboardProvider('faculty')).data?['faculty']?['name']?.toString() ??
        'Faculty';

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
                      'assets/logo-login-mark-48.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
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
                    fontFamily: DefensysTokens.fontFamily,
                    color: DefensysTokens.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (available.length > 1)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<FacultyWorkspace>(
                  isExpanded: true,
                  value: workspace,
                  dropdownColor: const Color(0xFF5E0D08),
                  iconEnabledColor: DefensysTokens.gold,
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
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
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 16),
              children: [
                ..._sidebarItemsForWorkspace(workspace, roles, isWide: isWide),
                if (roles['uploader'] == true) ...[
                  _buildSectionHeader('Tools'),
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
          Container(height: 1, color: Colors.white.withValues(alpha: 0.09)),
          _buildUserProfileCard(facultyName, _workspaceLabel(workspace, roles), isWide),
        ],
      ),
    );
  }

  Widget _buildUserProfileCard(String facultyName, String roleLabel, bool isWide) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: DefensysTokens.gold.withValues(alpha: 0.5),
                width: 1.5,
              ),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: const Center(
              child: Icon(
                Icons.school_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  facultyName,
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  roleLabel,
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(
                Icons.draw_rounded,
                color: Color(0xFFD1D5DB),
                size: 18,
              ),
              tooltip: 'E-Signature',
              onPressed: () {
                if (!isWide) {
                  Navigator.of(context).pop();
                }
                showDialog(
                  context: context,
                  builder: (context) => const ESignatureUploadDialog(),
                );
              },
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              splashRadius: 20,
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFFCA5A5),
                size: 18,
              ),
              tooltip: 'Log Out',
              onPressed: () async {
                if (!isWide) {
                  Navigator.of(context).pop();
                }
                if (await confirmLogout(context)) {
                  await ref.read(authProvider.notifier).logout();
                }
              },
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              splashRadius: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamily,
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
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
          _buildSectionHeader('Dashboard'),
          _buildSidebarItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('dashboard'),
            ),
            isActive: _activeSection == 'dashboard',
          ),
          _buildSectionHeader('Management'),
          _buildExpandableSidebarItem(
            icon: Icons.manage_accounts_outlined,
            label: 'User Management',
            isExpanded: _userManagementExpanded,
            isActive: _activeSection == 'cohort' ||
                _activeSection == 'pit_student_import' ||
                _activeSection == 'pit_instructors' ||
                _activeSection == 'student_teams' ||
                _activeSection == 'deliverables' ||
                _activeSection == 'pit_events',
            onTap: () => _afterSidebarAction(
              isWide,
              () => setState(() {
                _userManagementExpanded = !_userManagementExpanded;
                if (_userManagementExpanded) {
                  _schedulingExpanded = false;
                }
              }),
            ),
          ),
          if (_userManagementExpanded) ...[
            _buildSubSidebarItem(
              icon: Icons.school_outlined,
              label: 'Cohort',
              onTap: () =>
                  _afterSidebarAction(isWide, () => _goToSection('cohort')),
              isActive:
                  _activeSection == 'cohort' ||
                  _activeSection == 'pit_student_import' ||
                  _activeSection == 'pit_instructors',
            ),
            _buildSubSidebarItem(
              icon: Icons.groups_outlined,
              label: 'Student Teams',
              onTap: () => _afterSidebarAction(
                isWide,
                () => _goToSection('student_teams'),
              ),
              isActive: _activeSection == 'student_teams',
            ),
            _buildSubSidebarItem(
              icon: Icons.event_note_outlined,
              label: 'PIT Events',
              onTap: () => _afterSidebarAction(
                isWide,
                () => _goToSection('pit_events'),
              ),
              isActive: _activeSection == 'pit_events',
            ),
          ],
          _buildSectionHeader('Operations'),
          _buildExpandableSidebarItem(
            icon: Icons.calendar_month_outlined,
            label: 'Scheduling',
            isExpanded: _schedulingExpanded,
            isActive: _activeSection == 'defense_scheduler' ||
                _activeSection == 'defense_board',
            onTap: () => _afterSidebarAction(
              isWide,
              () => setState(() {
                _schedulingExpanded = !_schedulingExpanded;
                if (_schedulingExpanded) {
                  _userManagementExpanded = false;
                }
              }),
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
          _buildSectionHeader('Evaluation'),
          _buildSidebarItem(
            icon: Icons.grading_outlined,
            label: 'Grade Center',
            onTap: () =>
                _afterSidebarAction(isWide, () => _goToSection('grade_center')),
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
          _buildSectionHeader('Archive & Audit'),
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
          _buildSectionHeader('Dashboard'),
          _buildSidebarItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('dashboard'),
            ),
            isActive: _activeSection == 'dashboard',
          ),
          _buildSectionHeader('Advising'),
          _buildSidebarItem(
            icon: Icons.folder_open_outlined,
            label: 'Capstone Deliverables',
            onTap: () =>
                _afterSidebarAction(isWide, () => _goToSection('deliverables')),
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
          _buildSidebarItem(
            icon: Icons.summarize_rounded,
            label: 'Reports',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('audit_compliance'),
            ),
            isActive: _activeSection == 'audit_compliance',
          ),
        ];
      case FacultyWorkspace.pitInstructor:
        return [
          _buildSectionHeader('Dashboard'),
          _buildSidebarItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('dashboard'),
            ),
            isActive: _activeSection == 'dashboard',
          ),
          _buildSectionHeader('Instruction'),
          _buildSidebarItem(
            icon: Icons.folder_open_outlined,
            label: 'PIT Deliverables',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('deliverables'),
            ),
            isActive: _activeSection == 'deliverables',
          ),
          _buildSidebarItem(
            icon: Icons.groups_outlined,
            label: 'PIT Teams',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('student_teams'),
            ),
            isActive: _activeSection == 'student_teams',
          ),
        ];
      case FacultyWorkspace.documenter:
        return [
          _buildSectionHeader('Dashboard'),
          _buildSidebarItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('dashboard'),
            ),
            isActive: _activeSection == 'dashboard',
          ),
          _buildSectionHeader('Operations'),
          _buildSidebarItem(
            icon: Icons.view_list_outlined,
            label: 'Defense Board',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('defense_board'),
            ),
            isActive: _activeSection == 'defense_board',
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
    final containerColor = isActive
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: containerColor,
          child: InkWell(
            onTap: onTap,
            hoverColor: Colors.white.withValues(alpha: 0.05),
            child: Container(
              height: 46,
              padding: const EdgeInsets.only(left: 10, right: 14),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isActive ? DefensysTokens.gold : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        color: color,
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
    bool isActive = false,
  }) {
    final color = isActive ? DefensysTokens.gold : const Color(0xFFD1D5DB);
    final containerColor = isActive
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: containerColor,
          child: InkWell(
            onTap: onTap,
            hoverColor: Colors.white.withValues(alpha: 0.05),
            child: Container(
              height: 46,
              padding: const EdgeInsets.only(left: 10, right: 14),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isActive ? DefensysTokens.gold : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        color: color,
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: color.withValues(alpha: 0.86),
                    size: 18,
                  ),
                ],
              ),
            ),
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
    final color = isActive ? DefensysTokens.gold : Colors.white.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: isActive ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: Colors.white.withValues(alpha: 0.03),
            child: Container(
              height: 38,
              padding: const EdgeInsets.only(left: 36, right: 14),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        color: color,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveContent(
    DashboardState dashState,
    Map<String, dynamic> roles,
  ) {
    if (_selectedMinutesScheduleId != null) {
      return MinutesFormScreen(
        scheduleId: _selectedMinutesScheduleId!,
        onBack: () {
          setState(() {
            _selectedMinutesScheduleId = null;
          });
          ref.read(dashboardProvider('faculty').notifier).fetchDashboardData();
        },
      );
    }

    final routerState = GoRouterState.of(context);
    final isSubRoute = routerState.pathParameters.containsKey('teamId') ||
        routerState.pathParameters.containsKey('sectionName');
    if (isSubRoute && widget.routeChild != null) {
      return Container(color: Colors.white, child: widget.routeChild!);
    }

    final sectionFromRoute = FacultyRoutes.sectionForLocation(
      routerState.uri.path,
    );
    final activeSection = sectionFromRoute ?? _activeSection;

    final workspace = _resolvedWorkspace(roles);
    final facultyName =
        widget.userData?['name']?.toString() ??
        dashState.data?['faculty']?['name']?.toString() ??
        'Faculty';

    switch (activeSection) {
      case 'deliverables':
        final ws = _resolvedWorkspace(roles);
        final initialScope = (ws == FacultyWorkspace.pitLead || ws == FacultyWorkspace.pitInstructor) ? 'pit' : 'capstone';
        return Container(
          color: Colors.white,
          child: TeamDeliverablesScreen(initialScope: initialScope),
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
      case 'pit_student_import':
        return Container(
          color: Colors.white,
          child: const PitStudentImportScreen(),
        );
      case 'student_teams':
        final ws = _resolvedWorkspace(roles);
        final mode = ws == FacultyWorkspace.pitInstructor
            ? TeamListMode.pitInstructor
            : TeamListMode.pitLead;
        return Container(
          color: Colors.white,
          child: StudentTeamsScreen(mode: mode),
        );
      case 'pit_events':
        return Container(
          color: Colors.white,
          child: const PitEventsManagementScreen(),
        );
      case 'pit_instructors':
        return Container(
          color: Colors.white,
          child: PitInstructorAssignmentScreen(
            initialSection: routerState.uri.queryParameters['section'],
          ),
        );
      case 'repository_audit':
        return Container(
          color: Colors.white,
          child: const RepositoryAuditScreen(),
        );
      case 'audit_compliance':
        if (roles['pit_lead'] != true && roles['adviser'] != true) {
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
        return Container(color: Colors.white, child: const UploaderDashboard());
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
        return Container(color: Colors.white, child: const GradeCenterScreen());
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
      case FacultyWorkspace.pitInstructor:
        return PitInstructorDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          onOpenDeliverables: () => _goToSection('deliverables'),
        );
      case FacultyWorkspace.documenter:
        return DocumenterDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          onOpenMinutes: (scheduleId) {
            setState(() {
              _selectedMinutesScheduleId = scheduleId;
            });
          },
        );
    }
  }
}
