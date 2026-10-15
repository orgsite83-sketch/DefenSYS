import 'package:flutter/material.dart';

import 'defensys_tokens.dart';

enum ProgramTrack { pit, capstone, unknown }

/// Program identity comes from the record, independently of user roles or years.
ProgramTrack programTrack({String? scope, Map? data, bool? isCapstone}) {
  ProgramTrack parse(dynamic value) {
    final label = value?.toString().trim().toLowerCase() ?? '';
    final capstone = RegExp(r'\bcapstone\b').hasMatch(label);
    final pit = RegExp(r'\bpit\b').hasMatch(label);
    if (capstone && pit) return ProgramTrack.unknown;
    if (capstone) return ProgramTrack.capstone;
    if (pit) return ProgramTrack.pit;
    return ProgramTrack.unknown;
  }

  if (isCapstone != null) {
    return isCapstone ? ProgramTrack.capstone : ProgramTrack.pit;
  }
  for (final key in ['is_capstone', 'isCapstone']) {
    if (data?[key] is bool) {
      return data![key] == true ? ProgramTrack.capstone : ProgramTrack.pit;
    }
  }
  if (data?['is_pit'] is bool) {
    return data!['is_pit'] == true ? ProgramTrack.pit : ProgramTrack.capstone;
  }
  for (final key in ['scope', 'program_scope', 'type', 'level', 'title']) {
    final track = parse(data?[key]);
    if (track != ProgramTrack.unknown) return track;
  }
  return parse(scope);
}

/// Program identity for badges, small avatars and type markers.
/// Use DefensysTokens brand colors for controls and neutral colors for content.
class ProgramColors {
  const ProgramColors._({
    required this.track,
    required this.accent,
    required this.text,
    required this.tint,
    required this.border,
    required this.hover,
  });

  static const pit = Color(0xFF426789);
  static const capstone = DefensysTokens.maroon;

  final ProgramTrack track;
  final Color accent;
  final Color text;
  final Color tint;
  final Color border;
  final Color hover;

  String get label => switch (track) {
    ProgramTrack.pit => 'PIT',
    ProgramTrack.capstone => 'Capstone',
    ProgramTrack.unknown => 'General',
  };

  static ProgramColors of(
    BuildContext context, {
    String? scope,
    Map? data,
    bool? isCapstone,
  }) => resolve(
    dark: Theme.of(context).brightness == Brightness.dark,
    track: programTrack(scope: scope, data: data, isCapstone: isCapstone),
  );

  static ProgramColors resolve({
    required bool dark,
    required ProgramTrack track,
  }) {
    final accent = switch (track) {
      ProgramTrack.pit => pit,
      ProgramTrack.capstone => capstone,
      ProgramTrack.unknown => DefensysTokens.textSecondary,
    };
    return ProgramColors._(
      track: track,
      accent: accent,
      text: dark
          ? switch (track) {
              ProgramTrack.pit => const Color(0xFFB0C4D8),
              ProgramTrack.capstone => DefensysTokens.mistMaroonText,
              ProgramTrack.unknown => DefensysTokens.mistTextSecondary,
            }
          : accent,
      tint: dark
          ? accent.withValues(alpha: .18)
          : switch (track) {
              ProgramTrack.pit => const Color(0xFFF1F5F8),
              ProgramTrack.capstone => const Color(0xFFF9EFEE),
              ProgramTrack.unknown => DefensysTokens.neutralBg,
            },
      border: dark
          ? accent.withValues(alpha: .55)
          : switch (track) {
              ProgramTrack.pit => const Color(0xFFCEDBE7),
              ProgramTrack.capstone => const Color(0xFFE8C7C4),
              ProgramTrack.unknown => DefensysTokens.neutralBorder,
            },
      hover: switch (track) {
        ProgramTrack.pit => const Color(0xFF34536F),
        ProgramTrack.capstone => DefensysTokens.maroonDark,
        ProgramTrack.unknown => DefensysTokens.textDark,
      },
    );
  }
}
