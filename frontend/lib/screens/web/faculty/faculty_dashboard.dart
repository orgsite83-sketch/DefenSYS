import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/auth_provider.dart';
import '../../login_screen.dart';
import '../../../theme/app_theme.dart';
import '../shared/capstone_deliverables_screen.dart';
import '../shared/repository_audit_screen.dart';
import '../admin/defense_scheduler_screen.dart';
import '../admin/defense_board_screen.dart';
import '../admin/grade_center_screen.dart';
import '../admin/rubric_engine_screen.dart';
import '../admin/student_teams_screen.dart';
import '../uploader/uploader_dashboard.dart';
import 'adviser_grading_screen.dart';
import 'weekly_progress_reports_screen.dart';

class FacultyDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;
  const FacultyDashboard({super.key, this.userData});

  @override
  ConsumerState<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends ConsumerState<FacultyDashboard> {
  static const _primaryColor = Color(0xFF7F1D1D);
  String _activeSection = 'dashboard'; // Track active section
  bool _schedulingExpanded = false; // Track scheduling section expansion

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
    final activeRoles =
        (dashState.data?['active_roles'] as List?)?.cast<String>() ?? [];

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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Permanent Sidebar
          if (showSidebar) _buildPermanentSidebar(roles),
          
          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Top AppBar
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Spacer(),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermanentSidebar(Map<String, dynamic> roles) {
    return Container(
      width: 260,
      color: _primaryColor,
      child: Column(
        children: [
          // Header
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
                        color: _primaryColor,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  'DefenSYS',
                  style: TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withOpacity(0.07)),
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 20),
              children: [
                _buildSidebarItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  onTap: () {
                    setState(() {
                      _activeSection = 'dashboard';
                    });
                  },
                  isActive: _activeSection == 'dashboard',
                ),
                const SizedBox(height: 8),
                
                // Adviser-specific features
                if (roles['adviser'] == true) ...[
                  _buildSidebarItem(
                    icon: Icons.folder_open_outlined,
                    label: 'Capstone Deliverables',
                    onTap: () {
                      setState(() {
                        _activeSection = 'deliverables';
                      });
                    },
                    isActive: _activeSection == 'deliverables',
                  ),
                  _buildSidebarItem(
                    icon: Icons.assignment_outlined,
                    label: 'Weekly Progress Reports',
                    onTap: () {
                      setState(() {
                        _activeSection = 'weekly_reports';
                      });
                    },
                    isActive: _activeSection == 'weekly_reports',
                  ),
                  _buildSidebarItem(
                    icon: Icons.rate_review_rounded,
                    label: 'Grade Students',
                    onTap: () {
                      setState(() {
                        _activeSection = 'adviser_grading';
                      });
                    },
                    isActive: _activeSection == 'adviser_grading',
                  ),
                ],
                
                // PIT Lead specific features
                if (roles['pit_lead'] == true) ...[
                  const SizedBox(height: 8),
                  _buildSidebarItem(
                    icon: Icons.groups_outlined,
                    label: 'Student Teams',
                    onTap: () {
                      setState(() {
                        _activeSection = 'student_teams';
                      });
                    },
                    isActive: _activeSection == 'student_teams',
                  ),
                  
                  // Scheduling Section (Expandable)
                  _buildExpandableSidebarItem(
                    icon: Icons.calendar_month_outlined,
                    label: 'Scheduling',
                    isExpanded: _schedulingExpanded,
                    onTap: () {
                      setState(() {
                        _schedulingExpanded = !_schedulingExpanded;
                      });
                    },
                  ),
                  if (_schedulingExpanded) ...[
                    _buildSubSidebarItem(
                      icon: Icons.event_outlined,
                      label: 'Defense Scheduler',
                      onTap: () {
                        setState(() {
                          _activeSection = 'defense_scheduler';
                        });
                      },
                      isActive: _activeSection == 'defense_scheduler',
                    ),
                    _buildSubSidebarItem(
                      icon: Icons.view_list_outlined,
                      label: 'Defense Board',
                      onTap: () {
                        setState(() {
                          _activeSection = 'defense_board';
                        });
                      },
                      isActive: _activeSection == 'defense_board',
                    ),
                  ],
                  
                  _buildSidebarItem(
                    icon: Icons.grading_outlined,
                    label: 'Grade Center',
                    onTap: () {
                      setState(() {
                        _activeSection = 'grade_center';
                      });
                    },
                    isActive: _activeSection == 'grade_center',
                  ),
                  _buildSidebarItem(
                    icon: Icons.rule_outlined,
                    label: 'Rubric Engine',
                    onTap: () {
                      setState(() {
                        _activeSection = 'rubric_engine';
                      });
                    },
                    isActive: _activeSection == 'rubric_engine',
                  ),
                ],
                
                // PIT Lead and Repo Assistant features
                if (roles['pit_lead'] == true || roles['repo_assistant'] == true) ...[
                  _buildSidebarItem(
                    icon: Icons.manage_search,
                    label: 'Repository Audit',
                    onTap: () {
                      setState(() {
                        _activeSection = 'repository_audit';
                      });
                    },
                    isActive: _activeSection == 'repository_audit',
                  ),
                ],
                
                // Uploader feature
                if (roles['uploader'] == true) ...[
                  _buildSidebarItem(
                    icon: Icons.upload_file,
                    label: 'Upload Documents',
                    onTap: () {
                      setState(() {
                        _activeSection = 'uploader';
                      });
                    },
                    isActive: _activeSection == 'uploader',
                  ),
                ],
              ],
            ),
          ),
          
          // Footer
          Container(height: 1, color: Colors.white.withOpacity(0.09)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                ref.read(authProvider.notifier).logout();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              hoverColor: Colors.white.withOpacity(0.05),
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

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final color = isActive ? const Color(0xFFFFC107) : const Color(0xFFD1D5DB);
    
    return Material(
      color: isActive ? const Color(0xFF5E0D08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withOpacity(0.05),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: isActive
                ? const Border(
                    left: BorderSide(color: Color(0xFFFFC107), width: 4),
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
        hoverColor: Colors.white.withOpacity(0.05),
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
    final color = isActive ? const Color(0xFFFFC107) : const Color(0xFFD1D5DB);
    
    return Material(
      color: isActive ? const Color(0xFF5E0D08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.white.withOpacity(0.05),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: isActive
                ? const Border(
                    left: BorderSide(color: Color(0xFFFFC107), width: 4),
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
    final activeRoles = (dashState.data?['active_roles'] as List?)?.cast<String>() ?? [];
    
    // For screens with their own Scaffold, wrap them in a container to prevent conflicts
    switch (_activeSection) {
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
      case 'student_teams':
        return Container(
          color: Colors.white,
          child: const StudentTeamsScreen(),
        );
      case 'repository_audit':
        return Container(
          color: Colors.white,
          child: const RepositoryAuditScreen(),
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, ${widget.userData?['name'] ?? 'Faculty'}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (roles['panelist'] == true)
                    _buildRoleChip('Panelist', Colors.purple),
                  if (roles['pit_lead'] == true)
                    _buildRoleChip(
                      'PIT Lead: ${roles['pit_lead_year'] ?? 'Unscoped'}',
                      Colors.blue,
                    ),
                  if (roles['adviser'] == true)
                    _buildRoleChip('Project Adviser', Colors.green),
                  if (roles['repo_assistant'] == true)
                    _buildRoleChip('Repo Assistant', Colors.orange),
                  if (activeRoles.isEmpty)
                    _buildRoleChip(
                      'No semester roles assigned',
                      Colors.grey,
                    ),
                ],
              ),
              const SizedBox(height: 24),

              _buildDashboardContent(dashState, roles),
            ],
          ),
        );
    }
  }

  Widget _buildDashboardContent(DashboardState dashState, Map<String, dynamic> roles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'My Advised Teams',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Teams List
        ...(dashState.data?['advised_teams'] as List? ?? []).map((
          team,
        ) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team['name'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        team['projectTitle'],
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          team['currentStage'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                team['status'],
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _openCapstoneDeliverables,
                              icon: const Icon(Icons.folder_open_outlined),
                              label: const Text('Deliverables'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if ((dashState.data?['advised_teams'] as List? ?? []).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No advised teams yet. Team data migrates in a later phase.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
      ],
    );
  }

  Widget _buildRoleChip(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.shade700,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _openCapstoneDeliverables() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CapstoneDeliverablesScreen()),
    );

    if (!mounted) {
      return;
    }
    ref.read(dashboardProvider('faculty').notifier).fetchDashboardData();
  }

  Future<void> _openRepositoryAudit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RepositoryAuditScreen()),
    );

    if (!mounted) {
      return;
    }
    ref.read(dashboardProvider('faculty').notifier).fetchDashboardData();
  }

  void _openWeeklyProgressReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WeeklyProgressReportsScreen()),
    );
  }
}
