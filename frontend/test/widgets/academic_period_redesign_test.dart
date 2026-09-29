import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/screens/web/admin/academic_periods/semester_detail_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/admin/user_management_provider.dart';

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

class _FakeUserManagementNotifier extends UserManagementNotifier {
  @override
  UserManagementState build() {
    return const UserManagementState(
      isLoading: false,
      users: [
        {
          'id': 101,
          'name': 'Prof. Alan Turing',
          'email': 'aturing@university.edu',
          'is_pit_lead': true,
          'pit_lead_year': '1st Year',
        },
      ],
    );
  }

  @override
  Future<void> fetchUsers({String? search, String? role, String? successMessage}) async {}
}

class _FakeDefenseSchedulerNotifier extends DefenseSchedulerNotifier {
  final List<Map<String, dynamic>> _configs = [
    {
      'id': 201,
      'event_name': 'CS 101 Concept Pitch',
      'panel_weight': 80,
      'peer_weight': 20,
      'peer_grading_enabled': true,
      'is_locked': false,
    },
    {
      'id': 202,
      'event_name': 'CS 201 Architecture Demo',
      'panel_weight': 80,
      'peer_weight': 20,
      'peer_grading_enabled': false,
      'is_locked': true,
      'lock_reason': 'Defenses already scheduled for sophomore cohort',
    },
  ];

  @override
  DefenseSchedulerState build() {
    return const DefenseSchedulerState();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPitEventConfigs(
      {int? semesterId}) async {
    return _configs;
  }

  @override
  Future<bool> savePitEventConfig(Map<String, dynamic> payload) async {
    return true;
  }
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
          userManagementProvider
              .overrideWith(_FakeUserManagementNotifier.new),
          defenseSchedulerProvider
              .overrideWith(_FakeDefenseSchedulerNotifier.new),
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

    // Verify PIT Governance Banner
    expect(find.text('Faculty Lead Ownership & Admin Oversight'),
        findsOneWidget);
    expect(find.text('Governance Model'), findsOneWidget);
    expect(find.text('PIT Coordinator (Faculty Lead)'), findsOneWidget);
    expect(
        find.text('Administrator (Institutional Oversight)'), findsOneWidget);

    // Verify PIT-specific rules: 80% Panelist, 20% Peer, and NO adviser note
    expect(find.text('📌 PIT Cohort Structure (1st–3rd Year)'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(
        find.textContaining(
            'Note: PIT does NOT have assigned faculty advisers.'),
        findsOneWidget);

    // Verify 3 Cohort breakdown cards
    expect(find.text('1st Year Cohort — CS 101'), findsOneWidget);
    expect(find.text('2nd Year Cohort — CS 201'), findsOneWidget);
    expect(find.text('3rd Year Cohort — CS 301'), findsOneWidget);

    // Verify Assigned Coordinator for 1st Year (Prof. Alan Turing)
    expect(find.text('Prof. Alan Turing'), findsOneWidget);

    // Verify Unassigned Coordinator prompt for cohorts without assigned lead
    expect(find.text('Assign Lead ↗'), findsWidgets);

    // Verify Configured PIT Events for cohorts
    expect(find.text('CS 101 Concept Pitch'), findsOneWidget);
    expect(find.text('CS 201 Architecture Demo'), findsOneWidget);
    expect(find.text('Defenses Scheduled (Locked)'), findsOneWidget);

    // Verify interactive Peer Evaluation switches
    final switches = find.byType(Switch);
    expect(switches, findsWidgets);

    // Tap peer evaluation toggle on 1st event
    await tester.ensureVisible(switches.first);
    await tester.tap(switches.first);
    await tester.pumpAndSettle();

    // 7. Switch to Tab 3: Master Controls & Logs
    await tester.ensureVisible(find.text('⚙️ Master Controls & Logs'));
    await tester.tap(find.text('⚙️ Master Controls & Logs'));
    await tester.pumpAndSettle();

    expect(find.text('⚙️ Semester Lifecycle & Status'), findsOneWidget);
    expect(find.text('⚠️ Danger Zone'), findsOneWidget);

    // 8. Test Back Button returns to Academic Cycles Hub
    await tester.tap(find.text('Back to Academic Cycles'));
    await tester.pumpAndSettle();

    expect(find.text('A.Y. 2026-2027'), findsOneWidget);
    expect(find.text('Manage Active Term ↗'), findsOneWidget);

    // 9. Verify [ ··· ] More Options popup menu on semester rows
    final moreOptionsButtons = find.byTooltip('More options');
    expect(moreOptionsButtons, findsWidgets);

    // Tap more options on the 2nd Semester (inactive term, index 1)
    await tester.tap(moreOptionsButtons.at(1));
    await tester.pumpAndSettle();

    expect(find.text('Set as Active Semester'), findsOneWidget);
    expect(find.text('Delete Semester'), findsOneWidget);

    // Dismiss menu
    await tester.tapAt(const Offset(50, 50));
    await tester.pumpAndSettle();

    // 10. Test Collapsing (Minimizing) the School Year Card
    // Tap on the header of A.Y. 2026-2027 to collapse it
    await tester.tap(find.text('A.Y. 2026-2027'));
    await tester.pumpAndSettle();

    // The terms table under A.Y. 2026-2027 should now be collapsed/minimized
    expect(find.text('1st Semester'), findsNothing);
    expect(find.text('2nd Semester'), findsNothing);

    // Tap on the header again to expand it back
    await tester.tap(find.text('A.Y. 2026-2027'));
    await tester.pumpAndSettle();

    // The terms table should be visible again
    expect(find.text('1st Semester'), findsWidgets);
    expect(find.text('2nd Semester'), findsWidgets);
  });
}
