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
        fontFamily: DefensysTokens.fontFamily,
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
              borderRadius: BorderRadius.circular(DefensysTokens.radiusXl)),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysTokens.maroon,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(DefensysTokens.radiusMd)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: DefensysTokens.background,
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide: const BorderSide(color: DefensysTokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(DefensysTokens.radiusMd),
            borderSide:
                const BorderSide(color: DefensysTokens.maroon, width: 2),
          ),
          labelStyle: const TextStyle(
              color: DefensysTokens.textSecondary, fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        dividerTheme: const DividerThemeData(
            color: DefensysTokens.background, thickness: 1),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(DefensysTokens.radiusPill)),
          side: BorderSide.none,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: DefensysTokens.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(DefensysTokens.radiusLg),
            side: const BorderSide(color: DefensysTokens.border),
          ),
          titleTextStyle: DefensysTokens.dialogTitle,
          contentTextStyle: DefensysTokens.dialogContent,
        ),
      );
}
