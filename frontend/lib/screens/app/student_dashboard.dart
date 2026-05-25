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
import '../../widgets/defensys_skeleton.dart';
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
    final initialLoad = dashState.isLoading && dashState.data == null;
    final showFatalError = dashState.error != null && dashState.data == null;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: PopScope(
      canPop: false,
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.studentDashboardTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (safeIndex != 0 && team != null)
              Text(
                team['name']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
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
                  backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.15),
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
