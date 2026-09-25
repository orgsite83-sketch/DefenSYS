import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';

/// Single source of truth for DefenSYS data table styling, dimensions, and typography.
class DefensysTableTokens {
  DefensysTableTokens._();

  // Layout Dimensions
  static const double headerHeight = 44.0;
  static const double rowHeightStandard = 56.0;
  static const double rowHeightMultiline = 64.0;
  static const double actionColumnWidth = 80.0;
  static const double cardBorderRadius = 14.0;
  static const double controlHeight = 42.0;

  // Paddings
  static const EdgeInsets cellPaddingStandard = EdgeInsets.symmetric(
    horizontal: 16.0,
    vertical: 12.0,
  );
  static const EdgeInsets headerPaddingStandard = EdgeInsets.symmetric(
    horizontal: 16.0,
    vertical: 10.0,
  );
  static const EdgeInsets cardPadding = EdgeInsets.all(20.0);

  // Colors
  static const Color headerBackground = Color(0xFFF8FAFC);
  static const Color headerBorder = Color(0xFFE2E8F0);
  static const Color rowBorder = Color(0xFFF1F5F9);
  static const Color rowHover = Color(0xFFF8FAFC);
  static const Color cardBackground = Colors.white;
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color searchFieldBackground = Color(0xFFF8FAFC);
  static const Color segmentedControlBackground = Color(0xFFF1F5F9);

  // Dynamic Theme-Aware Color Accessors
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color headerBackgroundOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF1B1B1F) : headerBackground;

  static Color headerBorderOf(BuildContext context) =>
      isDark(context) ? DefensysTokens.mistBorder : headerBorder;

  static Color rowBorderOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF2E2D33) : rowBorder;

  static Color rowHoverOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF28272D) : rowHover;

  static Color cardBackgroundOf(BuildContext context) =>
      isDark(context) ? DefensysTokens.mistSurface : cardBackground;

  static Color cardBorderOf(BuildContext context) =>
      isDark(context) ? DefensysTokens.mistBorder : cardBorder;

  static Color searchFieldBackgroundOf(BuildContext context) =>
      isDark(context) ? DefensysTokens.mistInputFill : searchFieldBackground;

  static Color segmentedControlBackgroundOf(BuildContext context) =>
      isDark(context) ? DefensysTokens.mistInputFill : segmentedControlBackground;

  // Typography
  static const TextStyle headerTextStyle = TextStyle(
    fontFamily: DefensysTokens.fontFamily,
    fontSize: 11.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: Color(0xFF64748B),
  );

  static TextStyle headerTextStyleOf(BuildContext context) => isDark(context)
      ? headerTextStyle.copyWith(color: const Color(0xFFA1A1AA))
      : headerTextStyle;

  static const TextStyle cellPrimaryTextStyle = TextStyle(
    fontFamily: DefensysTokens.fontFamily,
    fontSize: 13.0,
    fontWeight: FontWeight.w700,
    color: Color(0xFF0F172A),
  );

  static TextStyle cellPrimaryTextStyleOf(BuildContext context) =>
      isDark(context)
          ? cellPrimaryTextStyle.copyWith(color: const Color(0xFFF4F4F5))
          : cellPrimaryTextStyle;

  static const TextStyle cellSecondaryTextStyle = TextStyle(
    fontFamily: DefensysTokens.fontFamily,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: Color(0xFF64748B),
  );

  static TextStyle cellSecondaryTextStyleOf(BuildContext context) =>
      isDark(context)
          ? cellSecondaryTextStyle.copyWith(color: const Color(0xFFA1A1AA))
          : cellSecondaryTextStyle;

  static const TextStyle cellBodyTextStyle = TextStyle(
    fontFamily: DefensysTokens.fontFamily,
    fontSize: 13.0,
    fontWeight: FontWeight.w500,
    color: Color(0xFF1E293B),
  );

  static TextStyle cellBodyTextStyleOf(BuildContext context) => isDark(context)
      ? cellBodyTextStyle.copyWith(color: const Color(0xFFE4E4E7))
      : cellBodyTextStyle;

  static const TextStyle paginationTextStyle = TextStyle(
    fontFamily: DefensysTokens.fontFamily,
    fontSize: 12.0,
    fontWeight: FontWeight.w600,
    color: Color(0xFF5D6678),
  );

  static TextStyle paginationTextStyleOf(BuildContext context) =>
      isDark(context)
          ? paginationTextStyle.copyWith(color: const Color(0xFFA1A1AA))
          : paginationTextStyle;

  // Card Decoration
  static BoxDecoration cardDecoration([BuildContext? context]) {
    final dark = context != null && isDark(context);
    return BoxDecoration(
      color: dark ? DefensysTokens.mistSurface : cardBackground,
      borderRadius: BorderRadius.circular(cardBorderRadius),
      border: Border.all(color: dark ? DefensysTokens.mistBorder : cardBorder),
      boxShadow: [
        BoxShadow(
          color: dark
              ? const Color(0x33000000)
              : Colors.black.withValues(alpha: 0.03),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
