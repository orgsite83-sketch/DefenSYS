import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';

/// Neutral shadcn controls that follow the portal's light and dark surfaces.
class DefensysShadcnScope extends StatelessWidget {
  const DefensysShadcnScope({
    super.key,
    required this.child,
    this.maroonActions = false,
  });
  final Widget child;
  final bool maroonActions;

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
        outlineButtonTheme: maroonActions
            ? ShadButtonTheme(
                foregroundColor: DefensysTokens.textPrimaryOf(context),
                hoverForegroundColor: DefensysTokens.textPrimaryOf(context),
              )
            : null,
        colorScheme: scheme.copyWith(
          primary: maroonActions ? DefensysTokens.maroon : scheme.primary,
          primaryForeground: maroonActions
              ? Colors.white
              : scheme.primaryForeground,
          ring: maroonActions ? DefensysTokens.maroon : scheme.ring,
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
