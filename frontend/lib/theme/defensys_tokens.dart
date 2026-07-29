import 'package:flutter/material.dart';

/// Single source of truth for DefenSYS design tokens.
class DefensysTokens {
  DefensysTokens._();

  static const fontFamily = 'Inter';
  static const fontFamilyInter = 'Inter';

  // Brand colors
  static const maroon = Color(0xFF7A110A);
  static const maroonDark = Color(0xFF5E0D08);
  static const maroonLight = Color(0xFF991B1B);
  static const gold = Color(0xFFD97706);
  static const goldLight = Color(0xFFF59E0B);
  static const darkGold = Color(0xFFB45309); // Compliant AA contrast (>4.5:1) for body/labels on white

  // Neutrals (Refined Slate Scale)
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF0F172A);
  static const textDark = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF475569); // WCAG AA compliant contrast (6.5:1 on white)
  static const steelGrey = Color(0xFF64748B);
  static const neutralText = Color(0xFF334155);
  static const border = Color(0xFFE2E8F0); // Crisp hairline border
  static const switchInactiveTrack = Color(0xFFCBD5E1);

  // Semantic colors (Desaturated Tints + WCAG AA Compliant Text)
  static const success = Color(0xFF10B981);
  static const successBg = Color(0xFFECFDF5);
  static const successText = Color(0xFF047857);
  static const successBorder = Color(0xFFA7F3D0);

  static const warning = Color(0xFFF59E0B);
  static const warningBg = Color(0xFFFFFBEB);
  static const warningText = Color(0xFFB45309);
  static const warningBorder = Color(0xFFFDE68A);

  static const danger = Color(0xFFEF4444);
  static const dangerBg = Color(0xFFFEF2F2);
  static const dangerText = Color(0xFFB91C1C);
  static const dangerBorder = Color(0xFFFECACA);

  static const infoBg = Color(0xFFEFF6FF);
  static const infoText = Color(0xFF1D4ED8);
  static const infoBorder = Color(0xFFBFDBFE);

  static const overriddenBg = Color(0xFFEEF2FF);
  static const overriddenText = Color(0xFF4338CA); // WCAG AA Indigo
  static const overriddenBorder = Color(0xFFC7D2FE);

  static const revisionBg = Color(0xFFFFF7ED);
  static const revisionText = Color(0xFFC2410C); // WCAG AA Orange
  static const revisionBorder = Color(0xFFFFEDD5);

  static const archivedBg = Color(0xFFF1F5F9);
  static const archivedText = Color(0xFF475569);
  static const archivedBorder = Color(0xFFCBD5E1);

  static const neutralBg = Color(0xFFF1F5F9);
  static const neutralBorder = Color(0xFFE2E8F0);
  static const techBlue = Color(0xFF2563EB);

  // Button height presets
  static const buttonHeightPrimary = 44.0;
  static const buttonHeightSecondary = 36.0;
  static const buttonHeightSm = 32.0;

  // Spacing scale
  static const spacingXs = 4.0;
  static const spacingSm = 8.0;
  static const spacingMd = 12.0;
  static const spacingLg = 16.0;
  static const spacingXl = 20.0;
  static const spacing2xl = 24.0;
  static const spacing3xl = 32.0;
  static const spacing4xl = 40.0;

  // Standardized radius scale (Shape Consistency Lock)
  static const radiusSm = 6.0;
  static const radiusMd = 8.0;
  static const radiusLg = 12.0;
  static const radiusXl = 16.0;
  static const radiusPill = 999.0;

  // Layout (web admin)
  static const sidebarWidth = 260.0;
  static const minDesktopWidth = 1180.0;
  static const topNavHeight = 70.0;
  static const contentPadding = EdgeInsets.fromLTRB(40, 20, 40, 36);

  // Typography Scale (Inter, modular font sizes & crisp letter spacing)
  static TextStyle get pageTitle => const TextStyle(
        fontFamily: fontFamily,
        color: maroon,
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );

  static TextStyle get sectionTitle => const TextStyle(
        fontFamily: fontFamily,
        color: textDark,
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      );

  static TextStyle get subtitle => const TextStyle(
        fontFamily: fontFamilyInter,
        color: textSecondary,
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get body => const TextStyle(
        fontFamily: fontFamilyInter,
        color: textPrimary,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: fontFamilyInter,
        color: textSecondary,
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get tableHeader => const TextStyle(
        fontFamily: fontFamilyInter,
        color: steelGrey,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      );

  static TextStyle get tableCell => const TextStyle(
        fontFamily: fontFamilyInter,
        color: textPrimary,
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
        fontFamily: fontFamilyInter,
        color: textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
      );

  /// Anti-slop card decoration: clean surface + hairline border + subtle micro-shadow
  static BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radiusLg),
      border: Border.all(color: border, width: 1.0),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000), // 4% micro elevation
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    );
  }

  /// Anti-slop dialog decoration: standardized 16px radius + elevation
  static BoxDecoration dialogDecoration() {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radiusXl),
      border: Border.all(color: border, width: 1.0),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000), // 8% elevation
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    );
  }
}

