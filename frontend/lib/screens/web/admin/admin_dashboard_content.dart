import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../notifications/notifications_provider.dart';
import '../../../services/academic_period_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/defense_board_provider.dart';
import 'admin_overview_workspace.dart';
import '../../../services/app/data_refresh_provider.dart';
import 'admin_shell.dart';
import 'widgets/defensys_admin_shell.dart';

class AdminDashboardContent extends ConsumerStatefulWidget {
  final ValueChanged<DefensysAdminSection> onNavigate;

  const AdminDashboardContent({super.key, required this.onNavigate});

  @override
  ConsumerState<AdminDashboardContent> createState() =>
      _AdminDashboardContentState();
}

class _AdminDashboardContentState extends ConsumerState<AdminDashboardContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardProvider('admin').notifier).fetchDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(dashboardProvider('admin'));

    // New inbox entries can arrive while this dashboard stays mounted.
    // Also notice decisions made by another admin when the inbox polls again.
    // Read flags do not affect approval work.
    ref.listen<String>(
      notificationsProvider('admin').select(_approvalInboxState),
      (previous, next) {
        if (previous != next) {
          ref
              .read(dashboardProvider('admin').notifier)
              .fetchDashboardData(silent: true);
        }
      },
    );

    ref.listen<DefensysAdminSection>(activeAdminSectionProvider, (
      previous,
      next,
    ) {
      if (next == DefensysAdminSection.overview &&
          previous != DefensysAdminSection.overview) {
        ref
            .read(dashboardProvider('admin').notifier)
            .fetchDashboardData(silent: true);
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
      }
    });

    ref.listen<AcademicPeriodState>(academicPeriodProvider, (previous, next) {
      if (previous?.activeSemester?['id'] != next.activeSemester?['id']) {
        ref
            .read(dashboardProvider('admin').notifier)
            .fetchDashboardData(silent: true);
      }
    });

    ref.listen<int>(
      dataRefreshProvider.select((value) => value[DataArea.dashboard] ?? 0),
      (previous, next) {
        if (previous != next) {
          ref
              .read(dashboardProvider('admin').notifier)
              .fetchDashboardData(silent: true);
        }
      },
    );

    return AdminOverviewWorkspace(
      data: dashState.data,
      error: dashState.error,
      loading: dashState.isLoading && dashState.data == null,
      refreshing: dashState.isRefreshing,
      onRefresh: () {
        ref
            .read(dashboardProvider('admin').notifier)
            .fetchDashboardData(silent: true);
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
      },
      onAction: _openActionItem,
    );
  }

  String _approvalInboxState(NotificationsState state) {
    final requests = <String>[];
    for (final notification in state.notifications) {
      final payload = notification['action_payload'];
      final action = notification['action'];
      if (payload is Map &&
          (payload['action_kind'] == 'panelist_request' ||
              payload['panelist_eligibility'] == true)) {
        requests.add(
          '${payload['request_id']}:${action is Map ? action['status'] : ''}',
        );
      }
    }
    requests.sort();
    return '${state.totalCount}|${requests.join(',')}';
  }

  void _openActionItem(Map<String, dynamic> item) {
    if (const [
      'defenseBoardSchedules',
      'defenseBoardReadiness',
      'readiness',
      'teamReadiness',
    ].contains(item['target_section'])) {
      final program = item['scope']?.toString() ?? 'capstone';
      ref
          .read(defenseBoardProvider.notifier)
          .fetchBoard(
            scope: program,
            search: '',
            stage: '',
            status: '',
            adviser: '',
            section: '',
          );
    }
    final route = Uri.tryParse(item['target_route']?.toString() ?? '');
    final router = GoRouter.maybeOf(context);
    if (router != null &&
        route != null &&
        !route.hasScheme &&
        !route.hasAuthority &&
        route.path.startsWith('/admin/')) {
      router.go(route.toString());
      return;
    }
    widget.onNavigate(_mapSection(item['target_section']?.toString() ?? ''));
  }

  DefensysAdminSection _mapSection(String sectionKey) {
    switch (sectionKey) {
      case 'studentTeams':
        return DefensysAdminSection.studentTeams;
      case 'defenseBoardReadiness':
      case 'teamReadiness':
      case 'readiness':
        ref
            .read(defenseBoardActiveViewProvider.notifier)
            .setView(DefenseOperationsView.readiness);
        return DefensysAdminSection.defenseBoard;
      case 'defenseBoard':
        return DefensysAdminSection.defenseBoard;
      case 'defenseBoardSchedules':
        ref
            .read(defenseBoardActiveViewProvider.notifier)
            .setView(DefenseOperationsView.schedules);
        return DefensysAdminSection.defenseBoard;
      case 'scheduling':
        ref
            .read(defenseBoardActiveViewProvider.notifier)
            .setView(DefenseOperationsView.readiness);
        return DefensysAdminSection.defenseBoard;
      case 'gradeCenter':
        return DefensysAdminSection.gradeCenter;
      case 'academicPeriods':
        return DefensysAdminSection.academicPeriods;
      case 'rubrics':
        return DefensysAdminSection.rubrics;
      case 'userManagement':
        return DefensysAdminSection.userManagement;
      case 'defenseStages':
        return DefensysAdminSection.defenseStages;
      case 'auditCompliance':
        return DefensysAdminSection.auditCompliance;
      default:
        return DefensysAdminSection.overview;
    }
  }
}
