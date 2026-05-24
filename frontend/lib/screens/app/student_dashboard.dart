import 'package:flutter/material.dart';
import '../about_screen.dart';
import '../privacy_screen.dart';
import '../terms_screen.dart';
import 'student/team_tab.dart';
import 'student/repository_tab.dart';
import 'student/peer_eval_tab.dart';
import 'student/weekly_report_tab.dart';
import 'student/my_grades_tab.dart';
import 'student/profile_edit_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/dashboard_provider.dart';
import '../../services/auth_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../l10n/l10n_ext.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/offline_banner.dart';

class StudentDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  const StudentDashboard({super.key, this.userData});

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard> {
  int _selectedIndex = 0;
  late final StudentProfile _profile;

  final Map<String, bool> _peerPosted = {};

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(dashboardProvider('student'));

    final dataToPass = Map<String, dynamic>.from(
      dashState.data ?? <String, dynamic>{},
    );

    final team = dataToPass['team'] as Map<String, dynamic>?;
    final isCapstone = team?['isCapstone'] == true;

    final tabChildren = <Widget>[
      TeamTab(
        studentData: dataToPass,
        peerPosted: _peerPosted,
        onRefresh: () =>
            ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
      ),
      const RepositoryTab(),
      isCapstone
          ? const WeeklyReportTab()
          : MyGradesTab(studentData: dataToPass),
      PeerEvalTab(
        isCapstone: isCapstone,
        peerEvalAllowed: dataToPass['peerEvalEnabled'] == true,
        teammates: (dataToPass['members'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .where(
              (m) => m['id']?.toString() != widget.userData?['id']?.toString(),
            )
            .toList(),
        peerCriteria: (dataToPass['peerCriteria'] as List? ?? [])
            .cast<Map<String, dynamic>>(),
        myPeerSubmissions: (dataToPass['myPeerSubmissions'] as List? ?? [])
            .cast<Map<String, dynamic>>(),
        studentId: widget.userData?['id']?.toString() ?? '',
        teamId: dataToPass['team']?['id']?.toString() ?? '',
        peerWeight: (dataToPass['weights']?['peer'] as num?)?.toInt() ?? 20,
        onPeerSubmitted: () {
          ref.read(dashboardProvider('student').notifier).fetchDashboardData();
        },
      ),
    ];

    final l10n = context.l10n;
    final destinations = <NavigationDestination>[
      NavigationDestination(icon: const Icon(Icons.group), label: l10n.navTeam),
      NavigationDestination(
        icon: const Icon(Icons.folder_open),
        label: l10n.navDigitalVault,
      ),
      NavigationDestination(
        icon: Icon(isCapstone ? Icons.assignment : Icons.grade),
        label: isCapstone ? l10n.navWeeklyReport : l10n.navMyGrades,
      ),
      NavigationDestination(
        icon: const Icon(Icons.star_rate),
        label: l10n.navPeerEval,
      ),
    ];

    final safeIndex = _selectedIndex.clamp(0, tabChildren.length - 1);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
        title: Text(
          context.l10n.studentDashboardTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: _profile.avatarBytes != null
                ? CircleAvatar(
                    radius: 14,
                    backgroundImage: MemoryImage(_profile.avatarBytes!),
                  )
                : const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile',
            onPressed: () => _showProfileSheet(context),
          ),
        ],
      ),
      body: OfflineBanner(
        child: dashState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : dashState.error != null
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
                            ref.read(dashboardProvider('student').notifier).fetchDashboardData();
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
              : Column(
                  children: [
                    // Team Summary Card - Always visible
                    if (team != null) _buildTeamSummaryCard(team),
                    // Main Content
                    Expanded(
                      child: IndexedStack(
                        index: safeIndex,
                        children: tabChildren,
                      ),
                    ),
                  ],
                ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        indicatorColor: DefensysTokens.maroon.withOpacity(0.15),
        destinations: destinations,
      ),
    ),
    );
  }

  Widget _buildTeamSummaryCard(Map<String, dynamic> team) {
    final teamName = team['name'] ?? 'Unknown Team';
    final projectTitle = team['projectTitle'] ?? '—';
    final level = team['level'] ?? '—';
    final status = team['status'] ?? 'Pending';
    final memberCount = team['memberCount'] ?? 0;
    final adviserName = team['adviserName'] ?? 'Unassigned';
    final isCapstone = team['isCapstone'] == true;

    final statusColor = status == 'Approved'
        ? Colors.green
        : status == 'Failed'
            ? Colors.red
            : Colors.orange;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [DefensysTokens.maroon, DefensysTokens.maroon.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DefensysTokens.maroon.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _selectedIndex = 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isCapstone ? Icons.school : Icons.book,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            teamName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            level,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.assignment, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              projectTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.people, color: Colors.white70, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '$memberCount ${memberCount == 1 ? 'Member' : 'Members'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (isCapstone)
                            Row(
                              children: [
                                const Icon(Icons.person_pin, color: Colors.white70, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  adviserName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Tap for details',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white.withOpacity(0.7),
                      size: 12,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: DefensysTokens.maroon.withOpacity(0.15),
                  backgroundImage: _profile.avatarBytes != null
                      ? MemoryImage(_profile.avatarBytes!)
                      : null,
                  child: _profile.avatarBytes == null
                      ? Text(
                          _profile.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: DefensysTokens.maroon,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  _profile.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Student · ${_profile.team}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: DefensysTokens.maroon),
                title: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: DefensysTokens.maroon,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final updated = await Navigator.push<StudentProfile>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileEditScreen(profile: _profile),
                    ),
                  );
                  if (updated != null) setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About DefenSYS'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.gavel_rounded),
                title: const Text('Terms & Conditions'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  if (await confirmLogout(context)) {
                    await ref.read(authProvider.notifier).logout();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
