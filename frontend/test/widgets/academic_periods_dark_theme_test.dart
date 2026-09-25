import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';

class _FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState(
      isLoading: false,
      schoolYears: [
        {
          'id': 1,
          'label': '2025-2026',
          'semesters': [
            {'id': 10, 'label': '1st Semester', 'is_active': true},
          ],
        }
      ],
      selectedSchoolYearId: 1,
      activeSemester: {
        'id': 10,
        'display_name': '1st Semester, A.Y. 2025-2026',
        'capstone_program_phase': 'capstone_2',
        'capstone_team_creation_enabled': true,
        'capstone_peer_evaluation_enabled': true,
        'capstone_adviser_grading_enabled': true,
      },
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

void main() {
  testWidgets('AcademicPeriodsScreen renders with Mist Dark surfaces in dark mode',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academicPeriodProvider.overrideWith(_FakeAcademicPeriodNotifier.new),
        ],
        child: MaterialApp(
          theme: AppTheme.mistDarkTheme,
          home: const Scaffold(
            body: AcademicPeriodsScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Academic Period Management header & cards are present
    expect(find.text('Academic Period Management'), findsOneWidget);
    expect(find.text('Capstone program'), findsOneWidget);
    expect(find.text('School Years'), findsOneWidget);
    expect(find.text('Semesters (A.Y. 2025-2026)'), findsOneWidget);

    // Verify the School Years Card surface color is Mist Dark Surface
    final schoolYearsCard = find.ancestor(
      of: find.text('School Years'),
      matching: find.byType(Container),
    );
    final container = tester.widget<Container>(schoolYearsCard.first);
    final boxDecoration = container.decoration as BoxDecoration?;
    expect(boxDecoration?.color, equals(DefensysTokens.mistSurface));
    expect((boxDecoration?.border as Border?)?.top.color, equals(DefensysTokens.mistBorder));

    // Verify the Capstone Program Card surface is Mist Dark Surface
    final capstoneCard = find.ancestor(
      of: find.text('Capstone program'),
      matching: find.byType(Container),
    );
    final capstoneContainer = tester.widget<Container>(capstoneCard.first);
    final capstoneDecoration = capstoneContainer.decoration as BoxDecoration?;
    expect(capstoneDecoration?.color, equals(DefensysTokens.mistSurface));

    // Verify the Status Banner has dark crimson styling instead of flat red
    final statusBannerFinder = find.ancestor(
      of: find.text('Currently Active: 1st Semester, A.Y. 2025-2026'),
      matching: find.byType(Container),
    );
    final bannerContainer = tester.widget<Container>(statusBannerFinder.first);
    final bannerDecoration = bannerContainer.decoration as BoxDecoration?;
    expect(bannerDecoration?.color, equals(const Color(0xFF2E1014)));
  });
}
