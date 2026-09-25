import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/theme_provider.dart';
import '../../theme/defensys_tokens.dart';

/// Tactile, micro-animated header button to toggle between Light and Mist Dark mode.
class DefensysThemeToggle extends ConsumerWidget {
  final double size;

  const DefensysThemeToggle({
    super.key,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tooltip = isDark ? 'Switch to Light Mode' : 'Switch to Mist Dark';

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        onTap: () {
          ref.read(themeModeProvider.notifier).toggleTheme();
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? const Color(0xFF28272D)
                : const Color(0xFFF1F5F9),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF35343A)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) {
                return RotationTransition(
                  turns: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: isDark
                  ? Icon(
                      Icons.light_mode_rounded,
                      key: const ValueKey('sun_icon'),
                      color: DefensysTokens.mistGold,
                      size: size,
                    )
                  : Icon(
                      Icons.bedtime_outlined,
                      key: const ValueKey('moon_icon'),
                      color: DefensysTokens.steelGrey,
                      size: size,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
