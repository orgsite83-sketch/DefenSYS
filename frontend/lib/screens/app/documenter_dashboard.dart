import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../navigation/admin_route_paths.dart';
import '../../notifications/notifications_bell.dart';
import '../../services/auth_provider.dart';
import '../../services/documenter_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../widgets/branding/defensys_mobile_brand.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/minutes/documenter_assignments_view.dart';
import '../../widgets/minutes/faculty_app_workspace_switcher.dart';
import 'student/profile_edit_screen.dart';

class DocumenterDashboard extends ConsumerStatefulWidget {
  const DocumenterDashboard({super.key});
  @override
  ConsumerState<DocumenterDashboard> createState() =>
      _DocumenterDashboardState();
}

class _DocumenterDashboardState extends ConsumerState<DocumenterDashboard>
    with WidgetsBindingObserver {
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(documenterProvider.notifier).fetchAssignments();
      final token = ref.read(authProvider).token;
      if (token != null) {
        ref.read(authProvider.notifier).fetchCurrentUser(token);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DefensysTokens.backgroundOf(context),
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: DefensysTokens.maroon,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: DefensysMobileBrand.usesMobileHeader(context) ? 56 : 72,
      title: DefensysMobileBrand.usesMobileHeader(context)
          ? const DefensysMobileBrand()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DefenSYS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ['Documenter workspace', 'Minutes records', 'Profile'][_tab],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
      actions: const [
        NotificationsBell(
          workspace: 'documenter',
          workspaceLabel: 'Minutes Documenter',
          color: Colors.white,
        ),
        FacultyAppWorkspaceSwitcher(currentRoute: AppRoutes.documenter),
      ],
    ),
    body: _tab == 2
        ? const ProfileScreen(showAppBar: false, includeAppSettings: true)
        : OfflineBanner(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(documenterProvider.notifier).fetchAssignments(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: DocumenterAssignmentsView(
                  recordsOnly: _tab == 1,
                  showHeader: DefensysMobileBrand.usesMobileHeader(context),
                  onOpenMinutes: (id) =>
                      context.go('${AppRoutes.documenter}/minutes/$id'),
                ),
              ),
            ),
          ),
    bottomNavigationBar: NavigationBar(
      backgroundColor: DefensysTokens.surfaceOf(context),
      surfaceTintColor: Colors.transparent,
      indicatorColor: DefensysTokens.maroonTextOf(
        context,
      ).withValues(alpha: 0.10),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          selectedIcon: Icon(Icons.assignment_rounded),
          label: 'Assignments',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_open_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: 'Records',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );
}
