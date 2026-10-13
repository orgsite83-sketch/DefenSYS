import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

/// A reminder with an explicit action supplied by the screen that owns it.
class DefensysActionBanner extends StatelessWidget {
  const DefensysActionBanner({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    this.isBlocking = false,
  });

  final String title, description, actionLabel;
  final VoidCallback onAction;
  final bool isBlocking;

  @override
  Widget build(BuildContext context) {
    final dark = DefensysTokens.isDark(context);
    final color = isBlocking
        ? (dark ? const Color(0xFFFCA5A5) : DefensysTokens.dangerText)
        : DefensysTokens.goldOf(context);
    final copy = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isBlocking ? Icons.block_rounded : Icons.info_outline_rounded,
          color: color,
          size: 22,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(fontSize: 12.5, color: color, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
    final action = OutlinedButton.icon(
      onPressed: onAction,
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: Text(actionLabel),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark
            ? color.withValues(alpha: 0.08)
            : isBlocking
            ? DefensysTokens.dangerBg
            : DefensysTokens.warningBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dark
              ? color.withValues(alpha: 0.3)
              : isBlocking
              ? DefensysTokens.dangerBorder
              : DefensysTokens.warningBorder,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 12), action],
            );
          }
          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 20),
              action,
            ],
          );
        },
      ),
    );
  }
}
