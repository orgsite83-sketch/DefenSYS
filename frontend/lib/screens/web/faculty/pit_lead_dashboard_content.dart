import 'package:flutter/material.dart';

import '../admin/widgets/defensys_admin_shell.dart';
import 'pit_repository_assistant_card.dart';

class PitLeadDashboardContent extends StatelessWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final VoidCallback onOpenStudentTeams;
  final VoidCallback onOpenScheduler;
  final VoidCallback onOpenGradeCenter;
  final VoidCallback onOpenRubrics;
  final VoidCallback onOpenCohort;

  const PitLeadDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenStudentTeams,
    required this.onOpenScheduler,
    required this.onOpenGradeCenter,
    required this.onOpenRubrics,
    required this.onOpenCohort,
  });

  static const _line = Color(0xFFF3F4F6);
  static const _ink = DefensysUi.textDark;
  static const _maroon = DefensysUi.primaryMaroon;

  @override
  Widget build(BuildContext context) {
    final pitYear = data?['pit_lead_year']?.toString() ?? 'Unscoped';
    final overview =
        (data?['pit_lead_overview'] as Map?)?.cast<String, dynamic>();
    final stats = (overview?['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final alerts = (overview?['alerts'] as List?) ?? [];
    final recentTeams =
        (overview?['recent_pit_teams'] as List?) ??
        (data?['pit_teams'] as List?) ??
        [];
    final cohortPreview =
        (overview?['cohort_preview'] as List?)?.cast<Map<String, dynamic>>() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefensysPageHeader(
          icon: Icons.workspace_premium_outlined,
          title: 'Welcome, $facultyName',
          subtitle: 'PIT Lead workspace · $pitYear',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _metricCard(
                value: _stat(stats, 'students_in_cohort'),
                label: 'Students in Cohort',
                icon: Icons.groups_rounded,
                iconColor: const Color(0xFF7C3AED),
                iconBackground: const Color(0xFFEDE3FF),
                onTap: onOpenCohort,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: _stat(stats, 'pit_teams'),
                label: 'PIT Teams',
                icon: Icons.groups_3_rounded,
                iconColor: const Color(0xFF047857),
                iconBackground: const Color(0xFFCFFAE7),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: _stat(stats, 'scheduled_events'),
                label: 'Scheduled PIT Events',
                icon: Icons.event_available_rounded,
                iconColor: const Color(0xFF92400E),
                iconBackground: const Color(0xFFFFEDB8),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: _stat(stats, 'pending_grades'),
                label: 'Pending Grades',
                icon: Icons.fact_check_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBackground: const Color(0xFFDCEBFF),
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
            Expanded(child: _pitTeamsCard(recentTeams)),
          ],
        ),
        const SizedBox(height: 20),
        const PitRepositoryAssistantCard(),
        const SizedBox(height: 20),
        _cohortPreviewCard(cohortPreview, pitYear),
        const SizedBox(height: 20),
        _alertsCard(alerts),
      ],
    );
  }

  String _stat(Map<String, dynamic> stats, String key) {
    final value = stats[key];
    if (value == null) return '0';
    return value.toString();
  }

  Widget _cohortPreviewCard(List<Map<String, dynamic>> cohortPreview, String pitYear) {
    return _dashboardCard(
      height: cohortPreview.isEmpty ? 160 : 280,
      title: 'Cohort roster',
      actionLabel: 'View all',
      onActionTap: onOpenCohort,
      child: cohortPreview.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No students with academic records for $pitYear this semester. '
                  'Ask an administrator to import students or set academic records.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF9AA1B4), fontSize: 14),
                ),
              ),
            )
          : Column(
              children: [
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _line)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Name',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Student ID',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Team status',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    itemCount: cohortPreview.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 14, color: _line),
                    itemBuilder: (context, index) {
                      final student = cohortPreview[index];
                      final onTeam = student['team_status'] == 'on_team';
                      final statusLabel = onTeam
                          ? student['team_name']?.toString() ?? 'On team'
                          : 'Unassigned';

                      return Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              student['name']?.toString() ?? '-',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              student['username']?.toString() ?? '-',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: onTeam
                                    ? const Color(0xFF047857)
                                    : const Color(0xFF92400E),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
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
    final card = Container(
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

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }

  Widget _quickActionsCard() {
    return _dashboardCard(
      height: 320,
      title: 'Quick Actions',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 20, 28, 18),
        child: Column(
          children: [
            _quickAction(
              icon: Icons.groups_outlined,
              iconColor: const Color(0xFF7C3AED),
              iconBackground: const Color(0xFFEDE3FF),
              title: 'Manage PIT Teams',
              subtitle: 'Create or update teams for your year level',
              onTap: onOpenStudentTeams,
            ),
            _quickAction(
              icon: Icons.calendar_month_outlined,
              iconColor: const Color(0xFF047857),
              iconBackground: const Color(0xFFCFFAE7),
              title: 'Schedule PIT Event',
              subtitle: 'Plan presentations in Defense Scheduler',
              onTap: onOpenScheduler,
            ),
            _quickAction(
              icon: Icons.grading_outlined,
              iconColor: const Color(0xFF2563EB),
              iconBackground: const Color(0xFFDCEBFF),
              title: 'Grade Center',
              subtitle: 'Review and publish team grades',
              onTap: onOpenGradeCenter,
            ),
            _quickAction(
              icon: Icons.rule_outlined,
              iconColor: const Color(0xFF92400E),
              iconBackground: const Color(0xFFFFEDB8),
              title: 'Rubric Engine',
              subtitle: 'Configure grading rubrics',
              onTap: onOpenRubrics,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pitTeamsCard(List recentTeams) {
    return _dashboardCard(
      height: 320,
      title: 'PIT Teams Snapshot',
      actionLabel: 'View All',
      onActionTap: onOpenStudentTeams,
      child: recentTeams.isEmpty
          ? const Center(
              child: Text(
                'No PIT teams yet for this year level.',
                style: TextStyle(color: Color(0xFF9AA1B4), fontSize: 14),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              itemCount: recentTeams.length,
              separatorBuilder: (_, __) => const Divider(height: 16, color: _line),
              itemBuilder: (context, index) {
                final team = (recentTeams[index] as Map?)?.cast<String, dynamic>() ?? {};
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team['name']?.toString() ?? 'Team',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            team['projectTitle']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      team['status']?.toString() ?? '',
                      style: const TextStyle(
                        color: Color(0xFF047857),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _alertsCard(List alerts) {
    return _dashboardCard(
      height: alerts.isEmpty ? 120 : 168,
      title: 'Alerts',
      child: alerts.isEmpty
          ? const Center(
              child: Text(
                'No alerts for your PIT cohort.',
                style: TextStyle(color: Color(0xFF9AA1B4), fontSize: 14),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final alert = (alerts[index] as Map?)?.cast<String, dynamic>() ?? {};
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
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
