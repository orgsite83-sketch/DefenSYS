import 'package:flutter/material.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../theme/defensys_tokens.dart';

/// Prioritizes completion consequences over evaluation readiness.
class GradeGroupCompletionSummary extends StatelessWidget {
  const GradeGroupCompletionSummary({
    super.key,
    required this.readiness,
    this.isPit = false,
  });

  final GradeGroupCompletionReadiness readiness;
  final bool isPit;

  String _teamCount(int count) => '$count team${count == 1 ? '' : 's'}';

  String _teamNames(List<Map<String, dynamic>> teams) =>
      teams.map((team) => team['team_name']?.toString() ?? 'Team').join(', ');

  @override
  Widget build(BuildContext context) {
    final target = isPit ? 'event' : 'stage';
    final redefense = readiness.redefenseTeams;
    final revisions = readiness.revisionTeams;
    final failing = readiness.failingTeams;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (redefense.isNotEmpty) ...[
          _CompletionOutcomeNotice(
            key: const ValueKey('redefense-completion-warning'),
            title:
                '${_teamCount(redefense.length)} still require re-defense.',
            message:
                'Resolve their panel grades and verdict in a new attempt. '
                'This $target cannot be completed while re-defense is pending. '
                'Adviser and peer grades are retained.',
            teamNames: 'For Re-defense: ${_teamNames(redefense)}',
          ),
          const SizedBox(height: 12),
        ],
        if (failing.isNotEmpty) ...[
          _CompletionOutcomeNotice(
            key: const ValueKey('failing-completion-warning'),
            title:
                '${_teamCount(failing.length)} '
                '${failing.length == 1 ? 'has' : 'have'} failing grades.',
            message: 'These teams will not qualify for project archiving.',
            teamNames: _teamNames(failing),
          ),
          const SizedBox(height: 12),
        ],
        if (revisions.isNotEmpty) ...[
          _CompletionOutcomeNotice(
            key: const ValueKey('revision-completion-notice'),
            warning: true,
            title: '${_teamCount(revisions.length)} approved with revisions.',
            message:
                'Verify and clear their required corrections first. '
                'Progression, stage completion, and project archiving remain '
                'blocked until clearance is recorded.',
            teamNames: _teamNames(revisions),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          key: const ValueKey('grading-completion-summary'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceHigherOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 20,
                color: DefensysTokens.textSecondaryOf(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${readiness.readyTeams} of ${readiness.totalTeams} teams '
                  'have all required grades.',
                  style: DefensysTokens.dialogContent.copyWith(
                    fontSize: 13,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompletionOutcomeNotice extends StatelessWidget {
  const _CompletionOutcomeNotice({
    super.key,
    required this.title,
    required this.message,
    required this.teamNames,
    this.warning = false,
  });

  final String title, message, teamNames;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final dark = DefensysTokens.isDark(context);
    final accent = warning
        ? (dark ? DefensysTokens.warningBorder : DefensysTokens.warningText)
        : (dark ? DefensysTokens.dangerBorder : DefensysTokens.dangerText);
    final background = warning
        ? DefensysTokens.warningBg
        : DefensysTokens.dangerBg;
    final border = warning
        ? DefensysTokens.warningBorder
        : DefensysTokens.dangerBorder;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: dark ? accent.withValues(alpha: 0.1) : background,
          border: Border.all(
            color: dark ? accent.withValues(alpha: 0.5) : border,
          ),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning
                  ? Icons.assignment_late_outlined
                  : Icons.warning_amber_rounded,
              size: 24,
              color: accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DefensysTokens.dialogContent.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: DefensysTokens.dialogContent.copyWith(
                      fontSize: 13,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    teamNames,
                    style: DefensysTokens.dialogContent.copyWith(
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
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
}

