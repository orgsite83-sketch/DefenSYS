import 'package:flutter/material.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';

String? teamCurrentStageStatus(Map<String, dynamic> team) {
  final context = team['defense_context'];
  if (context is! Map) return null;
  final status = context['stage_status']?.toString().trim();
  return status == null || status.isEmpty ? null : status;
}

String _stageStatusLabel(String? status) => switch (status) {
  'locked' => 'Preparing',
  'ready' => 'Ready to schedule',
  'scheduled' => 'Scheduled',
  'grading' => 'Grading',
  'passed' => 'Stage passed',
  'failed' => 'Needs follow-up',
  'archived' => 'Stage archived',
  _ => 'No stage update',
};

Color _stageStatusColor(String? status, bool isDark) => switch (status) {
  'ready' ||
  'scheduled' => isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
  'passed' ||
  'archived' => isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
  'failed' => isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
  'grading' => isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
  _ => isDark ? DefensysTokens.textSecondaryDark : DefensysUi.steelGrey,
};

Widget currentStageBadge(BuildContext context, Map<String, dynamic> team) {
  final status = teamCurrentStageStatus(team);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final color = _stageStatusColor(status, isDark);
  return Tooltip(
    message: status == null
        ? 'No progress update is recorded for this stage.'
        : 'Progress for this team’s current defense stage.',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        _stageStatusLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class StudentTeamsSummaryCards extends StatelessWidget {
  const StudentTeamsSummaryCards({
    super.key,
    required this.state,
    required this.isPitContext,
  });

  final StudentTeamsState state;
  final bool isPitContext;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? DefensysTokens.textSecondaryDark
        : DefensysUi.steelGrey;
    final missingAdviser = state.teams.where((team) {
      final adviser = team['adviser_name'] ?? team['adviser'];
      return adviser == null || adviser.toString().trim().isEmpty;
    }).length;
    final ready = state.teams
        .where((team) => teamCurrentStageStatus(team) == 'ready')
        .length;
    final scheduled = state.teams
        .where((team) => teamCurrentStageStatus(team) == 'scheduled')
        .length;
    final noStageUpdate = state.teams
        .where((team) => teamCurrentStageStatus(team) == null)
        .length;
    final cards = [
      _TeamSummaryCard(
        id: 'teams',
        label: 'Teams',
        count: state.teams.length,
        helper: 'Current list',
        icon: Icons.groups_2_rounded,
        accent: DefensysUi.primaryMaroon,
      ),
      if (!isPitContext) ...[
        _TeamSummaryCard(
          id: 'needs-adviser',
          label: 'Needs adviser',
          count: missingAdviser,
          helper: 'No adviser assigned',
          icon: Icons.person_add_alt_1_rounded,
          accent: const Color(0xFFB45309),
        ),
        _TeamSummaryCard(
          id: 'ready',
          label: 'Ready to schedule',
          count: ready,
          helper: 'Current stage',
          icon: Icons.event_available_rounded,
          accent: const Color(0xFF2563EB),
        ),
        _TeamSummaryCard(
          id: 'scheduled',
          label: 'Scheduled',
          count: scheduled,
          helper: 'Current stage',
          icon: Icons.calendar_month_rounded,
          accent: const Color(0xFF047857),
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = isPitContext
            ? 1
            : constraints.maxWidth >= 880
            ? 4
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards)
                  SizedBox(width: cardWidth, child: card),
              ],
            ),
            if (!isPitContext && noStageUpdate > 0) ...[
              const SizedBox(height: 9),
              Text(
                '$noStageUpdate ${noStageUpdate == 1 ? 'team has' : 'teams have'} no current-stage update yet.',
                style: TextStyle(color: muted, fontSize: 11.5),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TeamSummaryCard extends StatelessWidget {
  const _TeamSummaryCard({
    required this.id,
    required this.label,
    required this.count,
    required this.helper,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String label;
  final int count;
  final String helper;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? DefensysTokens.textSecondaryDark
        : DefensysUi.steelGrey;
    return Container(
      key: Key('student-teams-summary-$id'),
      height: 102,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.18 : 0.09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 21, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$count',
                  style: TextStyle(
                    color: isDark
                        ? DefensysTokens.textPrimaryDark
                        : DefensysUi.textDark,
                    fontSize: 23,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  helper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
