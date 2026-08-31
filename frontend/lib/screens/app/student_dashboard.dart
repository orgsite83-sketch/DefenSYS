import 'package:flutter/material.dart';
import '../about_screen.dart';
import '../privacy_screen.dart';
import '../terms_screen.dart';
import 'student/student_events_tab.dart';
import 'student/team_tab.dart';
import 'student/repository_tab.dart';
import 'student/section_integration_tab.dart';
import 'student/profile_edit_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../services/dashboard_provider.dart';
import '../../services/auth_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../l10n/l10n_ext.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/defensys_skeleton.dart';
import '../../widgets/offline_banner.dart';
import '../../notifications/notifications_modal.dart';
import '../../notifications/notifications_provider.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  const StudentDashboard({super.key, this.userData});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard> {
  int _selectedIndex = 0;
  final _eventsSubTabNotifier = ValueNotifier<int>(0);
  late final StudentProfile _profile;

  @override
  void initState() {
    super.initState();
    final u = widget.userData;
    _profile = StudentProfile(
      name: u?['name'] ?? u?['first_name'] ?? 'Student',
      email: u?['email'] ?? '',
      studentId: u?['id']?.toString() ?? u?['username'] ?? '—',
      team: u?['team_id'] ?? '—',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardProvider('student').notifier).fetchDashboardData();
      ref.read(notificationsProvider.notifier).fetchNotifications();
    });
  }

  @override
  void dispose() {
    _eventsSubTabNotifier.dispose();
    super.dispose();
  }

  Future<void> _refreshDashboardAndNotifications() async {
    await Future.wait([
      ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
      ref.read(notificationsProvider.notifier).fetchNotifications(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(dashboardProvider('student'));
    final delivState = ref.watch(capstoneDeliverablesProvider);

    final dataToPass = Map<String, dynamic>.from(
      dashState.data ?? <String, dynamic>{},
    );

    final team = dataToPass['team'] as Map<String, dynamic>?;
    final isCapstone = team?['isCapstone'] == true;

    final isPM = widget.userData?['is_project_manager'] == true ||
        dataToPass['student']?['is_project_manager'] == true;

    final hasPendingEvents = StudentTaskBadgeHelper.hasPendingEvents(
      selectedStage: delivState.currentTeamSelectedStage,
      studentData: dataToPass,
    );

    final student = dataToPass['student'] as Map<String, dynamic>?;
    final studentName = student?['name']?.toString().trim().isNotEmpty == true
        ? student!['name'].toString().trim()
        : (widget.userData?['name'] ?? widget.userData?['first_name'] ?? _profile.name);

    final members = (dataToPass['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final isLeader = student?['is_leader'] == true ||
        student?['isLeader'] == true ||
        widget.userData?['is_leader'] == true ||
        widget.userData?['isLeader'] == true ||
        members.any((m) =>
            (m['id'] == student?['id'] || m['username'] == widget.userData?['username']) &&
            (m['isLeader'] == true || m['is_leader'] == true));
    final roleTag = isPM ? 'Project Manager' : (isLeader ? 'Leader' : 'Member');

    final teamName = team?['name']?.toString();
    final teamLevel = team?['level']?.toString() ??
        (isCapstone ? 'Capstone Project' : 'Design Project');

    final deliverables = (dataToPass['deliverables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    int fileCount = 0;
    for (final d in deliverables) {
      final files = d['files'] as List?;
      if (files != null && files.isNotEmpty) {
        fileCount += files.length;
      } else if (d['file_url'] != null || d['file_name'] != null) {
        fileCount += 1;
      }
    }
    if (fileCount == 0 && deliverables.isNotEmpty) {
      fileCount = deliverables.length;
    }

    final schedule = dataToPass['schedule'] as Map<String, dynamic>?;
    final grades = dataToPass['grades'] as Map<String, dynamic>?;
    final String stageName = schedule?['stage']?.toString() ??
        grades?['stage']?.toString() ??
        delivState.currentTeamSelectedStage?.toString() ??
        'Project Proposal';
    final isPassed = grades?['result'] == 'PASSED' || grades?['is_published'] == true;

    final tabChildren = <Widget>[
      TeamTab(
        studentData: dataToPass,
        onRefresh: _refreshDashboardAndNotifications,
        onSelectTab: (int index) => setState(() => _selectedIndex = index),
      ),
      StudentEventsTab(
        isCapstone: isCapstone,
        studentData: dataToPass,
        subTabNotifier: _eventsSubTabNotifier,
      ),
      const RepositoryTab(),
      if (isPM)
        SectionIntegrationTab(studentData: dataToPass),
      const ProfileScreen(showAppBar: false),
    ];

    final l10n = context.l10n;
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.group_outlined),
        selectedIcon: const Icon(Icons.group),
        label: l10n.navTeam,
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: hasPendingEvents,
          smallSize: 8,
          backgroundColor: Colors.redAccent,
          child: Icon(isCapstone ? Icons.alt_route_rounded : Icons.event_note_rounded),
        ),
        label: isCapstone ? 'Stages' : 'Events',
      ),
      NavigationDestination(
        icon: const Icon(Icons.folder_open_outlined),
        selectedIcon: const Icon(Icons.folder),
        label: l10n.navRepository,
      ),
      if (isPM)
        const NavigationDestination(
          icon: Icon(Icons.hub_outlined),
          selectedIcon: Icon(Icons.hub),
          label: 'Integration',
        ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    ];

    final safeIndex = _selectedIndex.clamp(0, tabChildren.length - 1);
    final initialLoad = dashState.isLoading && dashState.data == null;
    final showFatalError = dashState.error != null && dashState.data == null;

    String tabTitle;
    String tabSubtitle;
    if (safeIndex == 0) {
      tabTitle = 'Team Workspace';
      tabSubtitle = teamName != null ? '$teamName · $teamLevel' : 'Roster & Project Overview';
    } else if (safeIndex == 1) {
      tabTitle = isCapstone ? 'Defense Roadmap' : 'Defense Events';
      tabSubtitle = isPassed ? '$stageName Cleared ✓' : '$stageName Phase';
    } else if (safeIndex == 2) {
      tabTitle = 'Repository';
      tabSubtitle = fileCount > 0 ? '$fileCount Files Submitted' : 'Deliverables & Manuscripts';
    } else if (isPM && safeIndex == 3) {
      tabTitle = 'Section Integration';
      tabSubtitle = 'Section Deliverables & Reports';
    } else {
      tabTitle = 'Account & Security';
      tabSubtitle = '$studentName ($roleTag)';
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: PopScope(
      canPop: false,
      child: Scaffold(
      drawer: _buildStudentDrawer(
        context,
        dataToPass: dataToPass,
        isPM: isPM,
        studentName: studentName,
        roleTag: roleTag,
        teamName: teamName,
        hasPendingDeliverables: delivState.hasPendingDeliverables,
        hasPendingPeerEval: StudentTaskBadgeHelper.hasPendingPeerEval(dataToPass),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            tooltip: 'Navigation Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tabTitle,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tabSubtitle,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Consumer(
            builder: (context, ref, child) {
              final state = ref.watch(notificationsProvider);
              return Badge(
                isLabelVisible: state.unreadCount > 0,
                label: Text(
                  state.unreadCount.toString(),
                  style: const TextStyle(
                    color: DefensysTokens.maroon,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: Colors.white,
                textColor: DefensysTokens.maroon,
                child: IconButton(
                  icon: const Icon(Icons.notifications_outlined, color: Colors.white),
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
          const SizedBox(width: 4),
        ],
      ),
      body: OfflineBanner(
        child: showFatalError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading dashboard',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dashState.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          ref
                              .read(dashboardProvider('student').notifier)
                              .fetchDashboardData();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DefensysTokens.maroon,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : initialLoad
                ? DefensysSkeleton.tabContent()
                : IndexedStack(
                    index: safeIndex,
                    children: tabChildren,
                  ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        indicatorColor: DefensysTokens.maroon.withValues(alpha: 0.15),
        destinations: destinations,
      ),
    ),
    ),
    );
  }

  Widget _buildStudentDrawer(
    BuildContext context, {
    required Map<String, dynamic> dataToPass,
    required bool isPM,
    required String studentName,
    required String roleTag,
    required String? teamName,
    required bool hasPendingDeliverables,
    required bool hasPendingPeerEval,
  }) {
    final user = ref.watch(authProvider).user;
    final avatarUrl = user?['avatar'] != null
        ? ApiConfig.publicMediaUrl(user!['avatar'] as String)
        : null;
    final academicPeriod = dataToPass['academic_period'] as Map<String, dynamic>? ??
        (dataToPass['team'] as Map<String, dynamic>?)?['academic_period'] as Map<String, dynamic>?;
    final termName = academicPeriod?['name']?.toString() ??
        academicPeriod?['semester']?.toString() ??
        'AY 2026-2027';

    final notifState = ref.watch(notificationsProvider);

    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drawer Header with gradient maroon
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 20,
                20,
                20,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DefensysTokens.maroon,
                    Color(0xFF520B13),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'DefenSYS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          termName,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Text(
                                studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              teamName != null ? '$roleTag · $teamName' : roleTag,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Navigation Links / Action Shortcuts (Clean Single-Line Items)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                children: [
                  _drawerSectionHeader('QUICK ACCESS'),
                  _drawerItem(
                    icon: Icons.upload_file_rounded,
                    title: 'Deliverables & Manuscripts',
                    badgeLabel: hasPendingDeliverables ? 'Pending' : null,
                    badgeColor: const Color(0xFFEA580C),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 1);
                      _eventsSubTabNotifier.value = 1;
                    },
                  ),
                  _drawerItem(
                    icon: Icons.how_to_reg_rounded,
                    title: 'Peer Evaluation',
                    badgeLabel: hasPendingPeerEval ? 'Due Soon' : null,
                    badgeColor: const Color(0xFFDC2626),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 1);
                      _eventsSubTabNotifier.value = 2;
                    },
                  ),
                  _drawerItem(
                    icon: Icons.calendar_month_rounded,
                    title: 'Defense Schedule',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 1);
                      _eventsSubTabNotifier.value = 0;
                    },
                  ),
                  _drawerItem(
                    icon: Icons.folder_shared_rounded,
                    title: 'Project Repository',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 2);
                    },
                  ),
                  if (isPM)
                    _drawerItem(
                      icon: Icons.hub_rounded,
                      title: 'Section Integration Hub',
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _selectedIndex = 3);
                      },
                    ),
                  _drawerItem(
                    icon: Icons.draw_rounded,
                    title: 'E-Signature & Security',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = (isPM ? 4 : 3));
                    },
                  ),
                  _drawerItem(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    badgeCount: notifState.unreadCount,
                    onTap: () {
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => const NotificationsModal(),
                      );
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Divider(color: Color(0xFFE2E8F0)),
                  ),

                  _drawerSectionHeader('SYSTEM & POLICIES'),
                  _drawerItem(
                    icon: Icons.info_outline_rounded,
                    title: 'About DefenSYS',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.gavel_rounded,
                    title: 'Terms & Conditions',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TermsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Bottom Sign Out Tile
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: InkWell(
                onTap: () async {
                  final authNotifier = ref.read(authProvider.notifier);
                  Navigator.pop(context);
                  if (await confirmLogout(context)) {
                    await authNotifier.logout();
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 18),
                      SizedBox(width: 12),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Spacer(),
                      Icon(Icons.chevron_right_rounded, color: Color(0xFFDC2626), size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: DefensysTokens.textSecondary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? badgeLabel,
    Color? badgeColor,
    int? badgeCount,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 19,
                color: DefensysTokens.maroon,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badgeLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? const Color(0xFFDC2626)).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (badgeColor ?? const Color(0xFFDC2626)).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: badgeColor ?? const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (badgeCount != null && badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFFCBD5E1),
              ),
          ],
        ),
      ),
    );
  }
}
