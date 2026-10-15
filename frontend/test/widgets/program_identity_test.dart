import 'package:defensys/screens/app/student/team_tab.dart';
import 'package:defensys/screens/web/admin/curriculum_analytics/widgets/curriculum_cohort_progression_card.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/theme/program_colors.dart';
import 'package:defensys/widgets/program_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

void main() {
  for (final dark in [false, true]) {
    for (final capstone in [false, true]) {
      for (final width in [420.0, 1200.0]) {
        testWidgets(
          '${capstone ? 'Capstone' : 'PIT'} team identity at $width in dark=$dark',
          (tester) async {
            tester.view.physicalSize = Size(width, 1100);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await loadPreviewFonts(force: true);
            await pumpDefensysWidget(
              tester,
              RepaintBoundary(
                key: const ValueKey('program-preview'),
                child: TeamTab(
                  studentData: {
                    'year_level': capstone ? '4th Year' : '1st Year',
                    'student': {'id': 1, 'name': 'Maria Santos'},
                    'team': {
                      'id': 7,
                      'name': 'Team FreshStartEvents',
                      'projectTitle':
                          'Freshman Welcome Week & Seminar Attendance Module',
                      'isCapstone': capstone,
                      'level': capstone ? '4th Year Capstone' : '1st Year PIT',
                      'year_level': capstone ? '4th Year' : '1st Year',
                      'section': 'BSIT-1B',
                      'semester': '1st Semester',
                      'schoolYear': '2026-2027',
                    },
                    'members': <Map<String, dynamic>>[],
                  },
                ),
              ),
              theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            );

            final badge = find.byType(ProgramBadge);
            expect(badge, findsOneWidget);
            final label = tester.widget<Text>(
              find.descendant(of: badge, matching: find.byType(Text)),
            );
            final colors = ProgramColors.resolve(
              dark: dark,
              track: capstone ? ProgramTrack.capstone : ProgramTrack.pit,
            );
            expect(label.style?.color, colors.text);
            expect(
              tester.widget<Text>(find.text('FS')).style?.color,
              colors.text,
            );
            expect(label.data, capstone ? 'Capstone Project' : '1st Year PIT');
            expect(
              tester.widget<Text>(find.text('Reviews Pending')).style?.color,
              DefensysTokens.dangerText,
            );
            expect(find.text('Team FreshStartEvents'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await capturePreview(
              tester,
              find.byKey(const ValueKey('program-preview')),
              'program-${capstone ? 'capstone' : 'pit'}-${dark ? 'dark' : 'light'}-${width.toInt()}',
            );
          },
        );
      }
    }
  }

  testWidgets(
    'cohort badges follow reordered records rather than list position',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts(force: true);
      await pumpDefensysWidget(
        tester,
        const CurriculumCohortProgressionCard(
          cohortProgression: [
            {'title': '4th Year Capstone', 'phase': 'Defense'},
            {'title': '2nd Year PIT', 'phase': 'Systems'},
          ],
        ),
      );
      expect(
        tester.widget<Text>(find.text('4th Year Capstone')).style?.color,
        ProgramColors.capstone,
      );
      expect(
        tester.widget<Text>(find.text('2nd Year PIT')).style?.color,
        ProgramColors.pit,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
