import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/academic_period_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../login_screen.dart';
import '../shared/repository_audit_screen.dart';
import 'academic_periods_screen.dart';
import 'admin_dashboard_content.dart';
import 'curriculum_analytics_screen.dart';
import 'defense_scheduler_screen.dart';
import 'defense_stages_screen.dart';
import 'grade_center_screen.dart';
import 'rubric_engine_screen.dart';
import 'student_academic_records_screen.dart';
import 'student_teams_screen.dart';
import 'user_management_screen.dart';
import 'widgets/defensys_admin_shell.dart';
import 'defense_board_screen.dart';

final activeAdminSectionProvider =
    NotifierProvider<ActiveAdminSectionNotifier, DefensysAdminSection>(
      ActiveAdminSectionNotifier.new,
    );

class ActiveAdminSectionNotifier extends Notifier<DefensysAdminSection> {
  @override
  DefensysAdminSection build() => DefensysAdminSection.overview;

  void setSection(DefensysAdminSection section) {
    state = section;
  }
}

class AdminShell extends ConsumerStatefulWidget {
  final Map<String, dynamic>? userData;

  const AdminShell({super.key, this.userData});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(activeAdminSectionProvider.notifier)
          .setSection(DefensysAdminSection.overview);
      ref.read(dashboardProvider('admin').notifier).fetchDashboardData();
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeSection = ref.watch(activeAdminSectionProvider);
    final dashboardState = ref.watch(dashboardProvider('admin'));
    final academicState = ref.watch(academicPeriodProvider);

    return DefensysAdminShell(
      activeSection: activeSection,
      activeSemesterLabel: _topSemesterLabel(
        academicState.activeSemester,
        dashboardState.data?['active_semester'],
      ),
      scrollContent: false,
      onNavigate: (section) {
        ref.read(activeAdminSectionProvider.notifier).setSection(section);
      },
      onLogout: _logout,
      child: IndexedStack(
        index: activeSection.index,
        children: [
          _ContentViewport(
            child: AdminDashboardContent(onNavigate: _setActiveSection),
          ),
          const _ContentViewport(child: AcademicPeriodsScreen()),
          const UserManagementScreen(),
          StudentTeamsScreen(
            mode: TeamListMode.capstoneAdmin,
            onOpenStudentRecords: () =>
                _setActiveSection(DefensysAdminSection.studentAcademicRecords),
          ),
          const StudentAcademicRecordsScreen(),
          const GradeCenterScreen(),
          const RubricEngineScreen(),
          const RepositoryAuditScreen(),
          const CurriculumAnalyticsScreen(),
          const DefenseSchedulerScreen(),
          const DefenseBoardScreen(),
          const DefenseStagesScreen(),
        ],
      ),
    );
  }

  void _setActiveSection(DefensysAdminSection section) {
    ref.read(activeAdminSectionProvider.notifier).setSection(section);
  }

  void _logout() {
    ref.read(authProvider.notifier).logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String _topSemesterLabel(
    Map<String, dynamic>? activePeriod,
    dynamic dashboardLabel,
  ) {
    if (activePeriod != null) {
      return 'Active Sem: ${activePeriod['school_year'] ?? 'Configured'}';
    }

    final label = dashboardLabel?.toString().trim() ?? '';
    if (label.isEmpty || label == 'Not configured' || label == 'Loading...') {
      return 'No Active Semester';
    }

    final schoolYear = RegExp(r'\d{4}-\d{4}').firstMatch(label)?.group(0);
    return 'Active Sem: ${schoolYear ?? label}';
  }
}

class _ContentViewport extends StatelessWidget {
  final Widget child;

  const _ContentViewport({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: child,
    );
  }
}
