import 'package:flutter/material.dart';
import '../../../../../theme/defensys_tokens.dart';

/// Chart marks use the portal's maroon family; controls retain the shared shadcn theme.
abstract final class CurriculumChartPalette {
  static Color primary(BuildContext context) => DefensysTokens.isDark(context)
      ? const Color(0xFFD4776D)
      : DefensysTokens.maroon;
  static Color secondary(BuildContext context) => DefensysTokens.isDark(context)
      ? const Color(0xFFE2B2AC)
      : const Color(0xFFBE8079);
  static Color neutral(BuildContext context) => DefensysTokens.isDark(context)
      ? const Color(0xFFA3AFBF)
      : const Color(0xFF94A3B8);
  static Color evaluator(BuildContext context, String role) => switch (role) {
    'peer' => secondary(context),
    'adviser' => neutral(context),
    _ => primary(context),
  };
  static Color slice(BuildContext context, int index) => switch (index) {
    0 => primary(context),
    1 => secondary(context),
    _ => neutral(context),
  };
}
