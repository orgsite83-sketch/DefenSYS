import 'package:flutter/material.dart';

import 'defensys_tokens.dart';

/// Shared action hierarchy for page toolbars. Emphasis changes, sizing does not.
/// Use with native Material buttons to retain keyboard and screen-reader support.
class DefensysButtonStyles {
  DefensysButtonStyles._();

  static ButtonStyle primary(BuildContext context) =>
      _style(context, filled: true);

  static ButtonStyle secondary(BuildContext context) =>
      _style(context, outlined: true);

  static ButtonStyle tertiary(BuildContext context) => _style(context);

  static ButtonStyle _style(
    BuildContext context, {
    bool filled = false,
    bool outlined = false,
  }) {
    final ink = DefensysTokens.textPrimaryOf(context);
    final foreground = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.5);
      }
      return filled ? Colors.white : ink;
    });

    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(0, DefensysTokens.buttonHeightPrimary),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      visualDensity: VisualDensity.standard,
      elevation: const WidgetStatePropertyAll(0),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: foreground,
      iconColor: foreground,
      iconSize: const WidgetStatePropertyAll(18),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (filled) {
          if (states.contains(WidgetState.disabled)) {
            return DefensysTokens.borderOf(context);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return DefensysTokens.isDark(context)
                ? DefensysTokens.maroon
                : DefensysTokens.maroonDark;
          }
          return DefensysTokens.maroonOf(context);
        }
        return outlined
            ? DefensysTokens.surfaceOf(context)
            : Colors.transparent;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        final color = filled ? Colors.white : ink;
        if (states.contains(WidgetState.pressed)) {
          return color.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.focused)) {
          return color.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.hovered)) {
          return color.withValues(alpha: 0.06);
        }
        return Colors.transparent;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused) &&
            !states.contains(WidgetState.disabled)) {
          return BorderSide(color: filled ? Colors.white : ink, width: 2);
        }
        return BorderSide(
          color: outlined
              ? DefensysTokens.borderOf(context)
              : Colors.transparent,
        );
      }),
    );
  }
}
