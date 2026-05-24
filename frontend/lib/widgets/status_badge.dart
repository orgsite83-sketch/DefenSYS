import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

/// Pill status label for tables and detail views.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final Color borderColor;
  final bool showDot;

  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.textColor,
    required this.borderColor,
    this.showDot = false,
  });

  const StatusBadge.success({
    super.key,
    required this.label,
    this.showDot = true,
  })  : background = DefensysTokens.successBg,
        textColor = DefensysTokens.successText,
        borderColor = DefensysTokens.successBorder;

  const StatusBadge.inactive({
    super.key,
    required this.label,
    this.showDot = false,
  })  : background = DefensysTokens.neutralBg,
        textColor = DefensysTokens.steelGrey,
        borderColor = DefensysTokens.neutralBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: DefensysTokens.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Backward-compatible alias for admin screens.
class DefensysStatusBadge extends StatusBadge {
  const DefensysStatusBadge({
    super.key,
    required super.label,
    required super.background,
    required super.textColor,
    required super.borderColor,
    super.showDot = false,
  });

  const DefensysStatusBadge.success({
    super.key,
    required super.label,
    super.showDot = true,
  }) : super.success();

  const DefensysStatusBadge.inactive({
    super.key,
    required super.label,
    super.showDot = false,
  }) : super.inactive();
}
