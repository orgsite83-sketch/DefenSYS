import 'package:flutter/material.dart';

import 'defensys_tokens.dart';

/// Backward-compatible color aliases — prefer [DefensysTokens] in new code.
class AppColors {
  static const maroon = DefensysTokens.maroon;
  static const maroonDark = DefensysTokens.maroonDark;
  static const maroonLight = DefensysTokens.maroonLight;
  static const gold = DefensysTokens.gold;
  static const goldLight = DefensysTokens.goldLight;
  static const background = DefensysTokens.background;
  static const surface = DefensysTokens.surface;
  static const textPrimary = DefensysTokens.textPrimary;
  static const textSecondary = DefensysTokens.textSecondary;
  static const success = DefensysTokens.success;
  static const warning = DefensysTokens.warning;
  static const danger = DefensysTokens.danger;
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        fontFamily: DefensysTokens.fontFamilyInter,
        scaffoldBackgroundColor: DefensysTokens.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: DefensysTokens.maroon,
          primary: DefensysTokens.maroon,
          secondary: DefensysTokens.gold,
          surface: DefensysTokens.surface,
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: DefensysTokens.maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: DefensysTokens.appBarTitle,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: DefensysTokens.maroon.withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.maroon);
            }
            return const TextStyle(
                fontSize: 12, color: DefensysTokens.textPrimary);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(
                  color: DefensysTokens.maroon, size: 22);
            }
            return const IconThemeData(
                color: DefensysTokens.textSecondary, size: 22);
          }),
          elevation: 8,
          shadowColor: Colors.black12,
        ),
        cardTheme: CardThemeData(
          color: DefensysTokens.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            side: const BorderSide(color: DefensysTokens.border, width: 1.0),
          ),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysTokens.maroon,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            textStyle: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: -0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: DefensysTokens.maroon,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            side: const BorderSide(color: DefensysTokens.border, width: 1.0),
            textStyle: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: -0.1,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: const BorderSide(color: DefensysTokens.border, width: 1.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: const BorderSide(color: DefensysTokens.border, width: 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
          ),
          labelStyle: const TextStyle(
            color: DefensysTokens.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        dividerTheme: const DividerThemeData(
          color: DefensysTokens.border,
          thickness: 1.0,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
          ),
          side: const BorderSide(color: DefensysTokens.border, width: 1.0),
          backgroundColor: DefensysTokens.neutralBg,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: DefensysTokens.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 4,
          shadowColor: const Color(0x1F000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
            side: const BorderSide(color: DefensysTokens.border, width: 1.0),
          ),
          titleTextStyle: DefensysTokens.dialogTitle,
          contentTextStyle: DefensysTokens.dialogContent,
        ),
      );

  static ThemeData get lightTheme => theme;

  static ThemeData get mistDarkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: DefensysTokens.fontFamilyInter,
        scaffoldBackgroundColor: DefensysTokens.mistBackground,
        colorScheme: ColorScheme.dark(
          primary: DefensysTokens.mistMaroon,
          secondary: DefensysTokens.mistGold,
          surface: DefensysTokens.mistSurface,
          onSurface: DefensysTokens.mistTextPrimary,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          outline: DefensysTokens.mistBorder,
          brightness: Brightness.dark,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: DefensysTokens.mistPanel,
          foregroundColor: DefensysTokens.mistTextPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: DefensysTokens.appBarTitle.copyWith(
            color: DefensysTokens.mistTextPrimary,
          ),
        ),
        cardTheme: CardThemeData(
          color: DefensysTokens.mistSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            side: const BorderSide(color: DefensysTokens.mistBorder, width: 1.0),
          ),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysTokens.mistMaroon,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            textStyle: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: -0.1,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: DefensysTokens.mistTextPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            side: const BorderSide(color: DefensysTokens.mistBorder, width: 1.0),
            textStyle: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: -0.1,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: DefensysTokens.mistInputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: const BorderSide(color: DefensysTokens.mistBorder, width: 1.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: const BorderSide(color: DefensysTokens.mistBorder, width: 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: const BorderSide(color: DefensysTokens.mistMaroon, width: 1.5),
          ),
          labelStyle: const TextStyle(
            color: DefensysTokens.mistTextSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          hintStyle: const TextStyle(
            color: Color(0xFF71717A),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        dividerTheme: const DividerThemeData(
          color: DefensysTokens.mistBorder,
          thickness: 1.0,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
          ),
          side: const BorderSide(color: DefensysTokens.mistBorder, width: 1.0),
          backgroundColor: DefensysTokens.mistInputFill,
          labelStyle: const TextStyle(color: DefensysTokens.mistTextPrimary),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: DefensysTokens.mistSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 4,
          shadowColor: const Color(0x66000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
            side: const BorderSide(color: DefensysTokens.mistBorder, width: 1.0),
          ),
          titleTextStyle: DefensysTokens.dialogTitle.copyWith(
            color: DefensysTokens.mistTextPrimary,
          ),
          contentTextStyle: DefensysTokens.dialogContent.copyWith(
            color: DefensysTokens.mistTextSecondary,
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: DefensysTokens.mistSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            side: const BorderSide(color: DefensysTokens.mistBorder, width: 1.0),
          ),
          textStyle: const TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            color: DefensysTokens.mistTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}

