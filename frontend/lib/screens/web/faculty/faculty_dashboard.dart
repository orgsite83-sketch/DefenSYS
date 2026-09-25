import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../navigation/admin_route_paths.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/offline_banner.dart';
import '../../../widgets/defensys_logo_mark.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../services/unsaved_changes_provider.dart';
import '../../../utils/unsaved_changes.dart';
import '../../../notifications/notifications_modal.dart';
import '../../../notifications/notifications_provider.dart';
import '../../../widgets/buttons/defensys_theme_toggle.dart';
import '../shared/team_deliverables/team_deliverables_screen.dart';
import '../shared/project_archive/project_archive_screen.dart';
import '../../app/student/repository_tab.dart';
import '../admin/audit_compliance_screen.dart';
import '../admin/defense_scheduler/defense_scheduler_screen.dart';
import '../admin/defense_board_screen.dart';
import '../admin/grade_center_screen.dart';
import '../admin/rubric_engine_screen.dart';
import '../admin/student_teams_screen.dart';
import '../uploader/uploader_dashboard.dart';
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
import 'capstone_instructor_info_section.dart';
import 'faculty_base_dashboard_content.dart';
import '../../../config/api_config.dart';

enum FacultyWorkspace { faculty, pitLead, adviser, pitInstructor, documenter }

class WorkspaceOption {
  final FacultyWorkspace type;
  final String? yearLevel;
  final String? section;

  const WorkspaceOption({required this.type, this.yearLevel, this.section});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceOption &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          yearLevel == other.yearLevel &&
          section == other.section;

  @override
  int get hashCode => type.hashCode ^ yearLevel.hashCode ^ section.hashCode;
}

class FacultyDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  final Widget? routeChild;

  const FacultyDashboard({super.key, this.userData, this.routeChild});

  @override
  ConsumerState<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends ConsumerState<FacultyDashboard> {
  String _activeSection = 'dashboard';
  WorkspaceOption? _activeWorkspaceOption;
  int? _selectedMinutesScheduleId;
  int _navigationEpoch = 0;
  bool _isCollapsed = false;

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

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

    // Show sidebar for all faculty roles (unless uploader-only)
    final showSidebar = !isOnlyUploader;

    // If user is only uploader, show uploader dashboard directly
    if (isOnlyUploader) {
      return Scaffold(
        backgroundColor: DefensysTokens.backgroundOf(context),
        body: const UploaderDashboard(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= DefensysTokens.minDesktopWidth;
        final sidebar = showSidebar
            ? _buildPermanentSidebar(
                roles,
                isWide: isWide,
                isCollapsed: isWide && _isCollapsed,
                onToggleCollapse: isWide ? _toggleCollapse : null,
              )
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
            backgroundColor: DefensysTokens.backgroundOf(context),
            body: Row(
              children: [
                if (sidebar != null) RepaintBoundary(child: sidebar),
                Expanded(child: RepaintBoundary(child: mainColumn)),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: DefensysTokens.backgroundOf(context),
          drawer: sidebar != null
              ? Drawer(
                  width: DefensysTokens.sidebarWidth,
                  backgroundColor: DefensysTokens.panelOf(context),
                  surfaceTintColor: Colors.transparent,
                  child: sidebar,
                )
              : null,
          body: mainColumn,
        );
      },
    );
  }

  List<WorkspaceOption> _availableWorkspaces(Map<String, dynamic> roles) {
    final workspaces = <WorkspaceOption>[];
    if (roles['pit_lead'] == true) {
      workspaces.add(WorkspaceOption(
        type: FacultyWorkspace.pitLead,
        yearLevel: roles['pit_lead_year']?.toString(),
      ));
    }
    if (roles['adviser'] == true) {
      workspaces.add(const WorkspaceOption(type: FacultyWorkspace.adviser));
    }
    if (roles['pit_instructor'] == true) {
      final sections = roles['pit_instructor_sections'] as List<dynamic>?;
      if (sections != null && sections.isNotEmpty) {
        for (final item in sections) {
          if (item is Map) {
            workspaces.add(WorkspaceOption(
              type: FacultyWorkspace.pitInstructor,
              yearLevel: item['year_level']?.toString(),
              section: item['section']?.toString(),
            ));
          }
        }
      } else {
        final years = List<String>.from(roles['pit_instructor_years'] ?? []);
        if (years.isEmpty) {
          workspaces.add(const WorkspaceOption(
            type: FacultyWorkspace.pitInstructor,
            yearLevel: '1st Year',
          ));
        } else {
          for (final yr in years) {
            workspaces.add(WorkspaceOption(
              type: FacultyWorkspace.pitInstructor,
              yearLevel: yr,
            ));
          }
        }
      }
    }
    if (roles['documenter'] == true) {
      workspaces.add(const WorkspaceOption(type: FacultyWorkspace.documenter));
    }
    if (workspaces.isEmpty) {
      workspaces.add(const WorkspaceOption(type: FacultyWorkspace.faculty));
    }
    return workspaces;
  }

  bool _isSectionSupportedByWorkspace(String section, FacultyWorkspace workspace) {
    switch (workspace) {
      case FacultyWorkspace.faculty:
        return const {
          'dashboard',
          'project_archive',
          'repository_audit',
          'uploader',
        }.contains(section);
      case FacultyWorkspace.pitLead:
        return const {
          'dashboard',
          'pit_events',
          'rubrics',
          'cohort',
          'pit_student_import',
          'pit_instructors',
          'student_teams',
          'defense_scheduler',
          'defense_board',
          'grade_center',
          'project_archive',
          'repository_audit',
          'audit_compliance',
          'uploader',
        }.contains(section);
      case FacultyWorkspace.adviser:
        return const {
          'dashboard',
          'deliverables',
          'weekly_reports',
          'adviser_grading',
          'defense_board',
          'audit_compliance',
          'uploader',
        }.contains(section);
      case FacultyWorkspace.pitInstructor:
        return const {
          'dashboard',
          'deliverables',
          'student_teams',
          'audit_compliance',
          'uploader',
        }.contains(section);
      case FacultyWorkspace.documenter:
        return const {
          'dashboard',
          'defense_board',
          'uploader',
        }.contains(section);
    }
  }

  WorkspaceOption _resolvedWorkspace(Map<String, dynamic> roles) {
    final available = _availableWorkspaces(roles);
    if (available.isEmpty) {
      return const WorkspaceOption(type: FacultyWorkspace.faculty);
    }

    final routerState = GoRouterState.of(context);
    final sectionFromRoute = FacultyRoutes.sectionForLocation(routerState.uri.path);
    final currentSection = sectionFromRoute ?? _activeSection;

    if (_activeWorkspaceOption != null &&
        available.contains(_activeWorkspaceOption) &&
        _isSectionSupportedByWorkspace(currentSection, _activeWorkspaceOption!.type)) {
      return _activeWorkspaceOption!;
    }

    for (final option in available) {
      if (_isSectionSupportedByWorkspace(currentSection, option.type)) {
        return option;
      }
    }

    return available.first;
  }

  String _workspaceLabel(WorkspaceOption ws) {
    switch (ws.type) {
      case FacultyWorkspace.faculty:
        return 'Faculty Portal';
      case FacultyWorkspace.pitLead:
        final year = ws.yearLevel ?? 'Unscoped';
        return 'PIT Lead · $year';
      case FacultyWorkspace.adviser:
        return 'Project Adviser';
      case FacultyWorkspace.pitInstructor:
        final year = ws.yearLevel ?? 'Unscoped';
        final sec = ws.section;
        if (sec != null && sec.isNotEmpty) {
          return 'PIT Instructor · $year ($sec)';
        }
        return 'PIT Instructor · $year';
      case FacultyWorkspace.documenter:
        return 'Minutes Documenter';
    }
  }

  void _switchWorkspace(WorkspaceOption workspaceOption) async {
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
    setState(() {
      _activeWorkspaceOption = workspaceOption;
      _activeSection = workspaceOption.type == FacultyWorkspace.faculty
          ? 'project_archive'
          : 'dashboard';
      _navigationEpoch++;
    });
    context.go(
      workspaceOption.type == FacultyWorkspace.faculty
          ? FacultyRoutes.projectArchive
          : FacultyRoutes.dashboard,
    );
  }

  void _goToSection(String section, {Map<String, String>? queryParameters}) async {
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
    setState(() {
      _navigationEpoch++;
    });
    final path = FacultyRoutes.pathForSection(section);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final uri = Uri(path: path, queryParameters: queryParameters);
      context.go(uri.toString());
    } else {
      context.go(path);
    }
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
      padding: EdgeInsets.only(
        left: showMenuButton ? 8 : 32,
        right: 40,
      ),
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        border: Border(
          bottom: BorderSide(
            color: DefensysTokens.borderOf(context),
            width: 1,
          ),
        ),
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
                backgroundColor: DefensysTokens.maroonOf(context),
                child: IconButton(
                  icon: Icon(
                    Icons.notifications_outlined,
                    color: DefensysTokens.textSecondaryOf(context),
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
          const SizedBox(width: 10),
          const DefensysThemeToggle(),
        ],
      ),
    );
  }

  String _roleBadgeText(FacultyWorkspace workspace) {
    switch (workspace) {
      case FacultyWorkspace.pitLead:
        return 'PIT Lead';
      case FacultyWorkspace.adviser:
        return 'Adviser';
      case FacultyWorkspace.pitInstructor:
        return 'Instructor';
      case FacultyWorkspace.documenter:
        return 'Documenter';
      case FacultyWorkspace.faculty:
        return 'Faculty';
    }
  }

  Widget _buildPermanentSidebar(
    Map<String, dynamic> roles, {
    required bool isWide,
    required bool isCollapsed,
    VoidCallback? onToggleCollapse,
  }) {
    final workspaceOption = _resolvedWorkspace(roles);
    final available = _availableWorkspaces(roles);
    if (_activeWorkspaceOption != workspaceOption) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _activeWorkspaceOption = workspaceOption);
        }
      });
    }

    final facultyName = widget.userData?['name']?.toString() ??
        ref.read(dashboardProvider('faculty')).data?['faculty']?['name']?.toString() ??
        'Faculty';

    final groups = _sidebarGroupsForWorkspace(
      workspaceOption.type,
      roles,
      isWide: isWide,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: isCollapsed ? 68.0 : DefensysTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        border: Border(
          right: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header / Brand area
          if (isCollapsed)
            SizedBox(
              height: 64,
              width: 68,
              child: Center(
                child: IconButton(
                  icon: const _SidebarPanelIcon(size: 20),
                  tooltip: 'Expand sidebar',
                  splashRadius: 18,
                  onPressed: onToggleCollapse,
                ),
              ),
            )
          else
            Container(
              height: 64,
              padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
              child: Row(
                children: [
                  const DefensysLogoMark(
                    size: 30,
                    colorMode: DefensysLogoColorMode.brand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'DefenSYS',
                                style: TextStyle(
                                  fontFamily: DefensysTokens.fontFamily,
                                  color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                softWrap: false,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF28272D) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: DefensysTokens.borderOf(context),
                                ),
                              ),
                              child: Text(
                                _roleBadgeText(workspaceOption.type),
                                style: TextStyle(
                                  fontFamily: DefensysTokens.fontFamily,
                                  color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Academic Portal',
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamily,
                            color: isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ],
                    ),
                  ),
                  if (onToggleCollapse != null)
                    IconButton(
                      icon: const _SidebarPanelIcon(size: 18),
                      tooltip: 'Collapse sidebar',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(6),
                      splashRadius: 16,
                      onPressed: onToggleCollapse,
                    ),
                ],
              ),
            ),

          // Workspace Switcher (Multi-role switcher)
          if (available.length > 1) ...[
            if (isCollapsed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: PopupMenuButton<WorkspaceOption>(
                  tooltip: _workspaceLabel(workspaceOption),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
                  ),
                  color: DefensysTokens.panelOf(context),
                  elevation: 4,
                  offset: const Offset(50, 0),
                  onSelected: (value) {
                    _afterSidebarAction(isWide, () => _switchWorkspace(value));
                  },
                  itemBuilder: (context) => available
                      .map(
                        (ws) => PopupMenuItem(
                          value: ws,
                          height: 36,
                          child: Text(
                            _workspaceLabel(ws),
                            style: TextStyle(
                              fontFamily: DefensysTokens.fontFamily,
                              fontSize: 12.5,
                              fontWeight: ws == workspaceOption
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: ws == workspaceOption
                                  ? DefensysTokens.maroonOf(context)
                                  : (isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A)),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  child: Container(
                    width: 40,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF28272D) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: DefensysTokens.borderOf(context)),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        size: 16,
                        color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF28272D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context), width: 1),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<WorkspaceOption>(
                    isExpanded: true,
                    value: workspaceOption,
                    dropdownColor: DefensysTokens.panelOf(context),
                    iconEnabledColor: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B),
                    icon: const Icon(Icons.unfold_more_rounded, size: 18),
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamily,
                      color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    items: available
                        .map(
                          (ws) => DropdownMenuItem(
                            value: ws,
                            child: Text(
                              _workspaceLabel(ws),
                              style: TextStyle(
                                fontFamily: DefensysTokens.fontFamily,
                                color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
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
          ],

          // Hairline divider below header
          Divider(height: 1, thickness: 1, color: DefensysTokens.borderOf(context)),

          // Scrollable Navigation List (Clean direct groups)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              children: [
                for (int i = 0; i < groups.length; i++) ...[
                  if (i > 0)
                    SizedBox(height: isCollapsed ? 8 : 20),
                  _FacultySectionHeader(
                    title: groups[i].title,
                    isCollapsed: isCollapsed,
                    isFirst: i == 0,
                  ),
                  const SizedBox(height: 4),
                  for (final e in groups[i].entries)
                    _FacultyNavItem(
                      icon: e.icon,
                      label: e.label,
                      isActive: e.isActive,
                      onTap: e.onTap,
                      isCollapsed: isCollapsed,
                    ),
                ],
              ],
            ),
          ),

          // Hairline divider above profile
          Divider(height: 1, thickness: 1, color: DefensysTokens.borderOf(context)),

          // User Profile Card
          _buildUserProfileCard(
            facultyName: facultyName,
            roleLabel: _workspaceLabel(workspaceOption),
            isWide: isWide,
            isCollapsed: isCollapsed,
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfileCard({
    required String facultyName,
    required String roleLabel,
    required bool isWide,
    required bool isCollapsed,
  }) {
    final user = ref.watch(authProvider).user ?? widget.userData;
    final avatarUrl = user?['avatar'] != null
        ? ApiConfig.publicMediaUrl(user!['avatar'] as String)
        : null;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final popupItems = <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: 'signature',
        height: 38,
        child: Row(
          children: [
            Icon(Icons.draw_outlined, size: 16, color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569)),
            const SizedBox(width: 10),
            Text(
              'E-Signature',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(
        value: 'logout',
        height: 38,
        child: Row(
          children: const [
            Icon(Icons.logout_rounded, size: 16, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text(
              'Log Out',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ),
    ];

    void handleSelect(String value) async {
      if (value == 'signature') {
        if (!isWide && mounted) {
          Navigator.of(context).pop();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (context) => const ESignatureUploadDialog(),
          );
        });
      } else if (value == 'logout') {
        if (!isWide && mounted) {
          Navigator.of(context).pop();
        }
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
        if (await confirmLogout(context)) {
          ref.read(unsavedChangesProvider.notifier).setDirty(false);
          await ref.read(authProvider.notifier).logout();
        }
      }
    }

    if (isCollapsed) {
      return Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        height: 54,
        alignment: Alignment.center,
        child: PopupMenuButton<String>(
          tooltip: '$facultyName ($roleLabel)',
          offset: const Offset(50, 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
          ),
          color: DefensysTokens.panelOf(context),
          elevation: 4,
          onSelected: handleSelect,
          itemBuilder: (context) => popupItems,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? DefensysTokens.mistMaroon.withValues(alpha: 0.4)
                    : DefensysTokens.maroon.withValues(alpha: 0.25),
                width: 1.5,
              ),
              color: isDark ? DefensysTokens.mistMaroon : DefensysTokens.maroon,
              image: avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarUrl == null
                ? const Center(
                    child: Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  )
                : null,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF28272D) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DefensysTokens.borderOf(context),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? DefensysTokens.mistMaroon.withValues(alpha: 0.35)
                            : DefensysTokens.maroon.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                      color: isDark ? DefensysTokens.mistMaroon : DefensysTokens.maroon,
                      image: avatarUrl != null
                          ? DecorationImage(
                              image: NetworkImage(avatarUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: avatarUrl == null
                        ? const Center(
                            child: Icon(
                              Icons.school_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          facultyName,
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamily,
                            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF0F172A),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          roleLabel,
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamily,
                            color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account options',
            icon: Icon(
              Icons.more_horiz_rounded,
              color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B),
              size: 18,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 16,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: DefensysTokens.borderOf(context), width: 1),
            ),
            color: DefensysTokens.panelOf(context),
            elevation: 4,
            offset: const Offset(0, -100),
            onSelected: handleSelect,
            itemBuilder: (context) => popupItems,
          ),
        ],
      ),
    );
  }

  List<_FacultyNavGroup> _sidebarGroupsForWorkspace(
    FacultyWorkspace workspace,
    Map<String, dynamic> roles, {
    required bool isWide,
  }) {
    List<_FacultyNavGroup> groups;
    switch (workspace) {
      case FacultyWorkspace.faculty:
        groups = [
          _FacultyNavGroup(
            title: 'Repository',
            entries: [
              _FacultyNavEntry(
                section: 'project_archive',
                icon: Icons.folder_rounded,
                label: 'Research Repository',
                isActive: _activeSection == 'project_archive' ||
                    _activeSection == 'repository_audit' ||
                    _activeSection == 'dashboard',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('project_archive'),
                ),
              ),
            ],
          ),
        ];
        break;

      case FacultyWorkspace.pitLead:
        groups = [
          _FacultyNavGroup(
            title: 'Dashboard',
            entries: [
              _FacultyNavEntry(
                section: 'dashboard',
                icon: Icons.show_chart_rounded,
                label: 'Dashboard',
                isActive: _activeSection == 'dashboard',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('dashboard'),
                ),
              ),
            ],
          ),
          _FacultyNavGroup(
            title: 'Setup & Configuration',
            entries: [
              _FacultyNavEntry(
                section: 'pit_events',
                icon: Icons.event_note_rounded,
                label: 'PIT Events Setup',
                isActive: _activeSection == 'pit_events',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('pit_events'),
                ),
              ),
              _FacultyNavEntry(
                section: 'rubrics',
                icon: Icons.checklist_rounded,
                label: 'Rubrics',
                isActive: _activeSection == 'rubrics',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('rubrics'),
                ),
              ),
            ],
          ),
          _FacultyNavGroup(
            title: 'People & Teams',
            entries: [
              _FacultyNavEntry(
                section: 'cohort',
                icon: Icons.manage_accounts_rounded,
                label: 'User Management',
                isActive: _activeSection == 'cohort' ||
                    _activeSection == 'pit_student_import' ||
                    _activeSection == 'pit_instructors',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('cohort'),
                ),
              ),
              _FacultyNavEntry(
                section: 'student_teams',
                icon: Icons.groups_rounded,
                label: 'Student Teams',
                isActive: _activeSection == 'student_teams',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('student_teams'),
                ),
              ),
            ],
          ),
          _FacultyNavGroup(
            title: 'Defense Operations',
            entries: [
              _FacultyNavEntry(
                section: 'defense_board',
                icon: Icons.view_agenda_rounded,
                label: 'Defense Operations',
                isActive: _activeSection == 'defense_board' ||
                    _activeSection == 'defense_scheduler',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('defense_board'),
                ),
              ),
              _FacultyNavEntry(
                section: 'grade_center',
                icon: Icons.grade_rounded,
                label: 'Evaluation & Grades',
                isActive: _activeSection == 'grade_center',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('grade_center'),
                ),
              ),
            ],
          ),
          _FacultyNavGroup(
            title: 'Archives & Audit',
            entries: [
              _FacultyNavEntry(
                section: 'project_archive',
                icon: Icons.folder_rounded,
                label: 'Project Archive',
                isActive: _activeSection == 'project_archive' ||
                    _activeSection == 'repository_audit',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('project_archive'),
                ),
              ),
              _FacultyNavEntry(
                section: 'audit_compliance',
                icon: Icons.verified_user_outlined,
                label: 'Audit Trail',
                isActive: _activeSection == 'audit_compliance',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('audit_compliance'),
                ),
              ),
            ],
          ),
        ];
        break;

      case FacultyWorkspace.adviser:
        groups = [
          _FacultyNavGroup(
            title: 'Dashboard',
            entries: [
              _FacultyNavEntry(
                section: 'dashboard',
                icon: Icons.show_chart_rounded,
                label: 'Dashboard',
                isActive: _activeSection == 'dashboard',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('dashboard'),
                ),
              ),
            ],
          ),
          _FacultyNavGroup(
            title: 'Advising',
            entries: [
              _FacultyNavEntry(
                section: 'deliverables',
                icon: Icons.folder_open_rounded,
                label: 'Capstone Teams',
                isActive: _activeSection == 'deliverables',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('deliverables'),
                ),
              ),
              _FacultyNavEntry(
                section: 'defense_board',
                icon: Icons.view_agenda_rounded,
                label: 'Defense Operations',
                isActive: _activeSection == 'defense_board',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('defense_board'),
                ),
              ),
              _FacultyNavEntry(
                section: 'audit_compliance',
                icon: Icons.summarize_rounded,
                label: 'Reports',
                isActive: _activeSection == 'audit_compliance',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('audit_compliance'),
                ),
              ),
            ],
          ),
        ];
        break;

      case FacultyWorkspace.pitInstructor:
        groups = [
          _FacultyNavGroup(
            title: 'Dashboard',
            entries: [
              _FacultyNavEntry(
                section: 'dashboard',
                icon: Icons.show_chart_rounded,
                label: 'Dashboard',
                isActive: _activeSection == 'dashboard',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('dashboard'),
                ),
              ),
            ],
          ),
          _FacultyNavGroup(
            title: 'Instruction',
            entries: [
              _FacultyNavEntry(
                section: 'deliverables',
                icon: Icons.folder_open_rounded,
                label: 'PIT Teams',
                isActive: _activeSection == 'deliverables',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('deliverables'),
                ),
              ),
              _FacultyNavEntry(
                section: 'audit_compliance',
                icon: Icons.summarize_rounded,
                label: 'Reports',
                isActive: _activeSection == 'audit_compliance',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('audit_compliance'),
                ),
              ),
            ],
          ),
        ];
        break;

      case FacultyWorkspace.documenter:
        groups = [
          _FacultyNavGroup(
            title: 'Dashboard',
            entries: [
              _FacultyNavEntry(
                section: 'dashboard',
                icon: Icons.show_chart_rounded,
                label: 'Dashboard',
                isActive: _activeSection == 'dashboard',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('dashboard'),
                ),
              ),
            ],
          ),
          _FacultyNavGroup(
            title: 'Operations',
            entries: [
              _FacultyNavEntry(
                section: 'defense_board',
                icon: Icons.view_agenda_rounded,
                label: 'Defense Operations',
                isActive: _activeSection == 'defense_board',
                onTap: () => _afterSidebarAction(
                  isWide,
                  () => _goToSection('defense_board'),
                ),
              ),
            ],
          ),
        ];
        break;
    }

    if (roles['uploader'] == true) {
      groups.add(
        _FacultyNavGroup(
          title: 'Tools',
          entries: [
            _FacultyNavEntry(
              section: 'uploader',
              icon: Icons.upload_file_rounded,
              label: 'Upload Documents',
              isActive: _activeSection == 'uploader',
              onTap: () => _afterSidebarAction(
                isWide,
                () => _goToSection('uploader'),
              ),
            ),
          ],
        ),
      );
    }

    return groups;
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
      return Container(
        color: DefensysTokens.backgroundOf(context),
        child: widget.routeChild!,
      );
    }

    final sectionFromRoute = FacultyRoutes.sectionForLocation(
      routerState.uri.path,
    );
    final activeSection = sectionFromRoute ?? _activeSection;

    final workspaceOption = _resolvedWorkspace(roles);
    final facultyName =
        widget.userData?['name']?.toString() ??
        dashState.data?['faculty']?['name']?.toString() ??
        'Faculty';

    if (!_isSectionSupportedByWorkspace(activeSection, workspaceOption.type)) {
      return workspaceOption.type == FacultyWorkspace.faculty
          ? const RepositoryTab()
          : Container(
              color: DefensysTokens.backgroundOf(context),
              child: const ProjectArchiveScreen(),
            );
    }

    switch (activeSection) {
      case 'deliverables':
        final ws = _resolvedWorkspace(roles);
        final initialScope = (ws.type == FacultyWorkspace.pitLead || ws.type == FacultyWorkspace.pitInstructor) ? 'pit' : 'capstone';
        final queryParams = routerState.uri.queryParameters;
        final teamIdParam = queryParams['teamId'];
        final tabParam = queryParams['tab'];
        final initialTeamId = teamIdParam != null ? int.tryParse(teamIdParam) : null;
        final initialTab = tabParam != null ? int.tryParse(tabParam) : null;
        return TeamDeliverablesScreen(
          initialScope: initialScope,
          isAdviser: ws.type == FacultyWorkspace.adviser,
          pitYearLevel: (ws.type == FacultyWorkspace.pitLead || ws.type == FacultyWorkspace.pitInstructor) ? ws.yearLevel : null,
          pitSection: ws.type == FacultyWorkspace.pitInstructor ? ws.section : null,
          initialTeamId: initialTeamId,
          initialTab: initialTab,
        );
      case 'weekly_reports':
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: const WeeklyProgressReportsScreen(),
        );
      case 'adviser_grading':
        final queryParams = routerState.uri.queryParameters;
        final teamIdParam = queryParams['teamId'];
        final tabParam = queryParams['tab'];
        final initialTeamId = teamIdParam != null ? int.tryParse(teamIdParam) : null;
        final initialTab = tabParam != null ? int.tryParse(tabParam) : null;
        return TeamDeliverablesScreen(
          initialScope: 'capstone',
          isAdviser: true,
          initialTeamId: initialTeamId,
          initialTab: initialTab,
        );
      case 'cohort':
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: PitLeadCohortScreen(
            onCreateTeam: () => _goToSection('student_teams'),
          ),
        );
      case 'pit_student_import':
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: const PitStudentImportScreen(),
        );
      case 'student_teams':
        final ws = _resolvedWorkspace(roles);
        final mode = ws.type == FacultyWorkspace.pitInstructor
            ? TeamListMode.pitInstructor
            : TeamListMode.pitLead;
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: StudentTeamsScreen(
            mode: mode,
            pitYearLevel: (ws.type == FacultyWorkspace.pitLead || ws.type == FacultyWorkspace.pitInstructor) ? ws.yearLevel : null,
            pitSection: ws.type == FacultyWorkspace.pitInstructor ? ws.section : null,
          ),
        );
      case 'pit_events':
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: const PitEventsManagementScreen(),
        );
      case 'pit_instructors':
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: PitInstructorAssignmentScreen(
            initialSection: routerState.uri.queryParameters['section'],
          ),
        );
      case 'project_archive':
      case 'repository_audit':
        final ws = _resolvedWorkspace(roles);
        if (ws.type == FacultyWorkspace.faculty) {
          return const RepositoryTab();
        }
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: const ProjectArchiveScreen(),
        );
      case 'audit_compliance':
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: const AuditComplianceScreen(),
        );
      case 'uploader':
        return Container(color: DefensysTokens.surfaceOf(context), child: const UploaderDashboard());
      case 'defense_scheduler':
        final user = ref.watch(authProvider).user;
        final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
        final isPitLead = roles['pit_lead'] == true || user?['is_pit_lead'] == true;
        if (!isAdmin && !isPitLead) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildWorkspaceDashboard(
              workspace: workspaceOption.type,
              dashState: dashState,
              facultyName: facultyName,
              yearLevel: workspaceOption.yearLevel,
              section: workspaceOption.section,
            ),
          );
        }
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: DefenseSchedulerScreen(
            onBack: () => _goToSection('defense_board'),
          ),
        );
      case 'defense_board':
        final isImport =
            GoRouterState.of(context).uri.path == FacultyRoutes.defenseScheduleBulkImport;
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: DefenseBoardScreen(initialBulkImport: isImport),
        );
      case 'grade_center':
        return Container(color: DefensysTokens.surfaceOf(context), child: const GradeCenterScreen());
      case 'rubrics':
        return Container(
          color: DefensysTokens.surfaceOf(context),
          child: RubricEngineScreen(key: ValueKey('rubrics_$_navigationEpoch')),
        );
      case 'dashboard':
      default:
        if (workspaceOption.type == FacultyWorkspace.faculty) {
          return const RepositoryTab();
        }
        final capstoneTeams = (dashState.data?['capstone_info_teams'] as List?) ?? [];
        final hasCapstoneInfo = capstoneTeams.isNotEmpty || roles['capstone_instructor'] == true;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWorkspaceDashboard(
                workspace: workspaceOption.type,
                dashState: dashState,
                facultyName: facultyName,
                yearLevel: workspaceOption.yearLevel,
                section: workspaceOption.section,
              ),
              if (hasCapstoneInfo)
                CapstoneInstructorInfoSection(
                  capstoneTeams: capstoneTeams,
                  capstoneYears: (roles['capstone_instructor_years'] as List?)?.cast<String>(),
                ),
            ],
          ),
        );
    }
  }

  Widget _buildWorkspaceDashboard({
    required FacultyWorkspace workspace,
    required DashboardState dashState,
    required String facultyName,
    String? yearLevel,
    String? section,
  }) {
    switch (workspace) {
      case FacultyWorkspace.faculty:
        return const RepositoryTab();
      case FacultyWorkspace.pitLead:
        return PitLeadDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          onOpenStudentTeams: () => _goToSection('student_teams'),
          onOpenScheduler: () => _goToSection('defense_scheduler'),
          onOpenGradeCenter: () => _goToSection('grade_center'),
          onOpenRubrics: () => _goToSection('rubrics'),
          onOpenCohort: () => _goToSection('cohort'),
          onOpenPitEvents: () => _goToSection('pit_events'),
          onOpenAuditCompliance: () => _goToSection('audit_compliance'),
        );
      case FacultyWorkspace.adviser:
        return AdviserDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          onOpenDeliverables: (teamId) => _goToSection('deliverables', queryParameters: {
            if (teamId != null) 'teamId': teamId.toString(),
            'tab': '0',
          }),
          onOpenWeeklyReports: (teamId) => _goToSection('deliverables', queryParameters: {
            if (teamId != null) 'teamId': teamId.toString(),
            'tab': '3',
          }),
          onOpenGrading: (teamId) => _goToSection('deliverables', queryParameters: {
            if (teamId != null) 'teamId': teamId.toString(),
            'tab': '1',
          }),
        );
      case FacultyWorkspace.pitInstructor:
        return PitInstructorDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          yearLevel: yearLevel,
          section: section,
          onOpenDeliverables: () => _goToSection('deliverables'),
          onOpenGrading: () => _goToSection('deliverables'),
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

class _FacultyNavGroup {
  final String title;
  final List<_FacultyNavEntry> entries;

  const _FacultyNavGroup({
    required this.title,
    required this.entries,
  });
}

class _FacultyNavEntry {
  final String section;
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FacultyNavEntry({
    required this.section,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });
}

class _FacultySectionHeader extends StatelessWidget {
  final String title;
  final bool isCollapsed;
  final bool isFirst;

  const _FacultySectionHeader({
    required this.title,
    this.isCollapsed = false,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isCollapsed) {
      if (isFirst) return const SizedBox(height: 4);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Divider(height: 1, thickness: 1, color: DefensysTokens.borderOf(context)),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 6 : 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamily,
          color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _FacultyNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isCollapsed;

  const _FacultyNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isCollapsed = false,
  });

  @override
  State<_FacultyNavItem> createState() => _FacultyNavItemState();
}

class _FacultyNavItemState extends State<_FacultyNavItem> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void didUpdateWidget(covariant _FacultyNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (_isPressed && widget.isActive) {
        _isPressed = false;
      }
    }
  }

  void _handleTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
  }

  void _handleTapCancel() {
    if (mounted) setState(() => _isPressed = false);
  }

  void _handleTapUp(TapUpDetails _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isPressed && !widget.isActive) {
        setState(() => _isPressed = false);
      }
    });
  }

  void _handleTap() {
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark ? DefensysTokens.mistMaroon : DefensysTokens.maroon;
    const activeColor = Colors.white;

    final isHighlighted = widget.isActive || _isPressed;
    final Color? bgColor;
    if (isHighlighted) {
      bgColor = activeBg;
    } else if (_isHovered) {
      bgColor = isDark ? const Color(0xFF28272D) : const Color(0xFFF4F4F5);
    } else {
      bgColor = null;
    }

    final textColor = isHighlighted
        ? activeColor
        : (isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B));
    final iconColor = isHighlighted
        ? activeColor
        : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B));

    if (widget.isCollapsed) {
      return Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              onTap: _handleTap,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 18,
                    color: iconColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: _handleTap,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: iconColor,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        color: textColor,
                        fontSize: 13,
                        fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarPanelIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _SidebarPanelIcon({
    this.size = 18,
    this.color = const Color(0xFF64748B),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _SidebarPanelPainter(color: color),
      ),
    );
  }
}

class _SidebarPanelPainter extends CustomPainter {
  final Color color;

  _SidebarPanelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.088;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(size.width * 0.22),
    );

    // Outer rounded rectangle
    canvas.drawRRect(rect, paint);

    // Inner vertical divider (left pane separator)
    final lineX = size.width * 0.35;
    canvas.drawLine(
      Offset(lineX, strokeWidth / 2),
      Offset(lineX, size.height - strokeWidth / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SidebarPanelPainter oldDelegate) => oldDelegate.color != color;
}

