import 'package:flutter/material.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';

String? teamCurrentStageStatus(Map<String, dynamic> team) {
  final context = team['defense_context'];
  if (context is! Map) return null;
  final workflow = context['concept_workflow'];
  if (workflow is Map && workflow['enabled'] == true) {
    return workflow['status']?.toString();
  }
  final status = context['stage_status']?.toString().trim();
  return status == null || status.isEmpty ? null : status;
}

String _stageStatusLabel(String? status) => switch (status) {
  'completed' => 'Completed',
  'awaiting_stage_setup' => 'Awaiting stage setup',
  'setup_pending' => 'Setup pending',
  'preparing' => 'Preparing',
  'needs_review' => 'Needs review',
  'open' => 'Term closed',
  'locked' => 'Preparing',
  'ready' => 'Ready to schedule',
  'scheduled' => 'Scheduled',
  'grading' => 'Grading',
  'passed' => 'Completed',
  'replacement_concepts_needed' => 'Replacement concepts needed',
  'concepts_needed' => 'Concepts needed',
  'concept_review_pending' => 'Adviser review pending',
  'concept_endorsement_pending' => 'Awaiting endorsement',
  'module_confirmation_pending' => 'Confirm module names',
  'shared_clearance_pending' => 'Team endorsed · Shared papers pending',
  'shared_acknowledgment_pending' => 'Team endorsed · Review shared systems',
  'ready_to_schedule_redefense' => 'Ready for re-defense scheduling',
  'ready_to_schedule' => 'Ready to schedule',
  'approved' => 'Concept approved',
  'approved_with_revisions' => 'Revisions required',
  'project_rejected' => 'Project rejected',
  'failed' => 'Failed',
  'archived' => 'Stage archived',
  _ => 'No stage update',
};

Color _stageStatusColor(String? status, bool isDark) => switch (status) {
  'ready' ||
  'ready_to_schedule' ||
  'ready_to_schedule_redefense' ||
  'scheduled' => isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
  'passed' ||
  'approved' ||
  'archived' => isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
  'project_rejected' ||
  'failed' => isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
  'replacement_concepts_needed' ||
  'concepts_needed' ||
  'concept_review_pending' ||
  'concept_endorsement_pending' ||
  'module_confirmation_pending' ||
  'shared_acknowledgment_pending' ||
  'approved_with_revisions' ||
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
        : ((team['defense_context'] as Map? ?? {})['concept_workflow']
                          as Map? ??
                      {})['next_step']
                  ?.toString() ??
              'Progress for this team’s current defense stage.',
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
    final missingFaculty = state.teams.where((team) {
      final faculty = isPitContext
          ? team['instructor_name']
          : team['adviser_name'] ?? team['adviser'];
      return faculty == null || faculty.toString().trim().isEmpty;
    }).map((t) => t['id'] ?? t)
        .toSet()
        .length;
    final eventName = state.eventName?.trim() ?? '';
    final historical =
        state.teams.isNotEmpty &&
        state.teams.every((t) => t['is_editable'] == false);
    final hasSchedulingContext = !historical &&
        (isPitContext
            ? eventName.isNotEmpty
            : state.teams.any(
                (t) => teamCurrentStageStatus(t) != 'awaiting_stage_setup',
              ));
    String? schedulingStatus(Map<String, dynamic> team) {
      if (!isPitContext) return teamCurrentStageStatus(team);
      final context = team['defense_context'];
      if (context is! Map ||
          context['event_label']?.toString().trim().toLowerCase() !=
              eventName.toLowerCase()) {
        return null;
      }
      return context['scheduling_status']?.toString();
    }

    final ready = state.teams
        .where(
          (team) => const {
            'ready',
            'ready_to_schedule',
            'ready_to_schedule_redefense',
          }.contains(schedulingStatus(team)),
        )
        .length;
    final scheduled = state.teams
        .where((team) => schedulingStatus(team) == 'scheduled')
        .length;
    final noStageUpdate = state.teams
        .where((team) => teamCurrentStageStatus(team) == null)
        .length;
    final cards = [
      _TeamSummaryCard(
        id: 'teams',
        label: 'Teams',
        count: state.teams.map((t) => t['id'] ?? t).toSet().length,
        helper: historical ? 'Selected intake': 'Current list',
        icon: Icons.groups_2_rounded,
        accent: DefensysUi.primaryMaroon,
      ),
      _TeamSummaryCard(
        id: isPitContext ? 'needs-instructor' : 'needs-adviser',
        label: isPitContext ? 'Needs instructor' : 'Needs adviser',
        count: missingFaculty,
        helper: isPitContext ? 'No section instructor' : 'No adviser assigned',
        icon: Icons.person_add_alt_1_rounded,
        accent: const Color(0xFFB45309),
      ),
      _TeamSummaryCard(
        id: 'ready',
        label: 'Ready to schedule',
        count: hasSchedulingContext ? ready : null,
        helper: isPitContext
            ? (hasSchedulingContext
                  ? 'Selected PIT event'
                  : 'Select a PIT event')
            : 'Current stage',
        icon: Icons.event_available_rounded,
        accent: const Color(0xFF2563EB),
      ),
      _TeamSummaryCard(
        id: 'scheduled',
        label: 'Scheduled',
        count: hasSchedulingContext ? scheduled : null,
        helper: isPitContext
            ? (hasSchedulingContext
                  ? 'Selected PIT event'
                  : 'Select a PIT event')
            : 'Current stage',
        icon: Icons.calendar_month_rounded,
        accent: const Color(0xFF047857),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 880
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
  final int? count;
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
                  count?.toString() ?? '—',
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
