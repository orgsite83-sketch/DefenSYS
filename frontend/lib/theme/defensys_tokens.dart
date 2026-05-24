import 'package:flutter/material.dart';

/// Single source of truth for DefenSYS design tokens.
class DefensysTokens {
  DefensysTokens._();

  static const fontFamily = 'Poppins';

  // Brand colors
  static const maroon = Color(0xFF7A110A);
  static const maroonDark = Color(0xFF5E0D08);
  static const maroonLight = Color(0xFFB91C1C);
  static const gold = Color(0xFFD97706);
  static const goldLight = Color(0xFFF59E0B);

  // Neutrals
  static const background = Color(0xFFF3F4F6);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF111827);
  static const textDark = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF6B7280);
  // Contrast (WCAG AA, normal text): textSecondary on white ~4.6:1 (pass);
  // on background ~4.0:1 (borderline — use textPrimary for small labels).
  // gold (#D97706) on white ~3.2:1 — accent/icons only, not body text.
  static const steelGrey = Color(0xFF6B7280);
  static const neutralText = Color(0xFF374151);
  static const border = Color(0xFFE5E7EB);
  static const switchInactiveTrack = Color(0xFFD1D5DB);

  // Semantic colors
  static const success = Color(0xFF10B981);
  static const successBg = Color(0xFFD1FAE5);
  static const successText = Color(0xFF065F46);
  static const successBorder = Color(0xFFA7F3D0);
  static const warning = Color(0xFFF59E0B);
  static const warningBg = Color(0xFFFEF3C7);
  static const warningText = Color(0xFF92400E);
  static const warningBorder = Color(0xFFFDE68A);
  static const danger = Color(0xFFDC2626);
  static const dangerBg = Color(0xFFFEE2E2);
  static const dangerText = Color(0xFF991B1B);
  static const dangerBorder = Color(0xFFFECACA);
  static const infoBg = Color(0xFFDBEAFE);
  static const infoText = Color(0xFF1E40AF);
  static const infoBorder = Color(0xFFBFDBFE);
  static const neutralBg = Color(0xFFF3F4F6);
  static const neutralBorder = Color(0xFFE5E7EB);
  static const techBlue = Color(0xFF3B82F6);

  // Spacing scale
  static const spacingXs = 4.0;
  static const spacingSm = 8.0;
  static const spacingMd = 12.0;
  static const spacingLg = 16.0;
  static const spacingXl = 20.0;
  static const spacing2xl = 24.0;
  static const spacing3xl = 32.0;
  static const spacing4xl = 40.0;

  // Radius scale
  static const radiusSm = 8.0;
  static const radiusMd = 10.0;
  static const radiusLg = 12.0;
  static const radiusXl = 16.0;
  static const radiusPill = 20.0;

  // Layout (web admin)
  static const sidebarWidth = 260.0;
  static const minDesktopWidth = 1180.0;
  static const topNavHeight = 70.0;
  static const contentPadding = EdgeInsets.fromLTRB(40, 20, 40, 36);

  // Typography
  static TextStyle get pageTitle => const TextStyle(
        fontFamily: fontFamily,
        color: maroon,
        fontSize: 21,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      );

  static TextStyle get sectionTitle => const TextStyle(
        fontFamily: fontFamily,
        color: textDark,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get subtitle => const TextStyle(
        fontFamily: fontFamily,
        color: steelGrey,
        fontSize: 13,
        height: 1.45,
      );

  static TextStyle get body => const TextStyle(
        fontFamily: fontFamily,
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: fontFamily,
        color: textSecondary,
        fontSize: 12,
      );

  static TextStyle get tableHeader => const TextStyle(
        fontFamily: fontFamily,
        color: steelGrey,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.45,
      );

  static TextStyle get tableCell => const TextStyle(
        fontFamily: fontFamily,
        color: neutralText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get appBarTitle => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.3,
      );

  static TextStyle get dialogTitle => const TextStyle(
        fontFamily: fontFamily,
        color: textDark,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      );

  static TextStyle get dialogContent => const TextStyle(
        fontFamily: fontFamily,
        color: textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.45,
      );

  static BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radiusLg),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }
}
