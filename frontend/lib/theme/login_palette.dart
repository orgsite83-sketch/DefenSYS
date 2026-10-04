import 'package:flutter/material.dart';

import 'defensys_tokens.dart';

/// Login-specific contrast pairs built on the shared Mist theme surfaces.
/// Links and focus indicators use a lighter brand tint than filled actions.
class LoginPalette {
  const LoginPalette._(this.isDark);

  factory LoginPalette.of(BuildContext context) =>
      LoginPalette._(DefensysTokens.isDark(context));

  final bool isDark;

  Color get background =>
      isDark ? DefensysTokens.mistBackground : DefensysTokens.background;
  Color get panel =>
      isDark ? DefensysTokens.mistPanel : const Color(0xFFF1F5F9);
  Color get surface =>
      isDark ? DefensysTokens.mistSurface : DefensysTokens.surface;
  Color get subtleSurface =>
      isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9);
  Color get inputFill =>
      isDark ? DefensysTokens.mistInputFill : DefensysTokens.background;
  Color get border =>
      isDark ? DefensysTokens.mistBorder : DefensysTokens.border;
  Color get inputBorder =>
      isDark ? const Color(0xFF76737E) : const Color(0xFFCBD5E1);
  Color get primaryText =>
      isDark ? DefensysTokens.mistTextPrimary : DefensysTokens.textPrimary;
  Color get label =>
      isDark ? const Color(0xFFD4D4D8) : DefensysTokens.neutralText;
  Color get secondaryText =>
      isDark ? const Color(0xFFB8B6C0) : DefensysTokens.steelGrey;
  Color get muted =>
      isDark ? const Color(0xFFABA8B4) : DefensysTokens.steelGrey;
  Color get link => isDark ? const Color(0xFFF0A3B2) : const Color(0xFF800020);
  Color get focus => link;
  Color get action =>
      isDark ? const Color(0xFF9B263D) : const Color(0xFF800020);
  Color get actionStart =>
      isDark ? const Color(0xFF852236) : const Color(0xFF6B1124);
  Color get danger =>
      isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
  Color get dangerBackground =>
      isDark ? const Color(0xFF3A2226) : DefensysTokens.dangerBg;
  Color get dangerBorder =>
      isDark ? const Color(0xFF9F4B57) : DefensysTokens.dangerBorder;
  Color get warningBackground =>
      isDark ? const Color(0xFF332A1C) : const Color(0xFFFEF3C7);
  Color get warningText =>
      isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
  Color get warningBorder =>
      isDark ? const Color(0xFFA87920) : DefensysTokens.warning;
  Color get success =>
      isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669);
  Color get successBackground =>
      isDark ? const Color(0xFF18352C) : DefensysTokens.successBg;
}
