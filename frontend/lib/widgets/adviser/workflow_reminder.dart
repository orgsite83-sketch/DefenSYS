import 'package:flutter/material.dart';

import '../../models/adviser_workflow.dart';
import '../../theme/defensys_tokens.dart';

/// Compact, readable guidance that shares the deliverables' semantic colors.
class AdviserWorkflowReminder extends StatelessWidget {
  const AdviserWorkflowReminder({
    super.key,
    required this.title,
    required this.detail,
    required this.tone,
    this.actionLabel,
    this.onAction,
    this.progress,
    this.progressLabel,
    this.onLightSurface = false,
  });

  final String title, detail;
  final AdviserWorkflowTone tone;
  final String? actionLabel, progressLabel;
  final VoidCallback? onAction;
  final double? progress;
  final bool onLightSurface;

  static Color colorOf(
    BuildContext context,
    AdviserWorkflowTone tone, {
    bool onLightSurface = false,
  }) => switch (tone) {
    AdviserWorkflowTone.success =>
      DefensysTokens.isDark(context) && !onLightSurface
          ? const Color(0xFF6EE7B7)
          : DefensysTokens.successText,
    AdviserWorkflowTone.waiting =>
      onLightSurface ? DefensysTokens.darkGold : DefensysTokens.goldOf(context),
    AdviserWorkflowTone.neutral =>
      onLightSurface
          ? DefensysTokens.textSecondary
          : DefensysTokens.textSecondaryOf(context),
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context, tone, onLightSurface: onLightSurface);
    final icon = switch (tone) {
      AdviserWorkflowTone.success => Icons.check_circle_outline_rounded,
      AdviserWorkflowTone.waiting => Icons.hourglass_top_rounded,
      AdviserWorkflowTone.neutral => Icons.info_outline_rounded,
    };
    final copy = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(
                  color: onLightSurface
                      ? DefensysTokens.textSecondary
                      : DefensysTokens.textSecondaryOf(context),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final action = onAction != null && actionLabel != null
        ? FilledButton.icon(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: DefensysTokens.isDark(context) && !onLightSurface
                  ? DefensysTokens.mistBackground
                  : Colors.white,
            ),
            icon: const Icon(Icons.draw_outlined, size: 16),
            label: Text(actionLabel!),
          )
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (action == null) return copy;
              if (constraints.maxWidth < 600) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [copy, const SizedBox(height: 12), action],
                );
              }
              return Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 18),
                  action,
                ],
              );
            },
          ),
          if (progress != null && progressLabel != null) ...[
            const SizedBox(height: 12),
            Text(
              progressLabel!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
