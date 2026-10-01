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
    final primary = isDark
        ? DefensysTokens.textPrimaryDark
        : DefensysUi.textDark;
    final missingAdviser = isPitContext
        ? 0
        : state.teams.where((team) {
            final adviser = team['adviser_name'] ?? team['adviser'];
            return adviser == null || adviser.toString().trim().isEmpty;
          }).length;
    const statusOrder = [
      'locked',
      'ready',
      'scheduled',
      'grading',
      'passed',
      'failed',
      'archived',
    ];
    final stageCounts = <String?, int>{};
    if (!isPitContext) {
      for (final team in state.teams) {
        final status = teamCurrentStageStatus(team);
        final key = statusOrder.contains(status) ? status : null;
        stageCounts[key] = (stageCounts[key] ?? 0) + 1;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 18,
            runSpacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.groups_2_rounded,
                    size: 20,
                    color: DefensysUi.primaryMaroon,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${state.teams.length}',
                    style: TextStyle(
                      color: primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'teams shown',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (!isPitContext)
                ...[
                  ...statusOrder,
                  null,
                ].where((status) => (stageCounts[status] ?? 0) > 0).map((
                  status,
                ) {
                  final color = _stageStatusColor(status, isDark);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.14 : 0.07),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '${stageCounts[status]} ${_stageStatusLabel(status).toLowerCase()}',
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }),
              if (missingAdviser > 0)
                Text(
                  '$missingAdviser ${missingAdviser == 1 ? 'team needs' : 'teams need'} an adviser',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFFCD34D)
                        : const Color(0xFF92400E),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (!isPitContext) ...[
            const SizedBox(height: 8),
            Text(
              'Progress is for each team’s current stage. Passing one stage does not finish the whole project.',
              style: TextStyle(color: muted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}
