import 'package:flutter/material.dart';

import '../../../../widgets/feedback/empty_state.dart';
import '../../admin/widgets/defensys_admin_shell.dart';

class PitLeadDashboardContent extends StatefulWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final VoidCallback onOpenStudentTeams;
  final VoidCallback onOpenScheduler;
  final VoidCallback onOpenGradeCenter;
  final VoidCallback onOpenRubrics;
  final VoidCallback onOpenCohort;
  final VoidCallback onOpenPitEvents;
  final VoidCallback onOpenAuditCompliance;

  const PitLeadDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenStudentTeams,
    required this.onOpenScheduler,
    required this.onOpenGradeCenter,
    required this.onOpenRubrics,
    required this.onOpenCohort,
    required this.onOpenPitEvents,
    required this.onOpenAuditCompliance,
  });

  @override
  State<PitLeadDashboardContent> createState() => _PitLeadDashboardContentState();
}

class _PitLeadDashboardContentState extends State<PitLeadDashboardContent> {
  static const _line = Color(0xFFF3F4F6);
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;

  static const double _cardHeight = 356.0;

  int _bottomRightTabIndex = 0; // 0 = Action Items, 1 = Recent Activity Logs

  @override
  Widget build(BuildContext context) {
    final pitYear = widget.data?['pit_lead_year']?.toString() ?? 'Unscoped';
    final overview =
        (widget.data?['pit_lead_overview'] as Map?)?.cast<String, dynamic>() ??
        {};
    final stats = _statsFrom(overview['stats']);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefensysPageHeader(
              icon: Icons.workspace_premium_rounded,
              title: 'Welcome, ${widget.facultyName}!',
              subtitle: 'PIT Lead workspace · $pitYear',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    value: _statValue(stats, 'students_in_cohort'),
                    label: 'Students in Cohort',
                    icon: Icons.groups_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    iconBackground: const Color(0xFFEDE3FF),
                    onTap: widget.onOpenCohort,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _metricCard(
                    value: _statValue(stats, 'pit_teams'),
                    label: 'Active PIT Teams',
                    icon: Icons.groups_3_rounded,
                    iconColor: const Color(0xFF047857),
                    iconBackground: const Color(0xFFCFFAE7),
                    onTap: widget.onOpenStudentTeams,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _metricCard(
                    value: _statValue(stats, 'scheduled_events'),
                    label: 'Scheduled PIT Events',
                    icon: Icons.event_available_rounded,
                    iconColor: const Color(0xFF92400E),
                    iconBackground: const Color(0xFFFFEDB8),
                    onTap: widget.onOpenScheduler,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _metricCard(
                    value: _statValue(stats, 'pending_grades'),
                    label: 'Pending Grades',
                    icon: Icons.fact_check_outlined,
                    iconColor: const Color(0xFF2563EB),
                    iconBackground: const Color(0xFFDCEBFF),
                    onTap: widget.onOpenGradeCenter,
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
                Expanded(child: _upcomingDefensesCard(overview)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _teamPipelineCard(overview, pitYear)),
                const SizedBox(width: 20),
                Expanded(child: _actionAndAuditCard(overview)),
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
    VoidCallback? onTap,
  }) {
    final content = Container(
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
                  style: const TextStyle(
                    color: Color(0xFF4B5565),
                    fontSize: 14,
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
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
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
              icon: Icons.groups_rounded,
              iconColor: const Color(0xFF7C3AED),
              iconBackground: const Color(0xFFEDE3FF),
              title: 'Manage PIT Teams',
              subtitle: 'Create or update teams for your year level',
              onTap: widget.onOpenStudentTeams,
            ),
            _quickAction(
              icon: Icons.auto_fix_high_rounded,
              iconColor: const Color(0xFF047857),
              iconBackground: const Color(0xFFCFFAE7),
              title: 'Schedule PIT Event',
              subtitle: 'Plan presentations in Defense Scheduler',
              onTap: widget.onOpenScheduler,
            ),
            _quickAction(
              icon: Icons.format_list_bulleted_rounded,
              iconColor: const Color(0xFF92400E),
              iconBackground: const Color(0xFFFFEDB8),
              title: 'Configure Rubrics',
              subtitle: 'Build or configure grading rubrics',
              onTap: widget.onOpenRubrics,
            ),
            _quickAction(
              icon: Icons.layers_rounded,
              iconColor: const Color(0xFF2563EB),
              iconBackground: const Color(0xFFDCEBFF),
              title: 'PIT Events Setup',
              subtitle: 'Manage PIT stages & event milestones',
              onTap: widget.onOpenPitEvents,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _upcomingDefensesCard(Map<String, dynamic> overview) {
    final upcomingList = _upcomingDefensesFrom(overview);
    final count = upcomingList.length;

    return _dashboardCard(
      height: _cardHeight,
      title: 'Upcoming PIT Events',
      actionLabel: count > 0 ? 'View Calendar' : null,
      onActionTap: widget.onOpenScheduler,
      child: count == 0
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
                    'No Scheduled PIT Events',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'There are no defense or presentation sessions currently on the calendar for this period.',
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
                        onPressed: widget.onOpenScheduler,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Schedule Event'),
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
                        onPressed: widget.onOpenPitEvents,
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
                        child: const Text('Events Setup'),
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
    final stageLabel = item['stage_label']?.toString() ?? 'PIT Event';
    final dateStr = item['date']?.toString() ?? '';
    final timeStr = item['start_time']?.toString() ?? '';
    final room = item['room']?.toString() ?? 'TBD';
    final panelistCount = item['panelist_count']?.toString() ?? '0';

    return InkWell(
      onTap: widget.onOpenScheduler,
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

  Widget _teamPipelineCard(Map<String, dynamic> overview, String pitYear) {
    final pipeline = _pipelineFrom(overview['team_pipeline']);
    final stats = _statsFrom(overview['stats']);

    final totalTeams =
        pipeline['total_teams'] as int? ??
        (int.tryParse(stats['pit_teams']?.toString() ?? '0') ?? 0);
    final readyForDefense =
        pipeline['ready_for_defense'] as int? ??
        (int.tryParse(stats['ready_pit_teams']?.toString() ?? '0') ?? 0);
    final withInstructor =
        pipeline['teams_with_instructor'] as int? ??
        pipeline['teams_with_adviser'] as int? ??
        0;
    final stages =
        (pipeline['stage_distribution'] as List?)?.cast<Map>() ?? [];

    return _dashboardCard(
      height: _cardHeight,
      title: 'PIT Pipeline & Readiness',
      actionLabel: 'Manage Teams',
      onActionTap: widget.onOpenStudentTeams,
      child: totalTeams == 0
          ? const DefensysEmptyState(
              icon: Icons.groups_outlined,
              title: 'No Active PIT Teams Formed',
              description:
                  'Review cohort roster or import students under Team Management.',
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
                          onTap: widget.onOpenScheduler,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _miniMetricTile(
                          label: 'With Instructor',
                          value: totalTeams > 0
                              ? '${((withInstructor / totalTeams) * 100).round()}%'
                              : '0%',
                          color: const Color(0xFF15803D),
                          bgColor: const Color(0xFFF0FDF4),
                          borderColor: const Color(0xFFBBF7D0),
                          icon: Icons.co_present_rounded,
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
                          withInstructor == totalTeams
                              ? Icons.check_circle_outline_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: withInstructor == totalTeams
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$withInstructor of $totalTeams teams assigned to section instructors',
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
                            'Cohort: $pitYear',
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

  Widget _actionAndAuditCard(Map<String, dynamic> overview) {
    final actionItems = _actionItemsFrom(overview);
    final recentActivity = _recentActivityFrom(overview);
    final alerts = (overview['alerts'] as List?) ?? [];
    final activeSem =
        overview['active_semester']?.toString() ??
        widget.data?['active_semester']?.toString() ??
        'Active Semester';

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
                  title: 'Activity Logs',
                  icon: Icons.history_rounded,
                  isSelected: _bottomRightTabIndex == 1,
                  onTap: () => setState(() => _bottomRightTabIndex = 1),
                ),
                const Spacer(),
                InkWell(
                  onTap: widget.onOpenAuditCompliance,
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
            child: _bottomRightTabIndex == 0
                ? _buildActionItemsView(actionItems, activeSem)
                : _buildAuditLogsView(recentActivity, alerts),
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
                          'All PIT teams assigned and presentation pipeline is up to date.',
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

                      IconData actionIcon;
                      Color iconColor;
                      Color iconBg;
                      Color badgeBg;
                      Color badgeBorder;
                      Color badgeTextColor;
                      String categoryLabel;
                      VoidCallback onActionTap;

                      if (itemId == 'unscheduled_ready_teams' ||
                          targetSectionKey == 'defense_scheduler') {
                        actionIcon = Icons.event_available_rounded;
                        iconColor = const Color(0xFF059669);
                        iconBg = const Color(0xFFD1FAE5);
                        badgeBg = const Color(0xFFECFDF5);
                        badgeBorder = const Color(0xFFA7F3D0);
                        badgeTextColor = const Color(0xFF047857);
                        categoryLabel = 'READY TO SCHEDULE';
                        onActionTap = widget.onOpenScheduler;
                      } else if (itemId == 'unassigned_instructors' ||
                          targetSectionKey == 'pit_instructors') {
                        actionIcon = Icons.person_add_alt_1_rounded;
                        iconColor = const Color(0xFF15803D);
                        iconBg = const Color(0xFFDCFCE7);
                        badgeBg = const Color(0xFFF0FDF4);
                        badgeBorder = const Color(0xFFBBF7D0);
                        badgeTextColor = const Color(0xFF166534);
                        categoryLabel = 'INSTRUCTOR ASSIGNMENT';
                        onActionTap = widget.onOpenCohort;
                      } else if (itemId == 'unassigned_advisers' ||
                          targetSectionKey == 'student_teams') {
                        actionIcon = Icons.person_add_alt_1_rounded;
                        iconColor = const Color(0xFF4F46E5);
                        iconBg = const Color(0xFFE0E7FF);
                        badgeBg = const Color(0xFFEEF2FF);
                        badgeBorder = const Color(0xFFC7D2FE);
                        badgeTextColor = const Color(0xFF4338CA);
                        categoryLabel = 'TEAM MANAGEMENT';
                        onActionTap = widget.onOpenStudentTeams;
                      } else if (itemId == 'unassigned_students' ||
                          targetSectionKey == 'cohort') {
                        actionIcon = Icons.group_add_rounded;
                        iconColor = const Color(0xFF7C3AED);
                        iconBg = const Color(0xFFEDE3FF);
                        badgeBg = const Color(0xFFF5F3FF);
                        badgeBorder = const Color(0xFFDDD6FE);
                        badgeTextColor = const Color(0xFF6D28D9);
                        categoryLabel = 'COHORT ASSIGNMENT';
                        onActionTap = widget.onOpenCohort;
                      } else if (itemId == 'pending_grades' ||
                          targetSectionKey == 'grade_center') {
                        actionIcon = Icons.grading_rounded;
                        iconColor = const Color(0xFFD97706);
                        iconBg = const Color(0xFFFEF3C7);
                        badgeBg = const Color(0xFFFFFBEB);
                        badgeBorder = const Color(0xFFFDE68A);
                        badgeTextColor = const Color(0xFFB45309);
                        categoryLabel = 'GRADE REVIEW';
                        onActionTap = widget.onOpenGradeCenter;
                      } else {
                        actionIcon = Icons.tune_rounded;
                        iconColor = const Color(0xFFDC2626);
                        iconBg = const Color(0xFFFEE2E2);
                        badgeBg = const Color(0xFFFEF2F2);
                        badgeBorder = const Color(0xFFFECACA);
                        badgeTextColor = const Color(0xFFB91C1C);
                        categoryLabel = 'SETUP REQUIRED';
                        onActionTap = widget.onOpenStudentTeams;
                      }

                      return InkWell(
                        onTap: onActionTap,
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
                                onPressed: onActionTap,
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

  Widget _buildAuditLogsView(
    List<Map<String, dynamic>> logs,
    List alerts,
  ) {
    if (logs.isEmpty && alerts.isEmpty) {
      return const Center(
        child: Text(
          'No recent activity recorded for this cohort.',
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
          onTap: widget.onOpenAuditCompliance,
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

  List<Map<String, dynamic>> _upcomingDefensesFrom(Map<String, dynamic> overview) {
    final raw = overview['upcoming_defenses_list'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  List<Map<String, dynamic>> _actionItemsFrom(Map<String, dynamic> overview) {
    final raw = overview['action_items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  List<Map<String, dynamic>> _recentActivityFrom(Map<String, dynamic> overview) {
    final raw = overview['recent_activity'];
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
      return '0';
    }
    return value.toString();
  }
}
