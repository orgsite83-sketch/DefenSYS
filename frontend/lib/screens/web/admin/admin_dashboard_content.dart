import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/dashboard_provider.dart';
import 'widgets/defensys_admin_shell.dart';

class AdminDashboardContent extends ConsumerStatefulWidget {
  final ValueChanged<DefensysAdminSection> onNavigate;

  const AdminDashboardContent({super.key, required this.onNavigate});

  @override
  ConsumerState<AdminDashboardContent> createState() =>
      _AdminDashboardContentState();
}

class _AdminDashboardContentState extends ConsumerState<AdminDashboardContent> {
  static const _line = Color(0xFFF3F4F6);
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;

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
    final stats = _statsFrom(dashState.data?['stats']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DefensysPageHeader(
          icon: Icons.show_chart_rounded,
          title: 'Welcome back, Admin!',
          subtitle: 'Here is what is happening in the IT Department today.',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                value: _statValue(stats, 'total_students'),
                label: 'Active Students',
                icon: Icons.groups_rounded,
                iconColor: const Color(0xFF7C3AED),
                iconBackground: const Color(0xFFEDE3FF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: _statValue(stats, 'total_faculty'),
                label: 'Faculty Members',
                icon: Icons.co_present_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBackground: const Color(0xFFDCEBFF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: _statValue(stats, 'total_teams'),
                label: 'Active Teams',
                icon: Icons.groups_3_rounded,
                iconColor: const Color(0xFF047857),
                iconBackground: const Color(0xFFCFFAE7),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: _statValue(stats, 'upcoming_defenses'),
                label: 'Scheduled Defenses',
                icon: Icons.event_available_rounded,
                iconColor: const Color(0xFF92400E),
                iconBackground: const Color(0xFFFFEDB8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _quickActionsCard()),
            const SizedBox(width: 20),
            Expanded(child: _upcomingDefensesCard(dashState)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _teamOverviewCard(dashState)),
            const SizedBox(width: 20),
            Expanded(child: _systemAlertsCard(dashState)),
          ],
        ),
      ],
    );
  }

  Widget _metricCard({
    required String value,
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
  }) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: DefensysUi.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(width: 22),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 24,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF4B5565),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActionsCard() {
    return _dashboardCard(
      height: 378,
      title: 'Quick Actions',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 20, 28, 18),
        child: Column(
          children: [
            _quickAction(
              icon: Icons.group_add_rounded,
              iconColor: const Color(0xFF7C3AED),
              iconBackground: const Color(0xFFEDE3FF),
              title: 'Manage Users',
              subtitle: 'Add, import, or assign roles',
              onTap: () =>
                  widget.onNavigate(DefensysAdminSection.userManagement),
            ),
            _quickAction(
              icon: Icons.auto_fix_high_rounded,
              iconColor: const Color(0xFF047857),
              iconBackground: const Color(0xFFCFFAE7),
              title: 'Schedule a Defense',
              subtitle: 'Create a new scheduling run',
              onTap: () => widget.onNavigate(DefensysAdminSection.scheduling),
            ),
            _quickAction(
              icon: Icons.format_list_bulleted_rounded,
              iconColor: const Color(0xFF92400E),
              iconBackground: const Color(0xFFFFEDB8),
              title: 'Configure Rubrics',
              subtitle: 'Build or publish rubrics criteria',
              onTap: () => widget.onNavigate(DefensysAdminSection.rubricEngine),
            ),
            _quickAction(
              icon: Icons.layers_rounded,
              iconColor: const Color(0xFF2563EB),
              iconBackground: const Color(0xFFDCEBFF),
              title: 'Defense Stages',
              subtitle: 'Manage capstone stage pipeline',
              onTap: () =>
                  widget.onNavigate(DefensysAdminSection.defenseStages),
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _upcomingDefensesCard(DashboardState dashState) {
    return _dashboardCard(
      height: 378,
      title: 'Upcoming Defenses',
      actionLabel: 'View All',
      onActionTap: () => widget.onNavigate(DefensysAdminSection.scheduling),
      child: Center(
        child: Text(
          dashState.isLoading ? 'Loading...' : 'No scheduled defenses yet',
          style: const TextStyle(color: Color(0xFF9AA1B4), fontSize: 14),
        ),
      ),
    );
  }

  Widget _teamOverviewCard(DashboardState dashState) {
    return _dashboardCard(
      height: 148,
      title: 'Team Overview',
      actionLabel: 'Manage',
      onActionTap: () => widget.onNavigate(DefensysAdminSection.studentTeams),
      child: Center(
        child: Text(
          dashState.isLoading
              ? 'Loading...'
              : 'Open team management to review active teams',
          style: const TextStyle(color: Color(0xFF9AA1B4), fontSize: 14),
        ),
      ),
    );
  }

  Widget _systemAlertsCard(DashboardState dashState) {
    final alerts = _alertsFrom(dashState);

    return _dashboardCard(
      height: 148,
      title: 'System Status & Alerts',
      child: alerts.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              itemBuilder: (context, index) {
                final alert = alerts[index];
                final isWarning = alert['type'] == 'warning';
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isWarning
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      color: isWarning
                          ? const Color(0xFFD97706)
                          : const Color(0xFF059669),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        alert['message']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5D6678),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: alerts.length,
            ),
    );
  }

  Widget _dashboardCard({
    required String title,
    required Widget child,
    double? height,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    return Container(
      height: height,
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  InkWell(
                    onTap: onActionTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          color: _maroon,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
        child: SizedBox(
          height: 59,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFCDD2DB),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _statsFrom(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _alertsFrom(DashboardState dashState) {
    if (dashState.error != null) {
      return [
        {'type': 'warning', 'message': dashState.error},
      ];
    }

    final rawAlerts = dashState.data?['alerts'];
    if (rawAlerts is! List) {
      return const [];
    }

    return rawAlerts
        .whereType<Map>()
        .map(
          (alert) => alert.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }

  String _statValue(Map<String, dynamic> stats, String key) {
    final value = stats[key];
    if (value == null || value.toString().trim().isEmpty) {
      return '-';
    }
    return value.toString();
  }
}
