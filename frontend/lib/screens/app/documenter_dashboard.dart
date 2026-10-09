import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../navigation/admin_route_paths.dart';
import '../../services/auth_provider.dart';
import '../../services/documenter_provider.dart';
import '../../theme/defensys_tokens.dart';
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
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: DefensysTokens.maroon,
      foregroundColor: Colors.white,
      title: Text(
        ['Documenter workspace', 'Minutes records', 'Profile'][_tab],
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      actions: const [
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
                padding: const EdgeInsets.all(16),
                child: DocumenterAssignmentsView(
                  recordsOnly: _tab == 1,
                  showHeader: false,
                  onOpenMinutes: (id) =>
                      context.go('${AppRoutes.documenter}/minutes/$id'),
                ),
              ),
            ),
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.assignment_outlined),
          label: 'Assignments',
        ),
        NavigationDestination(
          icon: Icon(Icons.picture_as_pdf_outlined),
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
