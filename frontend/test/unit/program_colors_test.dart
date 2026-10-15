import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/theme/program_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (first > second ? first + .05 : second + .05) /
      (first > second ? second + .05 : first + .05);
}

void main() {
  test(
    'track resolution follows record identity, including legacy aliases',
    () {
      for (final data in <Map>[
        {'isCapstone': false},
        {'is_capstone': false},
        {'is_pit': true},
        {'scope': 'pit'},
        {'type': 'PIT'},
        {'level': '1st Year PIT'},
        {'level': '2nd Year PIT'},
        {'level': '3rd Year PIT'},
      ]) {
        expect(programTrack(data: data), ProgramTrack.pit);
      }
      for (final data in <Map>[
        {'isCapstone': true},
        {'is_capstone': true},
        {'is_pit': false},
        {'program_scope': 'capstone'},
        {'level': '3rd Year Capstone'},
        {'level': '4th Year Capstone'},
      ]) {
        expect(programTrack(data: data), ProgramTrack.capstone);
      }
      expect(
        programTrack(scope: 'capstone', data: {'type': 'pit'}),
        ProgramTrack.pit,
      );
      expect(
        programTrack(data: {'is_capstone': true, 'level': '1st Year PIT'}),
        ProgramTrack.capstone,
      );
    },
  );

  test(
    'unknown and mixed contexts are neutral; roles and years do not set track',
    () {
      for (final scope in [null, '', 'all', 'admin', 'PIT & Capstone']) {
        expect(programTrack(scope: scope), ProgramTrack.unknown);
      }
      expect(
        programTrack(data: {'year_level': '3rd Year', 'role': 'pit_lead'}),
        ProgramTrack.unknown,
      );
    },
  );

  test('cohort identity survives reordered or partial analytics results', () {
    final rows = [
      {'title': '4th Year Capstone'},
      {'title': '2nd Year PIT'},
    ];
    expect(programTrack(data: rows.first), ProgramTrack.capstone);
    expect(programTrack(data: rows.last), ProgramTrack.pit);
  });

  for (final dark in [false, true]) {
    for (final track in ProgramTrack.values) {
      test('$track has readable labels and filled surfaces in dark=$dark', () {
        final colors = ProgramColors.resolve(dark: dark, track: track);
        final surface = dark ? DefensysTokens.mistSurface : Colors.white;
        final badgeBackground = Color.alphaBlend(colors.tint, surface);
        expect(_contrast(colors.text, surface), greaterThanOrEqualTo(4.5));
        expect(
          _contrast(colors.text, badgeBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(Colors.white, colors.accent),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  }
}
