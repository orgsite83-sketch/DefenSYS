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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(color: borderColor, width: 1.0),
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
                color: textColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              color: textColor,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
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
