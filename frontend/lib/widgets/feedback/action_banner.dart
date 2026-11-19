import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

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
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 12.5,
                  color: color,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final action = DefensysShadcnScope(
      child: ShadButton.outline(
        onPressed: onAction,
        height: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Flexible(child: Text(actionLabel, textAlign: TextAlign.center)),
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
