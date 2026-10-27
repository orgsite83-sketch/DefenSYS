import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';

/// Keeps a proposal and its supporting deliverables in one visual scope.
class ConceptReviewSection extends StatelessWidget {
  const ConceptReviewSection({
    super.key,
    required this.titleReview,
    required this.deliverables,
    this.onReviewFiles,
  });

  final Widget titleReview;
  final Widget deliverables;
  final VoidCallback? onReviewFiles;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titleReview,
        if (onReviewFiles == null)
          Divider(height: 24, color: DefensysTokens.borderOf(context))
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Divider(color: DefensysTokens.borderOf(context)),
                ),
                const SizedBox(width: 8),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  height: 32,
                  onPressed: onReviewFiles,
                  trailing: const Icon(Icons.arrow_forward, size: 14),
                  child: const Text('Review files'),
                ),
              ],
            ),
          ),
        deliverables,
      ],
    ),
  );
}

/// Keeps title status in the trailing corner without tinting the proposal.
class TitleReviewHeader extends StatelessWidget {
  const TitleReviewHeader({
    super.key,
    required this.label,
    required this.statusLabel,
    required this.accepted,
  });

  final String label;
  final String statusLabel;
  final bool accepted;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Align(
          alignment: Alignment.centerRight,
          child: TitleReviewStatus(label: statusLabel, accepted: accepted),
        ),
      ),
    ],
  );
}

/// Acceptance uses a compact green badge; pending states stay muted.
class TitleReviewStatus extends StatelessWidget {
  const TitleReviewStatus({
    super.key,
    required this.label,
    required this.accepted,
  });

  final String label;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final dark = DefensysTokens.isDark(context);
    final color = accepted
        ? dark
              ? DefensysTokens.success
              : DefensysTokens.successText
        : DefensysTokens.textSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: accepted
          ? BoxDecoration(
              color: dark
                  ? DefensysTokens.success.withValues(alpha: 0.12)
                  : DefensysTokens.successBg,
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            accepted ? Icons.check_circle_outline : Icons.info_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
