import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

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

  const StatusBadge.warning({
    super.key,
    required this.label,
    this.showDot = true,
  })  : background = DefensysTokens.warningBg,
        textColor = DefensysTokens.warningText,
        borderColor = DefensysTokens.warningBorder;

  const StatusBadge.danger({
    super.key,
    required this.label,
    this.showDot = true,
  })  : background = DefensysTokens.dangerBg,
        textColor = DefensysTokens.dangerText,
        borderColor = DefensysTokens.dangerBorder;

  const StatusBadge.info({
    super.key,
    required this.label,
    this.showDot = true,
  })  : background = DefensysTokens.infoBg,
        textColor = DefensysTokens.infoText,
        borderColor = DefensysTokens.infoBorder;

  const StatusBadge.overridden({
    super.key,
    required this.label,
    this.showDot = true,
  })  : background = DefensysTokens.overriddenBg,
        textColor = DefensysTokens.overriddenText,
        borderColor = DefensysTokens.overriddenBorder;

  const StatusBadge.revision({
    super.key,
    required this.label,
    this.showDot = true,
  })  : background = DefensysTokens.revisionBg,
        textColor = DefensysTokens.revisionText,
        borderColor = DefensysTokens.revisionBorder;

  const StatusBadge.archived({
    super.key,
    required this.label,
    this.showDot = false,
  })  : background = DefensysTokens.archivedBg,
        textColor = DefensysTokens.archivedText,
        borderColor = DefensysTokens.archivedBorder;

  const StatusBadge.inactive({
    super.key,
    required this.label,
    this.showDot = false,
  })  : background = DefensysTokens.neutralBg,
        textColor = DefensysTokens.steelGrey,
        borderColor = DefensysTokens.neutralBorder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // In dark mode, calculate refined dark tones for badges
    Color effectiveBg = background;
    Color effectiveFg = textColor;
    Color effectiveBorder = borderColor;

    if (isDark) {
      if (background == DefensysTokens.successBg) {
        effectiveBg = const Color(0xFF064E3B).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFF34D399);
        effectiveBorder = const Color(0xFF059669).withValues(alpha: 0.5);
      } else if (background == DefensysTokens.warningBg) {
        effectiveBg = const Color(0xFF451A03).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFFFBBF24);
        effectiveBorder = const Color(0xFFB45309).withValues(alpha: 0.5);
      } else if (background == DefensysTokens.dangerBg) {
        effectiveBg = const Color(0xFF450A0A).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFFF87171);
        effectiveBorder = const Color(0xFF991B1B).withValues(alpha: 0.5);
      } else if (background == DefensysTokens.infoBg) {
        effectiveBg = const Color(0xFF172554).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFF60A5FA);
        effectiveBorder = const Color(0xFF1D4ED8).withValues(alpha: 0.5);
      } else if (background == DefensysTokens.neutralBg ||
          background == DefensysTokens.archivedBg) {
        effectiveBg = const Color(0xFF27272A);
        effectiveFg = const Color(0xFFA1A1AA);
        effectiveBorder = const Color(0xFF3F3F46);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(color: effectiveBorder, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: effectiveFg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                color: effectiveFg,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
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

  const DefensysStatusBadge.warning({
    super.key,
    required super.label,
    super.showDot = true,
  }) : super.warning();

  const DefensysStatusBadge.danger({
    super.key,
    required super.label,
    super.showDot = true,
  }) : super.danger();

  const DefensysStatusBadge.info({
    super.key,
    required super.label,
    super.showDot = true,
  }) : super.info();

  const DefensysStatusBadge.overridden({
    super.key,
    required super.label,
    super.showDot = true,
  }) : super.overridden();

  const DefensysStatusBadge.inactive({
    super.key,
    required super.label,
    super.showDot = false,
  }) : super.inactive();
}
