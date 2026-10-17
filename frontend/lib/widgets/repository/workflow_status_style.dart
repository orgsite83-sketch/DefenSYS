import 'package:flutter/material.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/theme/defensys_tokens.dart';

/// The only five color families used by team workflow badges.
class WorkflowStatusStyle {
  final Color foreground;
  final Color background;
  final Color border;

  const WorkflowStatusStyle(this.foreground, this.background, this.border);

  static WorkflowStatusStyle of(BuildContext context, WorkflowStatusTone tone) {
    if (DefensysTokens.isDark(context)) {
      final foreground = switch (tone) {
        WorkflowStatusTone.neutral => DefensysTokens.mistTextSecondary,
        WorkflowStatusTone.attention => const Color(0xFFFCD34D),
        WorkflowStatusTone.destructive => const Color(0xFFFCA5A5),
        WorkflowStatusTone.active => const Color(0xFF93C5FD),
        WorkflowStatusTone.success => const Color(0xFF6EE7B7),
      };
      return WorkflowStatusStyle(
        foreground,
        foreground.withValues(alpha: 0.10),
        foreground.withValues(alpha: 0.30),
      );
    }
    return switch (tone) {
      WorkflowStatusTone.neutral => const WorkflowStatusStyle(
        DefensysTokens.textSecondary,
        DefensysTokens.neutralBg,
        DefensysTokens.neutralBorder,
      ),
      WorkflowStatusTone.attention => const WorkflowStatusStyle(
        DefensysTokens.warningText,
        DefensysTokens.warningBg,
        DefensysTokens.warningBorder,
      ),
      WorkflowStatusTone.destructive => const WorkflowStatusStyle(
        DefensysTokens.dangerText,
        DefensysTokens.dangerBg,
        DefensysTokens.dangerBorder,
      ),
      WorkflowStatusTone.active => const WorkflowStatusStyle(
        DefensysTokens.infoText,
        DefensysTokens.infoBg,
        DefensysTokens.infoBorder,
      ),
      WorkflowStatusTone.success => const WorkflowStatusStyle(
        DefensysTokens.successText,
        DefensysTokens.successBg,
        DefensysTokens.successBorder,
      ),
    };
  }

  static IconData iconFor(TeamWorkflowStatus status) => switch (status.code) {
    'not_configured' => Icons.settings_outlined,
    'awaiting_files' => Icons.upload_file_outlined,
    'needs_review' => Icons.rate_review_outlined,
    'changes_requested' || 'revisions_pending' => Icons.edit_note_outlined,
    'awaiting_endorsement' => Icons.verified_outlined,
    'ready_to_schedule' => Icons.event_available_outlined,
    'scheduled' => Icons.event_outlined,
    'evaluating' => Icons.campaign_outlined,
    'completed' || 'passed' => Icons.check_circle_outline,
    'failed' || 'project_rejected' => Icons.cancel_outlined,
    'cancelled' || 'archived' => Icons.archive_outlined,
    _ => Icons.hourglass_top_rounded,
  };
}

/// Shared primary status for dashboards, team cards, dossiers and matrices.
class TeamWorkflowBadge extends StatelessWidget {
  const TeamWorkflowBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final TeamWorkflowStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = WorkflowStatusStyle.of(context, status.tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(compact ? 4 : 20),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            WorkflowStatusStyle.iconFor(status),
            size: 12,
            color: style.foreground,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                color: style.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
