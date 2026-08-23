import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../navigation/admin_route_paths.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/offline_banner.dart';
import '../../../widgets/defensys_logo_mark.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../services/unsaved_changes_provider.dart';
import '../../../utils/unsaved_changes.dart';
import '../../../notifications/notifications_modal.dart';
import '../../../notifications/notifications_provider.dart';
import '../shared/team_deliverables/team_deliverables_screen.dart';
import '../shared/project_archive/project_archive_screen.dart';
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

enum FacultyWorkspace { pitLead, adviser, pitInstructor, documenter }

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

    // Show sidebar if user has any faculty role
    final showSidebar =
        roles['adviser'] == true ||
        roles['pit_lead'] == true ||
        roles['documenter'] == true ||
        roles['uploader'] == true ||
        roles['pit_instructor'] == true ||
        roles['capstone_instructor'] == true;

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
    return workspaces;
  }

  bool _isSectionSupportedByWorkspace(String section, FacultyWorkspace workspace) {
    switch (workspace) {
      case FacultyWorkspace.pitLead:
        return const {
          'dashboard',
          'pit_events',
          'rubric_engine',
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
      return const WorkspaceOption(type: FacultyWorkspace.adviser);
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
      _activeSection = 'dashboard';
      _navigationEpoch++;
    });
    context.go(FacultyRoutes.dashboard);
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
                const DefensysLogoMark(size: 40),
                const SizedBox(width: 14),
                const Text(
                  'DefenSYS',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: Colors.white,
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
                child: DropdownButton<WorkspaceOption>(
                  isExpanded: true,
                  value: workspaceOption,
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
                          child: Text(_workspaceLabel(ws)),
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
                ..._sidebarItemsForWorkspace(workspaceOption.type, roles, isWide: isWide),
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
          _buildUserProfileCard(facultyName, _workspaceLabel(workspaceOption), isWide),
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
          _buildSectionHeader('Setup & Configuration'),
          _buildSidebarItem(
            icon: Icons.event_note_outlined,
            label: 'PIT Events Setup',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('pit_events'),
            ),
            isActive: _activeSection == 'pit_events',
          ),
          _buildSidebarItem(
            icon: Icons.rule_outlined,
            label: 'Rubrics',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('rubrics'),
            ),
            isActive: _activeSection == 'rubrics',
          ),
          _buildSectionHeader('People & Teams'),
          _buildSidebarItem(
            icon: Icons.school_outlined,
            label: 'Cohort',
            onTap: () =>
                _afterSidebarAction(isWide, () => _goToSection('cohort')),
            isActive:
                _activeSection == 'cohort' ||
                _activeSection == 'pit_student_import' ||
                _activeSection == 'pit_instructors',
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
          _buildSectionHeader('Defense Operations'),
          _buildSidebarItem(
            icon: Icons.view_agenda_outlined,
            label: 'Defense Operations',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('defense_board'),
            ),
            isActive: _activeSection == 'defense_board' ||
                _activeSection == 'defense_scheduler',
          ),
          _buildSidebarItem(
            icon: Icons.grading_outlined,
            label: 'Evaluation & Grades',
            onTap: () =>
                _afterSidebarAction(isWide, () => _goToSection('grade_center')),
            isActive: _activeSection == 'grade_center',
          ),
          _buildSectionHeader('Archives & Audit'),
          _buildSidebarItem(
            icon: Icons.manage_search,
            label: 'Project Archive',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('project_archive'),
            ),
            isActive: _activeSection == 'project_archive' ||
                _activeSection == 'repository_audit',
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
            label: 'Capstone Teams',
            onTap: () =>
                _afterSidebarAction(isWide, () => _goToSection('deliverables')),
            isActive: _activeSection == 'deliverables',
          ),
          _buildSidebarItem(
            icon: Icons.view_agenda_outlined,
            label: 'Defense Operations',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('defense_board'),
            ),
            isActive: _activeSection == 'defense_board',
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
            label: 'PIT Teams',
            onTap: () => _afterSidebarAction(
              isWide,
              () => _goToSection('deliverables'),
            ),
            isActive: _activeSection == 'deliverables',
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
            icon: Icons.view_agenda_outlined,
            label: 'Defense Operations',
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

    final workspaceOption = _resolvedWorkspace(roles);
    final facultyName =
        widget.userData?['name']?.toString() ??
        dashState.data?['faculty']?['name']?.toString() ??
        'Faculty';

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
          color: Colors.white,
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
        final mode = ws.type == FacultyWorkspace.pitInstructor
            ? TeamListMode.pitInstructor
            : TeamListMode.pitLead;
        return Container(
          color: Colors.white,
          child: StudentTeamsScreen(
            mode: mode,
            pitYearLevel: (ws.type == FacultyWorkspace.pitLead || ws.type == FacultyWorkspace.pitInstructor) ? ws.yearLevel : null,
            pitSection: ws.type == FacultyWorkspace.pitInstructor ? ws.section : null,
          ),
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
      case 'project_archive':
      case 'repository_audit':
        return Container(
          color: Colors.white,
          child: const ProjectArchiveScreen(),
        );
      case 'audit_compliance':
        return Container(
          color: Colors.white,
          child: const AuditComplianceScreen(),
        );
      case 'uploader':
        return Container(color: Colors.white, child: const UploaderDashboard());
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
      case 'rubrics':
      case 'rubric_engine':
        return Container(
          color: Colors.white,
          child: RubricEngineScreen(key: ValueKey('rubric_engine_$_navigationEpoch')),
        );
      case 'dashboard':
      default:
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
      case FacultyWorkspace.pitLead:
        return PitLeadDashboardContent(
          data: dashState.data,
          facultyName: facultyName,
          onOpenStudentTeams: () => _goToSection('student_teams'),
          onOpenScheduler: () => _goToSection('defense_scheduler'),
          onOpenGradeCenter: () => _goToSection('grade_center'),
          onOpenRubrics: () => _goToSection('rubrics'),
          onOpenCohort: () => _goToSection('cohort'),
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
