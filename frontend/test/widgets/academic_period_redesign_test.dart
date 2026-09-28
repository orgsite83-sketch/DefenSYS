import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/screens/web/admin/academic_periods/semester_detail_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';

class _FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState(
      isLoading: false,
      schoolYears: [
        {
          'id': 1,
          'label': '2026-2027',
          'semesters': [
            {
              'id': 10,
              'label': '1st Semester',
              'is_active': true,
              'capstone_program_phase': 'capstone_2',
              'capstone_team_creation_enabled': true,
              'capstone_peer_evaluation_enabled': true,
              'capstone_adviser_grading_enabled': true,
            },
            {
              'id': 11,
              'label': '2nd Semester',
              'is_active': false,
              'capstone_program_phase': 'capstone_1',
              'capstone_team_creation_enabled': false,
              'capstone_peer_evaluation_enabled': false,
              'capstone_adviser_grading_enabled': false,
            },
          ],
        },
        {
          'id': 2,
          'label': '2025-2026',
          'semesters': [
            {
              'id': 9,
              'label': '1st Semester',
              'is_active': false,
            },
          ],
        },
      ],
      selectedSchoolYearId: 1,
      activeSemester: {
        'id': 10,
        'school_year_id': 1,
        'display_name': '1st Semester, A.Y. 2026-2027',
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

class _FakeDefenseStagesNotifier extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() {
    return const DefenseStagesState(
      isLoading: false,
      stages: [
        {
          'id': 1,
          'label': 'Title Proposal',
          'description': 'Topic and concept defense',
          'is_presentation_only': true,
        },
        {
          'id': 2,
          'label': 'Outline Defense',
          'description': 'Chapters 1-3 manuscript review',
          'is_presentation_only': false,
        },
        {
          'id': 3,
          'label': 'Final Defense',
          'description': 'Full system demo and manuscript',
          'is_presentation_only': false,
        },
      ],
    );
  }

  @override
  Future<void> fetchStages({String? successMessage}) async {}
}

void main() {
  testWidgets(
      'AcademicPeriod Redesign: Accordion renders and drill-down into SemesterDetailScreen shows Capstone and PIT tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academicPeriodProvider
              .overrideWith(_FakeAcademicPeriodNotifier.new),
          defenseStagesProvider
              .overrideWith(_FakeDefenseStagesNotifier.new),
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

    // 1. Verify Level 1 Hub: Accordion School Years are present
    expect(find.text('A.Y. 2026-2027'), findsOneWidget);
    expect(find.text('A.Y. 2025-2026'), findsOneWidget);
    expect(find.text('CURRENTLY ACTIVE'), findsOneWidget);

    // 2. Verify that active A.Y. 2026-2027 is expanded and shows its terms
    expect(find.text('1st Semester'), findsWidgets);
    expect(find.text('2nd Semester'), findsWidgets);
    expect(find.text('Active (Write-Enabled)'), findsWidgets);
    expect(find.text('Capstone 2 Continue'), findsOneWidget);
    expect(find.text('PIT Active'), findsWidgets);

    // 3. Tap "Manage" button on 1st Semester to open SemesterDetailScreen
    final manageButtons = find.text('Manage');
    expect(manageButtons, findsWidgets);
    await tester.tap(manageButtons.first);
    await tester.pumpAndSettle();

    // 4. Verify SemesterDetailScreen Command Center is loaded
    expect(find.text('Back to Academic Cycles'), findsOneWidget);
    expect(find.text('🎓 Capstone Program (4th Year)'), findsOneWidget);
    expect(find.text('🚀 PIT Program (1st–3rd Year)'), findsOneWidget);
    expect(find.text('⚙️ Master Controls & Logs'), findsOneWidget);

    // 5. In Capstone Tab (default selected): verify policies and defense stages pipeline
    expect(find.text('⚙️ Capstone Cohort Policies'), findsOneWidget);
    expect(find.text('📝 Term-Wide Evaluation Master Toggles'), findsOneWidget);
    expect(find.text('🛡️ Capstone Defense Stages Pipeline'), findsOneWidget);
    expect(find.text('Title Proposal'), findsOneWidget);
    expect(find.text('Outline Defense'), findsOneWidget);
    expect(find.text('Final Defense'), findsOneWidget);

    // 6. Switch to Tab 2: PIT Program (1st–3rd Year)
    await tester.tap(find.text('🚀 PIT Program (1st–3rd Year)'));
    await tester.pumpAndSettle();

    // Verify PIT-specific rules: 80% Panelist, 20% Peer, and NO adviser note
    expect(find.text('📌 PIT Cohort Structure (1st–3rd Year)'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(
        find.textContaining(
            'Note: PIT does NOT have assigned faculty advisers.'),
        findsOneWidget);

    // 7. Switch to Tab 3: Master Controls & Logs
    await tester.tap(find.text('⚙️ Master Controls & Logs'));
    await tester.pumpAndSettle();

    expect(find.text('⚙️ Semester Lifecycle & Status'), findsOneWidget);
    expect(find.text('⚠️ Danger Zone'), findsOneWidget);

    // 8. Test Back Button returns to Academic Cycles Hub
    await tester.tap(find.text('Back to Academic Cycles'));
    await tester.pumpAndSettle();

    expect(find.text('A.Y. 2026-2027'), findsOneWidget);
  });
}
