import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';

/// Neutral shadcn controls that follow the portal's light and dark surfaces.
class DefensysShadcnScope extends StatelessWidget {
  const DefensysShadcnScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = DefensysTokens.isDark(context);
    final scheme = dark
        ? const ShadZincColorScheme.dark()
        : const ShadZincColorScheme.light();
    return ShadTheme(
      data: ShadThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        radius: BorderRadius.circular(DefensysTokens.radiusMd),
        textTheme: ShadTextTheme(family: DefensysTokens.fontFamilyInter),
        colorScheme: scheme.copyWith(
          background: DefensysTokens.surfaceOf(context),
          foreground: DefensysTokens.textPrimaryOf(context),
          popover: DefensysTokens.surfaceOf(context),
          popoverForeground: DefensysTokens.textPrimaryOf(context),
          border: DefensysTokens.borderOf(context),
          input: DefensysTokens.borderOf(context),
          mutedForeground: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: DefensysTokens.textPrimaryOf(context)),
        child: child,
      ),
    );
  }
}
