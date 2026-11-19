import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// Semester lifecycle is separate from enabled program and evaluation settings.
class SemesterStatusBadge extends StatelessWidget {
  const SemesterStatusBadge({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      return Text(
        'Inactive',
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          color: DefensysTokens.textSecondaryOf(context),
          fontSize: 12,
        ),
      );
    }
    final dark = DefensysTokens.isDark(context);
    final background = dark
        ? DefensysTokens.success.withValues(alpha: .12)
        : DefensysTokens.successBg;
    final foreground = dark
        ? const Color(0xFF6EE7B7)
        : DefensysTokens.successText;
    return DefensysShadcnScope(
      child: ShadBadge.secondary(
        backgroundColor: background,
        hoverBackgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 5, color: foreground),
            const SizedBox(width: 5),
            Text(
              'Active',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
