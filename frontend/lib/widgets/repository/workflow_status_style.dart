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
