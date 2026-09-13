import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/academic_period_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/defense_board_provider.dart';
import '../../../widgets/defensys_skeleton.dart';
import '../../../widgets/feedback/empty_state.dart';
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
  static const _line = Color(0xFFF3F4F6);
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;

  static const double _cardHeight = 356.0;

  int _bottomRightTabIndex = 0; // 0 = Action Items, 1 = Recent Audit Logs

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
    final academicState = ref.watch(academicPeriodProvider);

    ref.listen<DefensysAdminSection>(activeAdminSectionProvider, (previous, next) {
      if (next == DefensysAdminSection.overview && previous != DefensysAdminSection.overview) {
        ref.read(dashboardProvider('admin').notifier).fetchDashboardData(silent: true);
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
      }
    });

    ref.listen<AcademicPeriodState>(academicPeriodProvider, (previous, next) {
      if (previous?.activeSemester?['id'] != next.activeSemester?['id']) {
        ref.read(dashboardProvider('admin').notifier).fetchDashboardData(silent: true);
      }
    });

    final initialLoad = dashState.isLoading && dashState.data == null;
    final stats = _statsFrom(dashState.data?['stats']);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefensysPageHeader(
              icon: Icons.show_chart_rounded,
              title: 'Welcome back, Admin!',
              subtitle: 'Here is what is happening in the IT Department today.',
              actions: OutlinedButton.icon(
                onPressed: dashState.isRefreshing
                    ? null
                    : () {
                        ref
                            .read(dashboardProvider('admin').notifier)
                            .fetchDashboardData(silent: true);
                        ref.read(academicPeriodProvider.notifier).fetchPeriods();
                      },
                icon: dashState.isRefreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _maroon,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(dashState.isRefreshing ? 'Refreshing...' : 'Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (initialLoad)
              DefensysSkeleton.metricRow()
            else
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
                Expanded(child: _teamPipelineCard(dashState)),
                const SizedBox(width: 20),
                Expanded(child: _actionAndAuditCard(dashState, academicState)),
              ],
            ),
          ],
        ),
      ),
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
          Expanded(
            child: Column(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4B5565),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionsCard() {
    return _dashboardCard(
      height: _cardHeight,
      title: 'Quick Actions',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
              onTap: () => widget.onNavigate(DefensysAdminSection.rubrics),
            ),
            _quickAction(
              icon: Icons.layers_rounded,
              iconColor: const Color(0xFF2563EB),
              iconBackground: const Color(0xFFDCEBFF),
              title: 'Defense Stages Setup',
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
    final upcomingList = _upcomingDefensesFrom(dashState);
    final count = upcomingList.length;

    return _dashboardCard(
      height: _cardHeight,
      title: 'Upcoming Defenses',
      actionLabel: count > 0 ? 'View Calendar' : null,
      onActionTap: () => widget.onNavigate(DefensysAdminSection.scheduling),
      child: dashState.isLoading && dashState.data == null
          ? const Center(child: CircularProgressIndicator())
          : count == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Color(0xFF64748B),
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No Scheduled Defenses',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'There are no defense sessions currently on the calendar for this period.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => widget.onNavigate(
                          DefensysAdminSection.scheduling,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Schedule Defense'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => widget.onNavigate(
                          DefensysAdminSection.defenseStages,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Stage Setup'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              itemCount: count,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = upcomingList[index];
                return _defenseScheduleItem(item);
              },
            ),
    );
  }

  Widget _defenseScheduleItem(Map<String, dynamic> item) {
    final teamName = item['team_name']?.toString() ?? 'Team';
    final projectTitle = item['project_title']?.toString() ?? '';
    final stageLabel = item['stage_label']?.toString() ?? 'Defense';
    final dateStr = item['date']?.toString() ?? '';
    final timeStr = item['start_time']?.toString() ?? '';
    final room = item['room']?.toString() ?? 'TBD';
    final panelistCount = item['panelist_count']?.toString() ?? '0';

    return InkWell(
      onTap: () => widget.onNavigate(DefensysAdminSection.scheduling),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatMonth(dateStr),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _maroon,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _formatDay(dateStr),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          teamName,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          stageLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (projectTitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      projectTitle,
                      style: const TextStyle(fontSize: 12, color: _muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (timeStr.isNotEmpty) ...[
                        const Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      const Icon(
                        Icons.meeting_room_outlined,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        room,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.group_outlined,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$panelistCount Panelists',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamPipelineCard(DashboardState dashState) {
    final pipeline = _pipelineFrom(dashState.data?['team_pipeline']);
    final stats = _statsFrom(dashState.data?['stats']);

    final totalTeams =
        pipeline['total_teams'] as int? ??
        (int.tryParse(stats['total_teams']?.toString() ?? '0') ?? 0);
    final readyForDefense =
        pipeline['ready_for_defense'] as int? ??
        (int.tryParse(stats['ready_capstone_teams']?.toString() ?? '0') ?? 0);
    final withAdviser = pipeline['teams_with_adviser'] as int? ?? 0;
    final capstoneCount = pipeline['capstone_teams'] as int? ?? 0;
    final pitCount = pipeline['pit_teams'] as int? ?? 0;
    final stages =
        (pipeline['stage_distribution'] as List?)?.cast<Map>() ?? [];

    return _dashboardCard(
      height: _cardHeight,
      title: 'Team Pipeline & Readiness',
      actionLabel: 'Manage Teams',
      onActionTap: () => widget.onNavigate(DefensysAdminSection.studentTeams),
      child: dashState.isLoading && dashState.data == null
          ? const Center(child: CircularProgressIndicator())
          : totalTeams == 0
          ? const DefensysEmptyState(
              icon: Icons.groups_outlined,
              title: 'No Active Teams Formed',
              description:
                  'Review or import student teams under Team Management.',
              size: DefensysEmptyStateSize.compact,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top 3 Key Metrics
                  Row(
                    children: [
                      Expanded(
                        child: _miniMetricTile(
                          label: 'Total Teams',
                          value: '$totalTeams',
                          color: const Color(0xFF047857),
                          bgColor: const Color(0xFFECFDF5),
                          borderColor: const Color(0xFFA7F3D0),
                          icon: Icons.groups_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniMetricTile(
                          label: 'Stage Ready',
                          value: '$readyForDefense',
                          color: const Color(0xFF2563EB),
                          bgColor: const Color(0xFFEFF6FF),
                          borderColor: const Color(0xFFBFDBFE),
                          icon: Icons.verified_rounded,
                          onTap: () => widget.onNavigate(
                            _mapSection('defenseBoardReadiness'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniMetricTile(
                          label: 'With Adviser',
                          value: capstoneCount > 0
                              ? '${((withAdviser / capstoneCount) * 100).round()}%'
                              : (totalTeams > 0 ? 'N/A' : '0%'),
                          color: const Color(0xFF7C3AED),
                          bgColor: const Color(0xFFF5F3FF),
                          borderColor: const Color(0xFFDDD6FE),
                          icon: Icons.school_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Stage Distribution Section
                  const Text(
                    'DEFENSE STAGE DISTRIBUTION',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (stages.isNotEmpty)
                    Row(
                      children: stages.map((stage) {
                        final label = stage['label']?.toString() ?? '';
                        final count = stage['count']?.toString() ?? '0';
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  count,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$readyForDefense teams ready for scheduling • $totalTeams total active',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Adviser Assignment & Track Breakdown Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          capstoneCount == 0
                              ? Icons.info_outline_rounded
                              : (withAdviser == capstoneCount
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.info_outline_rounded),
                          size: 16,
                          color: capstoneCount > 0 && withAdviser == capstoneCount
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            capstoneCount > 0
                                ? '$withAdviser of $capstoneCount Capstone teams assigned with advisers'
                                : 'Advisers apply to Capstone teams only',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Capstone: $capstoneCount · PIT: $pitCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _miniMetricTile({
    required String label,
    required String value,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.0,
                  ),
                ),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionAndAuditCard(
    DashboardState dashState,
    AcademicPeriodState academicState,
  ) {
    final actionItems = _actionItemsFrom(dashState, academicState);
    final recentActivity = _recentActivityFrom(dashState);
    final activeSem = _resolveActiveSemesterLabel(dashState, academicState);

    return Container(
      height: _cardHeight,
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connected Tabs Header Bar
          Container(
            height: 48,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _tabButton(
                  title: 'Action Items',
                  badgeCount: actionItems.length,
                  icon: Icons.checklist_rtl_rounded,
                  isSelected: _bottomRightTabIndex == 0,
                  onTap: () => setState(() => _bottomRightTabIndex = 0),
                ),
                const SizedBox(width: 14),
                _tabButton(
                  title: 'Audit Logs',
                  icon: Icons.history_rounded,
                  isSelected: _bottomRightTabIndex == 1,
                  onTap: () => setState(() => _bottomRightTabIndex = 1),
                ),
                const Spacer(),
                if (_bottomRightTabIndex == 0)
                  InkWell(
                    onTap: dashState.isRefreshing
                        ? null
                        : () {
                            ref
                                .read(dashboardProvider('admin').notifier)
                                .fetchDashboardData(silent: true);
                            ref
                                .read(academicPeriodProvider.notifier)
                                .fetchPeriods();
                          },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (dashState.isRefreshing)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: _maroon,
                              ),
                            )
                          else
                            const Icon(
                              Icons.refresh_rounded,
                              size: 14,
                              color: _maroon,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            dashState.isRefreshing ? 'Refreshing...' : 'Refresh',
                            style: const TextStyle(
                              color: _maroon,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  InkWell(
                    onTap: () =>
                        widget.onNavigate(DefensysAdminSection.auditCompliance),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All',
                            style: TextStyle(
                              color: _maroon,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: _maroon,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Tab Content Body
          Expanded(
            child: dashState.isLoading && dashState.data == null
                ? const Center(child: CircularProgressIndicator(color: _maroon))
                : _bottomRightTabIndex == 0
                ? _buildActionItemsView(actionItems, activeSem)
                : _buildAuditLogsView(recentActivity),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
    int? badgeCount,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? _maroon : Colors.transparent,
              width: 3.0,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? _maroon : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? _ink : const Color(0xFF64748B),
                letterSpacing: -0.2,
              ),
            ),
            if (badgeCount != null && badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFDC2626)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionItemsView(
    List<Map<String, dynamic>> items,
    String activeSem,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Academic Period Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Period: $activeSem',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF059669),
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'All Clear — No Pending Actions',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'All teams assigned and defense pipeline is up to date.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final itemId = item['id']?.toString() ?? '';
                      final title = item['title']?.toString() ?? 'Action Item';
                      final desc = item['description']?.toString() ?? '';
                      final targetSectionKey =
                          item['target_section']?.toString() ?? '';
                      final buttonLabel =
                          item['button_label']?.toString() ?? 'Action';

                      // Determine action-specific styling (Task categories instead of passive warnings)
                      IconData actionIcon;
                      Color iconColor;
                      Color iconBg;
                      Color badgeBg;
                      Color badgeBorder;
                      Color badgeTextColor;
                      String categoryLabel;

                      if (itemId == 'unscheduled_ready_teams' ||
                          targetSectionKey == 'defenseBoardReadiness' ||
                          targetSectionKey == 'scheduling') {
                        actionIcon = Icons.event_available_rounded;
                        iconColor = const Color(0xFF059669);
                        iconBg = const Color(0xFFD1FAE5);
                        badgeBg = const Color(0xFFECFDF5);
                        badgeBorder = const Color(0xFFA7F3D0);
                        badgeTextColor = const Color(0xFF047857);
                        categoryLabel = 'READY TO SCHEDULE';
                      } else if (itemId == 'unassigned_advisers' ||
                          targetSectionKey == 'studentTeams') {
                        actionIcon = Icons.person_add_alt_1_rounded;
                        iconColor = const Color(0xFF4F46E5);
                        iconBg = const Color(0xFFE0E7FF);
                        badgeBg = const Color(0xFFEEF2FF);
                        badgeBorder = const Color(0xFFC7D2FE);
                        badgeTextColor = const Color(0xFF4338CA);
                        categoryLabel = 'ADVISER ASSIGNMENT';
                      } else if (itemId == 'pending_grades' ||
                          targetSectionKey == 'gradeCenter') {
                        actionIcon = Icons.grading_rounded;
                        iconColor = const Color(0xFFD97706);
                        iconBg = const Color(0xFFFEF3C7);
                        badgeBg = const Color(0xFFFFFBEB);
                        badgeBorder = const Color(0xFFFDE68A);
                        badgeTextColor = const Color(0xFFB45309);
                        categoryLabel = 'GRADE REVIEW';
                      } else {
                        actionIcon = Icons.tune_rounded;
                        iconColor = const Color(0xFFDC2626);
                        iconBg = const Color(0xFFFEE2E2);
                        badgeBg = const Color(0xFFFEF2F2);
                        badgeBorder = const Color(0xFFFECACA);
                        badgeTextColor = const Color(0xFFB91C1C);
                        categoryLabel = 'SETUP REQUIRED';
                      }

                      return InkWell(
                        onTap: () => widget.onNavigate(
                          _mapSection(targetSectionKey),
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x06000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: iconBg,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  actionIcon,
                                  color: iconColor,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeBg,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border:
                                                Border.all(color: badgeBorder),
                                          ),
                                          child: Text(
                                            categoryLabel,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                              color: badgeTextColor,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: _ink,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _muted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                onPressed: () => widget.onNavigate(
                                  _mapSection(targetSectionKey),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _maroon,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                                label: Text(
                                  buttonLabel,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogsView(List<Map<String, dynamic>> logs) {
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'No recent audit activity recorded.',
          style: TextStyle(color: Color(0xFF9AA1B4), fontSize: 12.5),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = logs[index];
        final actor = log['actor_name']?.toString() ?? 'System';
        final actionLabel = log['action_label']?.toString() ?? 'Action';
        final category = log['category']?.toString() ?? '';
        final timestamp = log['timestamp']?.toString() ?? '';

        final catColor = _categoryColor(category);
        final catIcon = _categoryIcon(category);

        return InkWell(
          onTap: () => widget.onNavigate(DefensysAdminSection.auditCompliance),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(catIcon, color: catColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              actor,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _timeAgo(timestamp),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        actionLabel,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF475569),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        );
      },
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFCDD2DB),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  String _formatMonth(String dateStr) {
    if (dateStr.isEmpty) return 'TBD';
    try {
      final dt = DateTime.parse(dateStr);
      const months = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ];
      return months[dt.month - 1];
    } catch (_) {
      return 'DEF';
    }
  }

  String _formatDay(String dateStr) {
    if (dateStr.isEmpty) return '--';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}';
    } catch (_) {
      return '--';
    }
  }

  String _timeAgo(String isoTimestamp) {
    if (isoTimestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTimestamp).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'student_teams':
        return const Color(0xFF047857);
      case 'scheduling':
        return const Color(0xFF92400E);
      case 'grade_center':
        return const Color(0xFF2563EB);
      case 'rubrics':
        return const Color(0xFF7C3AED);
      case 'user_management':
        return const Color(0xFF4F46E5);
      case 'repository':
        return const Color(0xFF0D9488);
      case 'auth':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF64748B);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'student_teams':
        return Icons.groups_rounded;
      case 'scheduling':
        return Icons.event_available_rounded;
      case 'grade_center':
        return Icons.school_rounded;
      case 'rubrics':
        return Icons.rule_folder_rounded;
      case 'user_management':
        return Icons.manage_accounts_rounded;
      case 'repository':
        return Icons.folder_shared_rounded;
      case 'auth':
        return Icons.security_rounded;
      default:
        return Icons.history_rounded;
    }
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
      default:
        return DefensysAdminSection.overview;
    }
  }

  List<Map<String, dynamic>> _upcomingDefensesFrom(DashboardState dashState) {
    final raw = dashState.data?['upcoming_defenses_list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  String _resolveActiveSemesterLabel(
    DashboardState dashState,
    AcademicPeriodState academicState,
  ) {
    final backendSem = dashState.data?['active_semester']?.toString().trim();
    if (backendSem != null &&
        backendSem.isNotEmpty &&
        backendSem != 'Not configured' &&
        backendSem != 'Loading...') {
      return backendSem;
    }
    if (academicState.activeSemester != null) {
      final label = academicState.activeSemester!['label']?.toString() ?? '';
      final sy =
          academicState.activeSemester!['school_year']?.toString() ?? '';
      if (label.isNotEmpty && sy.isNotEmpty) {
        return '$label, A.Y. $sy';
      } else if (label.isNotEmpty) {
        return label;
      } else if (sy.isNotEmpty) {
        return 'A.Y. $sy';
      }
    }
    return backendSem ?? 'Not configured';
  }

  List<Map<String, dynamic>> _actionItemsFrom(
    DashboardState dashState,
    AcademicPeriodState academicState,
  ) {
    final raw = dashState.data?['action_items'];
    if (raw is! List) return const [];
    final items = raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    if (academicState.activeSemester != null) {
      items.removeWhere((item) => item['id'] == 'no_active_period');
    }
    return items;
  }

  List<Map<String, dynamic>> _recentActivityFrom(DashboardState dashState) {
    final raw = dashState.data?['recent_activity'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Map<String, dynamic> _pipelineFrom(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
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

  String _statValue(Map<String, dynamic> stats, String key) {
    final value = stats[key];
    if (value == null || value.toString().trim().isEmpty) {
      return '-';
    }
    return value.toString();
  }
}
